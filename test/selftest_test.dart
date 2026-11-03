import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rm_core/api/rm_api.dart';
import 'package:rm_core/config/app_config.dart';
import 'package:rm_core/models/app_user.dart';
import 'package:rm_core/selftest.dart';
import 'package:rm_core/state/app_state.dart';

import 'fake_rm_api.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('piqueo_cfg'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('AppConfig.load', () {
    test('archivo inexistente → vacío', () {
      final c = AppConfig.load(File('${tmp.path}/no.json'));
      expect((c.apiUrl, c.source), ('', null));
    });

    test('JSON dañado → vacío', () {
      final f = File('${tmp.path}/config.json')..writeAsStringSync('{no es json');
      expect(AppConfig.load(f).source, isNull);
    });

    test('JSON válido', () {
      final f = File('${tmp.path}/config.json')..writeAsStringSync('{"apiUrl": " http://srv:8180 "}');
      final c = AppConfig.load(f);
      expect((c.apiUrl, c.source), ('http://srv:8180', f.path));
    });
  });

  test('la URL de la configuración se aplica al almacén central', () {
    final c = ProviderContainer(overrides: [
      appConfigProvider.overrideWithValue(const AppConfig(apiUrl: 'http://srv:8180', source: 'x')),
    ]);
    addTearDown(c.dispose);
    expect(c.read(appProvider).centralStore.apiUrl, 'http://srv:8180');
  });

  group('runSelfTest', () {
    const cfg = AppConfig(apiUrl: 'http://srv:8180', source: 'config.json');

    test('todo correcto → PASS', () async {
      final checks = await runSelfTest(cfg, apiFactory: (_) => FakeRmApi(lines: [line('1')]));
      expect(checks.map((c) => c.ok), [true, true, true, true, true]);
      expect(selfTestPassed(checks), isTrue);
    });

    test('API caída → FAIL con el motivo', () async {
      final checks = await runSelfTest(cfg, apiFactory: (_) => FakeRmApi(health: 'No se pudo conectar'));
      expect(selfTestPassed(checks), isFalse);
      expect(checks.last.toString(), contains('No se pudo conectar'));
    });

    test('error en RecReceiptsByDate → FAIL', () async {
      final checks = await runSelfTest(cfg, apiFactory: (_) => FakeRmApi(error: 'Invalid DateFrom'));
      expect(checks.map((c) => c.ok).take(3), [true, true, false]);
    });

    test('órdenes y facturas aún no disponibles → informa sin fallar', () async {
      final api = FakeRmApi(lines: [line('1')])
        ..ordersError = RmApiException('x', notAvailable: true)
        ..invoicesError = RmApiException('x', notAvailable: true);
      final checks = await runSelfTest(cfg, apiFactory: (_) => api);
      expect(selfTestPassed(checks), isTrue);
      expect(checks.where((c) => c.detail.contains('aún no disponible')).length, 2);
    });

    test('sin config o URL inválida → FAIL sin llamar a la API', () async {
      expect(selfTestPassed(await runSelfTest(AppConfig.empty)), isFalse);
      final bad = await runSelfTest(const AppConfig(apiUrl: 'srv', source: 'x'),
          apiFactory: (_) => throw StateError('no debe llamarse'));
      expect(bad.single.ok, isFalse);
    });

    test('usuarios: sin users.json o sin administrador con PIN → FAIL; con administrador → OK', () async {
      final f = File('${tmp.path}/users.json');
      final api = FakeRmApi(lines: [line('1')]);
      var checks = await runSelfTest(cfg, apiFactory: (_) => api, usersFile: f);
      expect((checks.first.ok, selfTestPassed(checks)), (false, false));

      f.writeAsStringSync('{"users":[{"id":"u1","name":"Ana","role":"Administrador","active":true,'
          '"perms":["users"]}]}');
      checks = await runSelfTest(cfg, apiFactory: (_) => api, usersFile: f);
      expect(checks.first.detail, contains('ningún administrador activo con PIN'));

      f.writeAsStringSync('{"users":[{"id":"u1","name":"Ana","role":"Administrador","active":true,'
          '"perms":["users"],"pinSalt":"ab","pinHash":"${hashPin('ab', '1234')}"}]}');
      checks = await runSelfTest(cfg, apiFactory: (_) => api, usersFile: f);
      expect(checks.first.ok, isTrue);
      expect(selfTestPassed(checks), isTrue);
    });

    test('runSelfTestAndLog escribe el log y devuelve 1 si falla', () async {
      final log = File('${tmp.path}/sub/selftest.log');
      expect(await runSelfTestAndLog(AppConfig.empty, log: log), 1);
      final text = log.readAsStringSync();
      expect(text, contains('RESULT: FAIL'));
      expect(text, contains('FAIL Configuracion: no se encontro config.json'));
      expect(text.runes.every((r) => r < 128), isTrue, reason: 'el log debe ser ASCII para Inno Setup');
    });
  });
}
