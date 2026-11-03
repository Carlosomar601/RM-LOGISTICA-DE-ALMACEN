import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rm_core/config/app_config.dart';
import 'package:rm_core/data/data_store.dart';
import 'package:rm_core/selftest.dart';
import 'package:rm_core/state/app_state.dart';
import 'package:rm_core/sync/dispatch_ledger.dart';
import 'package:rm_core/util/clock.dart';

const _installed = AppConfig(apiUrl: 'http://srv:8180', source: 'config.json');

void main() {
  late Directory tmp;
  late File dataFile;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('piqueo_data');
    dataFile = File('${tmp.path}${Platform.pathSeparator}data.json');
  });
  tearDown(() {
    demoMode = true;
    tmp.deleteSync(recursive: true);
  });

  ProviderContainer open({AppConfig config = AppConfig.empty, bool files = true}) {
    final c = ProviderContainer(overrides: [
      appConfigProvider.overrideWithValue(config),
      if (files) sharedDirProvider.overrideWithValue(tmp),
      if (files) dataLoadProvider.overrideWithValue(DataStore.load(dataFile)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  String canonical(AppState s) => jsonEncode(s.toDataJson());

  test('ida y vuelta de todo el estado, con un piqueo en curso y los contadores', () {
    final c = open(files: false);
    final n = c.read(appProvider.notifier)..login('1111');
    n.suggestSingle('p1', 40, 'OV-1');
    n.binTransfer(productId: 'p1', srcRowId: c.read(appProvider).centralFifoRowsOf('p1').first.id, destBin: 'C-01-01', qty: 2);
    final s = c.read(appProvider);
    final again = AppState.fromDataJson(jsonDecode(jsonEncode(s.toDataJson())) as Map);
    expect(canonical(again), canonical(s));
    expect(again.pickSessions[singleSessionKey('u1')]?.steps, isNotEmpty);
    expect(again.tbSeq, s.tbSeq);
    expect(again.history.first.type, 'transfer-bin');
    // Los usuarios no van en data.json.
    expect(s.toDataJson().containsKey('users'), isFalse);
  });

  test('sin data.json: PC instalado → almacén vacío; desarrollo → demostración', () {
    final inst = open(config: _installed).read(appProvider);
    expect(inst.products, isEmpty);
    expect(inst.inventory, isEmpty);
    expect(inst.orders, isEmpty);
    expect(inst.stores.map((s) => s.name), ['Almacén Central']);
    expect(inst.centralStore.apiUrl, 'http://srv:8180');
    expect(inst.bins.map((b) => b.code), containsAll(['RECIBO', 'AL-RX']));
    expect(inst.centralBinCodes, ['RECIBO']);

    final dev = open().read(appProvider);
    expect(dev.products.length, 10);
  });

  test('guardado: flush escribe data.json y al reabrir vuelve igual', () {
    final c = open(config: _installed);
    final n = c.read(appProvider.notifier)..login('1111');
    expect(n.updateSettings(companyName: 'Centeno Tire PR'), isNull);
    expect(dataFile.existsSync(), isFalse, reason: 'se guarda con espera (agrupa cambios)');
    n.flush();
    expect(dataFile.existsSync(), isTrue);
    final before = canonical(c.read(appProvider));

    final c2 = open(config: _installed);
    expect(canonical(c2.read(appProvider)), before);
    expect(c2.read(appProvider).settings.companyName, 'Centeno Tire PR');
  });

  test('guardado automático unos segundos después del último cambio', () async {
    final c = open(config: _installed);
    c.read(appProvider.notifier).updateSettings(warehouseName: 'Almacén Norte');
    await Future<void>.delayed(AppNotifier.saveDelay + const Duration(milliseconds: 300));
    expect(jsonDecode(dataFile.readAsStringSync())['settings']['warehouseName'], 'Almacén Norte');
  });

  test('data.json dañado: no se sobrescribe, se avisa, y «Empezar vacío» lo aparta', () {
    dataFile.writeAsStringSync('{"version":1, "products": [ roto');
    final c = open(config: _installed);
    final n = c.read(appProvider.notifier)..login('1111');
    expect(c.read(appProvider).dataStoreError, contains('No se pudo leer'));
    n.updateSettings(companyName: 'X');
    n.flush();
    expect(dataFile.readAsStringSync(), startsWith('{"version":1, "products": [ roto'));

    n.startFresh();
    expect(c.read(appProvider).dataStoreError, isNull);
    expect(c.read(appProvider).currentUser?.name, 'Carlos Omar', reason: 'la sesión sigue');
    expect(tmp.listSync().map((f) => f.uri.pathSegments.last), contains(matches(r'^data\.danado-\d{8}-\d{6}\.json$')));
    expect(jsonDecode(dataFile.readAsStringSync())['version'], kDataVersion);
  });

  test('JSON válido pero con campos que faltan = dañado (nunca datos a medias)', () {
    dataFile.writeAsStringSync(jsonEncode({'version': 1, 'products': []}));
    final s = open(config: _installed).read(appProvider);
    expect(s.dataStoreError, isNotNull);
    expect(s.products, isEmpty);
  });

  test('dirección API de config.json: se aplica si cambió; si no, manda la editada en la app', () {
    final c = open(config: _installed);
    final n = c.read(appProvider.notifier);
    final central = c.read(appProvider).centralStore;
    n.updateStore(central.id, apiUrl: 'http://editada:8180');
    n.flush();
    expect(open(config: _installed).read(appProvider).centralStore.apiUrl, 'http://editada:8180');
    const otro = AppConfig(apiUrl: 'http://nuevo:8180', source: 'config.json');
    expect(open(config: otro).read(appProvider).centralStore.apiUrl, 'http://nuevo:8180');
  });

  test('fecha real en un PC instalado: los movimientos llevan la hora actual', () {
    demoMode = false;
    final c = open(config: _installed, files: false);
    final n = c.read(appProvider.notifier)..login('1111');
    final before = DateTime.now().subtract(const Duration(seconds: 1));
    n.updateSettings(companyName: 'Y');
    expect(kToday.isAfter(before), isTrue);
    expect(ageDays(DateTime.now()), 0);
  });

  test('libro de despachos: pasa de %APPDATA% a la carpeta compartida una sola vez', () {
    final old = Directory('${tmp.path}${Platform.pathSeparator}appdata')..createSync();
    File('${old.path}${Platform.pathSeparator}ledger.json').writeAsStringSync('{"s1|O|9":{"created":"2026-10-01T00:00:00.000","appId":"ORD-9","picked":{},"invoices":[]}}');
    final shared = Directory('${tmp.path}${Platform.pathSeparator}shared');
    final f = DispatchLedger.sharedFile(shared, old)!;
    expect(f.existsSync(), isTrue);
    expect(DispatchLedger.load(f, now: DateTime(2026, 10, 13)).order('s1', '9')?.appId, 'ORD-9');
    f.writeAsStringSync('{}');
    DispatchLedger.sharedFile(shared, old);
    expect(f.readAsStringSync(), '{}', reason: 'no vuelve a copiar encima');
  });

  test('autodiagnóstico: data.json ausente, válido o dañado nunca hace fallar', () {
    expect(checkData(dataFile).ok, isTrue);
    final c = open(files: false);
    DataStore.write(dataFile, c.read(appProvider).toDataJson());
    expect(checkData(dataFile).detail, contains('10 producto(s)'));
    dataFile.writeAsStringSync('nope');
    final bad = checkData(dataFile);
    expect((bad.ok, bad.detail.contains('aviso')), (true, true));
  });
}
