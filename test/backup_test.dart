import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rm_core/auth/audit_log.dart';
import 'package:rm_core/backup/backup_service.dart';
import 'package:rm_core/backup/backup_settings.dart';
import 'package:rm_core/config/app_config.dart';
import 'package:rm_core/data/data_store.dart';
import 'package:rm_core/state/app_state.dart';

void main() {
  group('programación', () {
    // Martes 13 oct 2026, 10:00.
    final tue = DateTime(2026, 10, 13, 10);

    test('todos los días a las 23:00', () {
      final s = BackupSettings(frequency: BackupFrequency.daily, hour: 23);
      expect(s.lastScheduled(tue), DateTime(2026, 10, 12, 23));
      expect(s.nextScheduled(tue), DateTime(2026, 10, 13, 23));
      expect(s.lastScheduled(DateTime(2026, 10, 13, 23)), DateTime(2026, 10, 13, 23));
      expect(s.describe(), 'Todos los días a las 11:00 p. m.');
    });

    test('dos veces por semana (lunes y jueves) y una vez por semana (domingo)', () {
      final two = BackupSettings(frequency: BackupFrequency.twiceWeekly, hour: 6, weekdays: [4, 1]);
      expect(two.activeWeekdays, [1, 4]);
      expect(two.lastScheduled(tue), DateTime(2026, 10, 12, 6)); // lunes
      expect(two.nextScheduled(tue), DateTime(2026, 10, 15, 6)); // jueves
      expect(two.describe(), 'Cada lunes y jueves a las 6:00 a. m.');

      final one = BackupSettings(frequency: BackupFrequency.weekly, hour: 0, weekdays: [7]);
      expect(one.lastScheduled(tue), DateTime(2026, 10, 11)); // domingo
      expect(one.nextScheduled(tue), DateTime(2026, 10, 18));
      expect(one.describe(), 'Cada domingo a las 12:00 a. m.');
    });

    test('una vez al mes: cambio de mes y de año', () {
      final m = BackupSettings(frequency: BackupFrequency.monthly, dayOfMonth: 28, hour: 22);
      expect(m.lastScheduled(tue), DateTime(2026, 9, 28, 22));
      expect(m.nextScheduled(tue), DateTime(2026, 10, 28, 22));
      final jan = DateTime(2027, 1, 5);
      expect(BackupSettings(frequency: BackupFrequency.monthly, dayOfMonth: 15).lastScheduled(jan),
          DateTime(2026, 12, 15, 23));
      expect(m.describe(), 'El día 28 de cada mes a las 10:00 p. m.');
    });

    test('toca respaldar: al ponerse al día tras días cerrada, y no dos veces por el mismo turno', () {
      final s = BackupSettings(frequency: BackupFrequency.daily, hour: 23);
      expect(s.isDue(tue), isTrue, reason: 'nunca se ha respaldado');
      s.lastBackup = DateTime(2026, 10, 9, 23); // la app estuvo cerrada desde el viernes
      expect(s.isDue(tue), isTrue);
      s.lastBackup = DateTime(2026, 10, 12, 23, 1);
      expect(s.isDue(tue), isFalse);
      expect(s.isDue(DateTime(2026, 10, 13, 23)), isTrue);
    });

    test('tras un fallo se reintenta cada 30 minutos; solo manual nunca toca', () {
      final s = BackupSettings(frequency: BackupFrequency.daily, hour: 9)
        ..lastError = 'carpeta no disponible'
        ..lastAttempt = tue.subtract(const Duration(minutes: 10));
      expect(s.isDue(tue), isFalse);
      s.lastAttempt = tue.subtract(const Duration(minutes: 31));
      expect(s.isDue(tue), isTrue);
      expect(BackupSettings(frequency: BackupFrequency.manual).isDue(tue), isFalse);
      expect(BackupSettings(frequency: BackupFrequency.manual).nextScheduled(tue), isNull);
    });

    test('backup.json: ida y vuelta, valores fuera de rango se corrigen', () {
      final s = BackupSettings(frequency: BackupFrequency.weekly, hour: 7, minute: 30, weekdays: [5], keep: 12)
        ..lastBackup = DateTime(2026, 10, 1, 7, 30);
      final again = BackupSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map);
      expect(jsonEncode(again.toJson()), jsonEncode(s.toJson()));
      final bad = BackupSettings.fromJson({'frequency': 'x', 'hour': 99, 'dayOfMonth': 31, 'keep': 0});
      expect((bad.frequency, bad.hour, bad.dayOfMonth, bad.keep), (BackupFrequency.daily, 23, 28, 1));
    });
  });

  group('respaldar y restaurar', () {
    late Directory tmp;
    late Directory folder;
    late ProviderContainer c;
    late DateTime now;
    late File auditFile;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('piqueo_bk');
      folder = Directory('${tmp.path}${Platform.pathSeparator}backups');
      auditFile = File('${tmp.path}${Platform.pathSeparator}audit.log');
      now = DateTime(2026, 10, 13, 23, 5);
      c = ProviderContainer(overrides: [
        appConfigProvider.overrideWithValue(const AppConfig(apiUrl: 'http://srv:8180')),
        sharedDirProvider.overrideWithValue(tmp),
        clockProvider.overrideWithValue(() => now),
        auditProvider.overrideWithValue(AuditLog(file: auditFile)),
      ]);
      c.read(appProvider.notifier).login('1111');
    });
    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    BackupService svc() => c.read(backupProvider.notifier);
    AppNotifier n() => c.read(appProvider.notifier);
    AppState s() => c.read(appProvider);

    Archive unzip(File f) => ZipDecoder().decodeBytes(f.readAsBytesSync());

    test('el respaldo es un zip con datos, usuarios (sin PIN en claro), auditoría y manifiesto', () async {
      final r = await svc().backupNow();
      expect(r.ok, isTrue, reason: r.error);
      expect(r.file!.path, startsWith(folder.path), reason: 'carpeta predeterminada …\\backups');
      expect(r.file!.uri.pathSegments.last, 'RMLogistics-respaldo-2026-10-13_2305.zip');
      final zip = unzip(r.file!);
      expect(zip.files.map((f) => f.name), containsAll(['manifest.json', 'data.json', 'users.json', 'audit.log']));
      final users = utf8.decode(zip.findFile('users.json')!.content);
      expect(users, contains('pinHash'));
      expect(users, isNot(contains('"1111"')));
      final manifest = jsonDecode(utf8.decode(zip.findFile('manifest.json')!.content));
      expect(manifest['createdBy'], 'Carlos Omar');
      expect(manifest['counts']['productos'], 10);
      expect(c.read(backupProvider).settings.lastBackup, now);
      expect(auditFile.readAsStringSync(), contains('respaldo RMLogistics-respaldo-2026-10-13_2305.zip'));
      expect(File('${tmp.path}${Platform.pathSeparator}data.json').existsSync(), isTrue,
          reason: 'antes de respaldar se guarda lo pendiente');
    });

    test('conservar los últimos N: borra solo los más viejos con nuestro nombre', () async {
      svc().update((x) => x.keep = 3);
      folder.createSync(recursive: true);
      final other = File('${folder.path}${Platform.pathSeparator}otro.zip')..writeAsStringSync('no tocar');
      for (var i = 0; i < 5; i++) {
        now = DateTime(2026, 10, 10 + i, 23);
        expect((await svc().backupNow()).ok, isTrue);
      }
      final names = svc().list().map((b) => b.name).toList();
      expect(names, [
        'RMLogistics-respaldo-2026-10-14_2300.zip',
        'RMLogistics-respaldo-2026-10-13_2300.zip',
        'RMLogistics-respaldo-2026-10-12_2300.zip',
      ]);
      expect(other.existsSync(), isTrue);
    });

    test('dos respaldos en el mismo minuto no se pisan', () async {
      final a = await svc().backupNow();
      final b = await svc().backupNow();
      expect(a.file!.path, isNot(b.file!.path));
      expect(b.file!.uri.pathSegments.last, 'RMLogistics-respaldo-2026-10-13_2305-2.zip');
    });

    test('automático: al abrir (tick) si pasó la hora; luego no repite', () async {
      svc().update((x) => x
        ..frequency = BackupFrequency.daily
        ..hour = 23
        ..minute = 0);
      await svc().tick();
      expect(svc().list(), hasLength(1));
      now = now.add(const Duration(minutes: 30));
      await svc().tick();
      expect(svc().list(), hasLength(1));
      now = DateTime(2026, 10, 14, 23, 0, 30);
      await svc().tick();
      expect(svc().list(), hasLength(2));
    });

    test('carpeta inaccesible: falla, lo anota y reintenta en 30 min', () async {
      final blocker = File('${tmp.path}${Platform.pathSeparator}soy-un-archivo')..writeAsStringSync('x');
      svc().update((x) => x
        ..folder = '${blocker.path}${Platform.pathSeparator}sub'
        ..frequency = BackupFrequency.daily);
      final r = await svc().backupNow(auto: true);
      expect(r.ok, isFalse);
      final st = c.read(backupProvider).settings;
      expect(st.lastError, isNotNull);
      expect(st.lastBackup, isNull);
      expect(svc().isDue(now.add(const Duration(minutes: 5))), isFalse);
      expect(svc().isDue(now.add(const Duration(minutes: 31))), isTrue);
      expect(svc().testFolder(st.folder), isNotNull);
      expect(svc().testFolder(folder.path), isNull);
    });

    test('restaurar: vuelve al estado del respaldo, cierra la sesión y guarda uno de seguridad', () async {
      final bk = (await svc().backupNow()).file!;
      final unitsBefore = s().totalUnits;
      final ordersBefore = s().orders.length;
      // Cambios después del respaldo.
      n().updateSettings(companyName: 'Cambiada');
      final row = s().centralFifoRowsOf('p1').first;
      n().binTransfer(productId: 'p1', srcRowId: row.id, destBin: 'C-01-01', qty: 1);
      n().setPin('u3', '7777');
      final historyAfter = s().history.length;
      now = now.add(const Duration(minutes: 10));

      final err = await svc().restore(bk);
      expect(err, isNull);
      expect(s().settings.companyName, 'Centeno Tire');
      expect(s().history.length, historyAfter - 1);
      expect(s().totalUnits, unitsBefore);
      expect(s().orders.length, ordersBefore);
      expect(s().currentUser, isNull, reason: 'la sesión se cierra');
      expect(s().logoutReason, contains('Respaldo restaurado'));
      expect(n().login('7777'), isNotNull, reason: 'los PIN vuelven a los del respaldo');
      expect(n().login('1111'), isNull);
      expect(s().centralStore.apiUrl, 'http://srv:8180', reason: 'la dirección API del PC no viaja');
      expect(svc().list().where((b) => b.isSafety), hasLength(1));
      expect(auditFile.readAsStringSync(), contains('respaldo restaurado'));
      // data.json quedó con lo restaurado.
      final saved = jsonDecode(File('${tmp.path}${Platform.pathSeparator}data.json').readAsStringSync());
      expect(saved['settings']['companyName'], 'Centeno Tire');
    });

    test('un archivo dañado o sin administrador con PIN no se restaura y no toca nada', () async {
      folder.createSync(recursive: true);
      final junk = File('${folder.path}${Platform.pathSeparator}RMLogistics-respaldo-2026-01-01_0000.zip')
        ..writeAsStringSync('no soy un zip');
      n().updateSettings(companyName: 'Actual');
      expect(await svc().restore(junk), startsWith('No se puede restaurar'));
      expect(s().settings.companyName, 'Actual');
      expect(s().currentUser, isNotNull);
      expect(svc().list().where((b) => b.isSafety), isEmpty, reason: 'ni siquiera hace el de seguridad');

      // Un respaldo cuyos usuarios no tienen ningún administrador con PIN dejaría a todos fuera.
      final archive = Archive();
      void add(String name, String text) {
        final b = utf8.encode(text);
        archive.addFile(ArchiveFile(name, b.length, b));
      }

      add('manifest.json', jsonEncode({'format': 1}));
      add('data.json', jsonEncode(s().toDataJson()));
      add('users.json', jsonEncode({'users': [{'id': 'u9', 'name': 'Sin PIN', 'role': 'Administrador', 'perms': ['users']}]}));
      final noAdmin = File('${folder.path}${Platform.pathSeparator}RMLogistics-respaldo-2026-01-02_0000.zip')
        ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
      expect(await svc().restore(noAdmin), contains('ningún administrador activo con PIN'));
    });

    test('con data.json dañado no respalda (no rota los respaldos buenos) pero sí restaura', () async {
      final good = (await svc().backupNow()).file!;
      c.dispose();
      File('${tmp.path}${Platform.pathSeparator}data.json').writeAsStringSync('dañado');
      c = ProviderContainer(overrides: [
        appConfigProvider.overrideWithValue(const AppConfig(apiUrl: 'http://srv:8180')),
        sharedDirProvider.overrideWithValue(tmp),
        dataLoadProvider.overrideWithValue(DataStore.load(File('${tmp.path}${Platform.pathSeparator}data.json'))),
        clockProvider.overrideWithValue(() => now),
      ]);
      n().login('1111');
      expect(s().dataStoreError, isNotNull);
      svc().update((x) => x.frequency = BackupFrequency.daily);
      expect(svc().isDue(now), isFalse);
      final r = await svc().backupNow();
      expect(r.error, contains('dañados'));
      expect(await svc().restore(good), isNull);
      expect(s().dataStoreError, isNull);
      expect(s().products.length, 10);
    });
  });
}
