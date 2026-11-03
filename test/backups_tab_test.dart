import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rm_core/backup/backup_service.dart';
import 'package:rm_core/backup/backup_settings.dart';
import 'package:rm_core/config/app_config.dart';
import 'package:piqueo_fifo_centeno/main.dart';
import 'package:piqueo_fifo_centeno/shell/sidebar.dart';
import 'package:rm_core/state/app_state.dart';
import 'package:rm_core/sync/sync_service.dart';

class _FakeTimer implements Timer {
  @override
  void cancel() {}
  @override
  bool get isActive => true;
  @override
  int get tick => 0;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('piqueo_bktab'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<ProviderContainer> pump(WidgetTester t,
      {double width = 1440, ThemeMode mode = ThemeMode.light, AppConfig config = AppConfig.empty}) async {
    t.view.physicalSize = Size(width, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = ProviderContainer(overrides: [
      appConfigProvider.overrideWithValue(config),
      clockProvider.overrideWithValue(() => DateTime(2026, 10, 13, 10)),
      tickerFactoryProvider.overrideWithValue((d, fn) => _FakeTimer()),
    ]);
    addTearDown(c.dispose);
    c.read(themeModeProvider.notifier).state = mode;
    // Sin carpeta compartida en pruebas: los respaldos van a una carpeta temporal elegida.
    c.read(backupProvider.notifier).update((s) => s.folder = tmp.path);
    c.read(appProvider.notifier).login('1111');
    await t.pumpWidget(UncontrolledProviderScope(container: c, child: const PiqueoApp()));
    await t.pumpAndSettle();
    return c;
  }

  Future<void> openTab(WidgetTester t, ProviderContainer c) async {
    c.read(appProvider.notifier).navigate(AppView.users);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Respaldos'));
    await t.pumpAndSettle();
    await t.tap(find.text('Respaldos'));
    await t.pumpAndSettle();
  }

  for (final width in [360.0, 1440.0]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('Respaldos sin overflow (${width.toInt()}px, ${mode.name})', (t) async {
        final c = await pump(t, width: width, mode: mode);
        await openTab(t, c);
        expect(find.textContaining(RegExp('programación de respaldos', caseSensitive: false)), findsOneWidget);
        expect(find.text('Todos los días a las 11:00 p. m.'), findsOneWidget);
        expect(find.textContaining('Próximo respaldo: martes 13 oct, 11:00 p. m.'), findsOneWidget);
        c.read(backupProvider.notifier).update((s) => s.frequency = BackupFrequency.twiceWeekly);
        await t.pumpAndSettle();
        expect(find.text('Dos días de la semana'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('días: semanal = 1, dos veces por semana = siempre 2', (t) async {
    final c = await pump(t);
    await openTab(t, c);
    final svc = c.read(backupProvider.notifier);
    svc.update((s) => s.frequency = BackupFrequency.twiceWeekly);
    await t.pumpAndSettle();
    expect(c.read(backupProvider).settings.activeWeekdays, [1, 4]);
    await t.tap(find.byKey(const ValueKey('backup-day-6')));
    await t.pumpAndSettle();
    expect(c.read(backupProvider).settings.activeWeekdays, [4, 6], reason: 'el sábado reemplaza al lunes');
    await t.tap(find.byKey(const ValueKey('backup-day-4')));
    await t.pumpAndSettle();
    expect(c.read(backupProvider).settings.activeWeekdays, [4, 6], reason: 'no se puede quedar con uno');
    expect(find.textContaining('Cada jueves y sábado'), findsOneWidget);

    svc.update((s) => s.frequency = BackupFrequency.weekly);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('backup-day-3')));
    await t.pumpAndSettle();
    expect(c.read(backupProvider).settings.activeWeekdays, [3]);
    expect(find.textContaining('Cada miércoles'), findsOneWidget);
  });

  testWidgets('Respaldar ahora crea el archivo; Restaurar pide el PIN y cierra la sesión', (t) async {
    final c = await pump(t);
    await openTab(t, c);
    await t.tap(find.text('Respaldar ahora'));
    await t.pumpAndSettle();
    final zips = tmp.listSync().whereType<File>().where((f) => f.path.endsWith('.zip')).toList();
    expect(zips, hasLength(1));
    expect(find.text('Restaurar'), findsOneWidget);

    c.read(appProvider.notifier).updateSettings(companyName: 'Después del respaldo');
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Restaurar'));
    await t.tap(find.text('Restaurar'));
    await t.pumpAndSettle();
    expect(find.text('Restaurar respaldo'), findsOneWidget);
    expect(find.textContaining('hecho por Carlos Omar'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('restore-pin')), '2222');
    await t.tap(find.widgetWithText(FilledButton, 'Restaurar'));
    await t.pumpAndSettle();
    expect(find.text('PIN incorrecto.'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('restore-pin')), '1111');
    await t.tap(find.widgetWithText(FilledButton, 'Restaurar'));
    await t.pumpAndSettle();

    expect(find.text('INGRESA TU PIN'), findsOneWidget);
    expect(find.textContaining('Respaldo restaurado'), findsOneWidget);
    expect(c.read(appProvider).settings.companyName, 'Centeno Tire');
    expect(tmp.listSync().where((f) => f.path.contains(kSafetySuffix)), hasLength(1));
  });

  testWidgets('almacén vacío (PC instalado, primer arranque): todas las pantallas abren', (t) async {
    final c = await pump(t, config: const AppConfig(apiUrl: 'http://srv:8180', source: 'config.json'));
    expect(c.read(appProvider).products, isEmpty);
    for (final v in AppView.values) {
      c.read(appProvider.notifier).navigate(v);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: 'pantalla ${v.name}');
    }
    c.read(appProvider.notifier).navigate(AppView.picking);
    await t.pumpAndSettle();
    expect(find.textContaining('Aún no hay productos'), findsOneWidget);
    expect(find.byType(Sidebar), findsOneWidget);
  });
}
