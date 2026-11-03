import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rm_core/api/rm_api.dart';
import 'package:rm_core/data/seed.dart';
import 'package:rm_core/models/app_user.dart';
import 'package:rm_core/state/app_state.dart';

import 'fake_rm_api.dart';

void main() {
  late ProviderContainer c;
  AppNotifier n() => c.read(appProvider.notifier);
  AppState s() => c.read(appProvider);

  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  test('seed: tiendas y canastas equivalentes a las constantes', () {
    expect(s().stores.map((x) => x.name), kStores);
    expect(s().centralBinCodes, kAllBins);
    expect(s().receiveBinOf('Sucursal Bayamón'), 'BA-RX');
    expect(s().receiveBinOf(kCentral), 'AL-RX');
  });

  test('tiendas: alta, validaciones y baja', () {
    final id = n().addStore();
    expect(s().stores.length, 5);
    expect(n().updateStore(id, code: 'SB'), contains('código'));
    expect(n().updateStore(id, name: 'Sucursal Bayamón'), contains('nombre'));
    expect(n().updateStore(id, name: 'Sucursal Caguas', apiUrl: 'ftp://x'), contains('http'));
    expect(n().updateStore(id, apiUrl: 'https://caguas.example.com/api'), isNull);
    expect(s().stores.last.name, 'Sucursal Caguas');
    expect(s().activeStores.any((x) => x.id == id), isTrue);
    n().updateStore(id, active: false);
    expect(s().activeStores.any((x) => x.id == id), isFalse);
    expect(n().deleteStore(id), isNull);
    expect(s().stores.length, 4);
  });

  test('tiendas: central protegida y tienda con historial no se renombra ni elimina', () {
    final central = s().centralStore;
    expect(n().updateStore(central.id, name: 'Otro'), isNotNull);
    expect(n().updateStore(central.id, active: false), isNotNull);
    expect(n().deleteStore(central.id), isNotNull);
    final bay = s().storeByName('Sucursal Bayamón')!;
    expect(n().storeHasHistory(bay.id), isTrue);
    expect(n().updateStore(bay.id, name: 'Otra'), isNotNull);
    expect(n().deleteStore(bay.id), isNotNull);
  });

  test('prueba de conexión usa el HealthCheck de la API', () async {
    c.dispose();
    c = ProviderContainer(overrides: [
      rmApiFactoryProvider.overrideWithValue((url) => FakeRmApi(health: url.contains('ok') ? null : 'caído')),
    ]);
    final id = n().addStore();
    expect(await n().testStoreConnection(id), contains('Sin dirección'));
    n().updateStore(id, apiUrl: 'http://x.example.com');
    expect(await n().testStoreConnection(id), 'caído');
    n().updateStore(id, apiUrl: 'http://ok.example.com');
    expect(await n().testStoreConnection(id), contains('Conexión OK'));
    expect(s().stores.firstWhere((x) => x.id == id).lastCheck, contains('Conexión OK'));
  });

  test('canastas: alta, duplicado, inventario y recepción', () {
    expect(n().addBin('s0', 'z-01-01', zone: 'Zona Z'), isNull);
    expect(s().centralBinCodes, contains('Z-01-01'));
    expect(n().addBin('s0', 'Z-01-01'), contains('ya existe'));
    expect(n().addBin('s0', ' '), isNotNull);
    final bin = s().bins.firstWhere((b) => b.code == 'A-01-01');
    expect(n().binHasStock(bin), isTrue);
    expect(n().updateBin(bin.id, active: false), contains('inventario'));
    expect(n().deleteBin(bin.id), contains('inventario'));
    final recibo = s().bins.firstWhere((b) => b.code == 'RECIBO');
    expect(n().deleteBin(recibo.id), isNotNull);
    final z = s().bins.firstWhere((b) => b.code == 'Z-01-01');
    n().updateBin(z.id, active: false);
    expect(s().centralBinCodes, isNot(contains('Z-01-01')));
    expect(n().deleteBin(z.id), isNull);
  });

  test('una canasta nueva se puede usar al ubicar un recibo', () {
    n().addBin('s0', 'Z-09-09');
    final rec = s().pendingReceipts.first;
    final item = rec.items.firstWhere((i) => i.pending > 0);
    final qty = item.pending;
    expect(n().allocateReceiptItem(rec.id, item.productId, [('Z-09-09', qty)]), isNull);
    expect(s().inventory.any((r) => r.bin == 'Z-09-09' && r.qty == qty), isTrue);
  });

  test('parámetros: umbrales cambian las alertas y se validan', () {
    final before = s().ageAlerts;
    expect(n().updateSettings(ageAlertDays: 500, staleDays: 600), isNull);
    expect(s().ageAlerts, lessThan(before));
    expect(s().staleRows, isEmpty);
    expect(n().updateSettings(ageAlertDays: 90, staleDays: 60), isNotNull);
    expect(n().updateSettings(ageAlertDays: 0), isNotNull);
    n().updateSettings(companyName: 'ACME', warehouseName: 'Bodega 1');
    expect(s().settings.companyName, 'ACME');
  });

  test('roles: editar el preset afecta a usuarios nuevos y se restablece', () {
    n().setRolePerm('Piqueador', Area.history, true);
    final id = n().addUser();
    expect(s().users.firstWhere((u) => u.id == id).can(Area.history), isTrue);
    n().resetRolePreset('Piqueador');
    expect(s().presetFor('Piqueador')[Area.history], isFalse);
    n().setRolePerm('Administrador', Area.users, false);
    expect(s().presetFor('Administrador')[Area.users], isTrue);
  });

  test('el único administrador activo no se puede borrar ni desactivar', () {
    expect(n().isLastAdmin('u1'), isTrue);
    n().deleteUser('u1');
    expect(s().users.any((u) => u.id == 'u1'), isTrue);
    n().updateUser('u1', active: false);
    expect(s().users.firstWhere((u) => u.id == 'u1').active, isTrue);
    n().setPerm('u1', Area.users, false);
    expect(s().users.firstWhere((u) => u.id == 'u1').can(Area.users), isTrue);
  });
}
