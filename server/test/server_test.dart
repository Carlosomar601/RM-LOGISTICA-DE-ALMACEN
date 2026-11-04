import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:riverpod/riverpod.dart';
import 'package:rm_core/api/rm_api.dart';
import 'package:rm_core/backup/backup_service.dart';
import 'package:rm_core/models/inv_row.dart';
import 'package:rm_core/notify/toast_state.dart';
import 'package:rm_core/remote/remote_app_notifier.dart';
import 'package:rm_core/remote/remote_link.dart';
import 'package:rm_core/remote/remote_services.dart';
import 'package:rm_core/remote/wire_state.dart';
import 'package:rm_core/state/app_state.dart';
import 'package:rm_core/sync/sync_service.dart';
import 'package:rm_server/app_server.dart';
import 'package:test/test.dart';

/// Un dispositivo cliente conectado al servidor de prueba.
class Device {
  Device._(this.link, this.container);

  static Future<Device> connect(int port, {String name = 'prueba'}) async {
    final link = RemoteLink(Uri.parse('ws://127.0.0.1:$port/ws'), device: name,
        retryDelays: const [Duration(milliseconds: 50)]);
    final c = ProviderContainer(overrides: [
      remoteLinkProvider.overrideWithValue(link),
      appProvider.overrideWith(RemoteAppNotifier.new),
      syncProvider.overrideWith(RemoteSyncService.new),
      backupProvider.overrideWith(RemoteBackupService.new),
    ]);
    final d = Device._(link, c);
    c.read(appProvider); // se suscribe antes de conectar
    c.read(syncProvider);
    c.read(backupProvider);
    c.listen(toastProvider, (_, m) {
      if (m != null) d.toasts.add(m.text);
    });
    await link.start();
    await until(() => link.online);
    return d;
  }

  final RemoteLink link;
  final ProviderContainer container;
  final toasts = <String>[];

  RemoteAppNotifier get n => container.read(appProvider.notifier) as RemoteAppNotifier;
  AppState get s => container.read(appProvider);

  Future<void> login(String pin) async {
    expect(await n.loginAsync(pin), isNull);
  }

  /// Espera a que el servidor confirme todo lo enviado.
  Future<void> settle() => until(() => n.pendingCount == 0);

  Future<void> close() async {
    await link.close();
    container.dispose();
  }
}

Future<void> until(bool Function() cond, {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('condición no cumplida');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  // Deja llegar los mensajes que vienen detrás (patch → result).
  await Future<void>.delayed(const Duration(milliseconds: 30));
}

int unitsOf(AppState s, String productId) => s.rowsOf(productId).fold(0, (a, r) => a + r.qty);

void main() {
  late ProviderContainer serverContainer;
  late AppServer server;
  final devices = <Device>[];

  AppState serverState() => serverContainer.read(appProvider);

  Future<Device> device(String pin, {String name = 'prueba'}) async {
    final d = await Device.connect(server.port, name: name);
    devices.add(d);
    if (pin.isNotEmpty) await d.login(pin);
    return d;
  }

  setUp(() async {
    serverContainer = ProviderContainer();
    server = AppServer(serverContainer, name: 'servidor-prueba', appVersion: 'test');
    await server.start(port: 0, address: InternetAddress.loopbackIPv4, discovery: false);
  });

  tearDown(() async {
    for (final d in devices) {
      await d.close();
    }
    devices.clear();
    await server.stop();
    serverContainer.dispose();
  });

  test('el estado viaja completo y sin hash de PIN', () {
    final s = serverContainer.read(appProvider);
    final wire = jsonDecode(jsonEncode(encodeWireState(s))) as Map<String, dynamic>;
    expect(jsonEncode(wire), isNot(contains('pinHash')));
    final back = decodeWireState(wire);
    expect(jsonEncode(back.toDataJson()), jsonEncode(s.toDataJson()));
    expect(back.users.map((u) => u.id), s.users.map((u) => u.id));
    expect(back.users.first.hasPin, isTrue);
    expect(back.users.first.checkPin('1111'), isFalse, reason: 'el cliente no puede comprobar PIN');
  });

  test('/health contesta', () async {
    final r = await HttpClient().getUrl(Uri.parse('http://127.0.0.1:${server.port}/health'));
    final body = await (await r.close()).transform(utf8.decoder).join();
    expect(jsonDecode(body)['server'], 'servidor-prueba');
  });

  test('PIN: incorrecto, correcto y bloqueo por dispositivo', () async {
    final d = await device('');
    await until(() => d.s.settings.companyName.isNotEmpty);
    expect(await d.n.loginAsync('9999'), 'PIN incorrecto');
    await d.login('1111');
    expect(d.s.currentUser?.name, 'Carlos Omar');
    expect(d.s.products.length, serverState().products.length);
    expect(serverState().currentUserId, isNull, reason: 'el servidor no queda con sesión propia');
  });

  test('un cambio en un dispositivo aparece en el otro', () async {
    final a = await device('1111', name: 'A');
    final b = await device('2222', name: 'B');
    final before = unitsOf(b.s, 'p1');

    a.n.suggestSingle('p1', 5, 'OV-PRUEBA');
    expect(a.s.pickSessions[a.s.singleKey], isNotNull, reason: 'se ve al instante en A');
    final key = a.s.singleKey;
    for (final st in a.s.pickSessions[key]!.steps.toList()) {
      expect(a.n.stepPicked(key, st.id), isNull);
    }
    expect(a.n.confirmSingle(), isNotNull);
    await a.settle();
    await until(() => unitsOf(b.s, 'p1') == before - 5);

    expect(unitsOf(serverState(), 'p1'), before - 5);
    expect(serverState().history.first.user, 'C. Omar', reason: 'el servidor registra al usuario del dispositivo');
    expect(b.s.pickSessions.containsKey(key), isFalse);
    expect(b.s.pickSessions.containsKey(b.s.singleKey), isFalse, reason: 'cada usuario tiene su piqueo individual');
  });

  test('dos dispositivos mueven la misma mercancía a la vez: uno gana y el otro se deshace', () async {
    final a = await device('1111', name: 'A');
    final b = await device('2222', name: 'B');
    InvRow row(AppState s) => s.inventory.firstWhere((r) => r.productId == 'p1' && r.bin == 'A-01-02');
    final qty = row(serverState()).qty;
    final total = unitsOf(serverState(), 'p1');

    // Ambos ven la canasta llena y la vacían al mismo tiempo, antes de saber del otro.
    expect(a.n.binTransfer(productId: 'p1', srcRowId: row(a.s).id, destBin: 'C-01-01', qty: qty), isNull);
    expect(b.n.binTransfer(productId: 'p1', srcRowId: row(b.s).id, destBin: 'C-01-02', qty: qty), isNull);
    await a.settle();
    await b.settle();

    expect(b.toasts.single, startsWith('No se aplicó'));
    expect(unitsOf(serverState(), 'p1'), total, reason: 'no se crean ni se pierden unidades');
    expect(serverState().inventory.every((r) => r.qty >= 0), isTrue);
    final dest = serverState().inventory.where((r) => r.productId == 'p1' && r.bin == 'C-01-01');
    expect(dest.fold(0, (x, r) => x + r.qty), qty);
    await until(() => jsonEncode(b.s.toDataJson()) == jsonEncode(serverState().toDataJson()));
    expect(jsonEncode(a.s.toDataJson()), jsonEncode(serverState().toDataJson()));
  });

  test('el servidor aplica los permisos aunque la pantalla no los respete', () async {
    final picker = await device('3333'); // Juan Nieves, piqueador
    final count = serverState().users.length;
    picker.n.addUser();
    expect(picker.s.users.length, count + 1, reason: 'predicción local');
    await picker.settle();
    expect(picker.toasts.single, contains('permiso'));
    expect(serverState().users.length, count);
    expect(picker.s.users.length, count, reason: 'se deshace al recibir el rechazo');
  });

  test('devoluciones: la supervisora acepta desde su dispositivo; un piqueador no puede', () async {
    serverContainer.read(appProvider.notifier).importReturns('s0', [
      RmReturnLine(
        returnNumber: 'V78',
        returnType: 70,
        returnDate: DateTime(2026, 9, 10),
        lineId: 'V78-1',
        itemCode: 'MI-20565R15',
        description: 'Michelin',
        quantity: 2,
      ),
    ]);
    final id = serverState().returns.single.id;
    final picker = await device('3333', name: 'P');
    await until(() => picker.s.returns.isNotEmpty);
    expect(picker.n.discardReturn(id, 2, 'No llegó al almacén'), isNull, reason: 'predicción local');
    await picker.settle();
    expect(picker.toasts.single, contains('permiso'));
    expect(serverState().returns.single.isOpen, isTrue);

    final sup = await device('2222', name: 'S');
    expect(sup.n.acceptReturn(id, 2, DateTime(2026, 8, 1)), isNull);
    await sup.settle();
    expect(serverState().returns.single.receiptId, id);
    expect(serverState().receipts.firstWhere((r) => r.id == id).isReturn, isTrue);
    expect(serverState().returns.single.reviewedBy, 'M. Rivera');
  });

  test('cambio de PIN confirmado por el servidor (no repetido)', () async {
    final a = await device('3333');
    expect(await a.n.setPinAsync('u3', '1111'), contains('otro empleado'));
    expect(await a.n.setPinAsync('u3', '7777'), isNull);
    expect(serverState().users.firstWhere((u) => u.id == 'u3').checkPin('7777'), isTrue);
    expect(await a.n.setPinAsync('u1', '8888'), contains('permiso'), reason: 'un piqueador no cambia el PIN de otro');
  });

  test('al reconectar retoma la sesión y no aplica dos veces lo pendiente', () async {
    final a = await device('1111');
    final count = serverState().users.length;
    // Se corta la conexión justo después de mandar la acción.
    a.n.addUser();
    await until(() => serverState().users.length == count + 1);
    await server.dropConnectionsForTest();
    await until(() => a.link.online && a.n.pendingCount == 0, timeout: const Duration(seconds: 8));
    expect(serverState().users.length, count + 1);
    expect(a.s.currentUser?.name, 'Carlos Omar', reason: 'sin volver a pedir el PIN');
    expect(a.s.users.length, count + 1);
  });

  test('una acción repetida con el mismo ID se aplica una sola vez', () async {
    final a = await device('1111');
    final count = serverState().receipts.length;
    final msg = {'t': 'cmd', 'id': 'dup-1', 'name': 'simulateReceipt', 'args': <String, dynamic>{}, 'base': 1 << 30};
    a.link.send(msg);
    a.link.send(msg);
    await until(() => serverState().receipts.length == count + 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(serverState().receipts.length, count + 1);
  });

  test('cerrar sesión libera el dispositivo y el servidor lo registra', () async {
    final a = await device('1111');
    a.n.logout();
    expect(a.s.currentUserId, isNull);
    await until(() => server.sessionCount == 0);
    expect(await a.n.loginAsync('2222'), isNull);
    expect(a.s.currentUser?.name, 'María Rivera');
  });
}
