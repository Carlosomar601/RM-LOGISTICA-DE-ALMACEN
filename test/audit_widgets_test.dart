import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piqueo_fifo_centeno/main.dart';
import 'package:piqueo_fifo_centeno/shell/sidebar.dart';
import 'package:rm_core/state/app_state.dart';

late ProviderContainer container;
AppNotifier get n => container.read(appProvider.notifier);
AppState get s => container.read(appProvider);

Future<void> pumpApp(WidgetTester t, String pin, {Size size = const Size(1440, 1000)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  container = ProviderContainer();
  addTearDown(container.dispose);
  n.login(pin);
  await t.pumpWidget(UncontrolledProviderScope(container: container, child: const PiqueoApp()));
  await t.pumpAndSettle();
}

Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text);
  expect(f, findsWidgets, reason: 'no se encontró "$text"');
  await t.ensureVisible(f.first);
  await t.pumpAndSettle();
  await t.tap(f.first);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('conteo a ciegas: el auditor escanea y nunca ve lo esperado', (t) async {
    await pumpApp(t, '5555');
    final id = n.createAudit(bins: ['A-01-02']).id!; // sistema: p1 × 20
    n.navigate(AppView.audit);
    await t.pumpAndSettle();
    expect(find.text('Auditorías'), findsNothing, reason: 'el auditor solo ve Contar');

    await t.enterText(find.byKey(const Key('audit-bin-scan')), 'A-01-02');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(find.text('CONTANDO A-01-02'), findsOneWidget);
    expect(s.lockedBins, {'A-01-02'});

    for (var i = 0; i < 3; i++) {
      await t.enterText(find.byKey(const Key('audit-product-scan')), 'MI-20565R15');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
    }
    expect(s.audits.first.bins.single.counts['p1'], 3);
    expect(find.text('3'), findsWidgets);
    expect(find.text('20'), findsNothing, reason: 'la cantidad esperada no se muestra');
    expect(find.textContaining('Esperado'), findsNothing);

    await tapText(t, 'Terminar canasta');
    expect(find.text('RECONTEO DE A-01-02'), findsOneWidget);
    expect(find.text('20'), findsNothing);
    await t.enterText(find.byType(TextField).last, '18');
    await tapText(t, 'Guardar reconteo');
    expect(s.audits.firstWhere((a) => a.id == id).bins.single.recounts, {'p1': 18});
    expect(t.takeException(), isNull);
    await t.pump(const Duration(seconds: 3));
  });

  for (final size in const [Size(360, 800), Size(1440, 1000)]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('auditoría sin overflow a ${size.width.toInt()}px (${mode.name})', (t) async {
        await pumpApp(t, '2222', size: size); // supervisora
        container.read(themeModeProvider.notifier).state = mode;
        // Una auditoría con una canasta contada (faltante y no registrado), un pendiente y una cerrada.
        final id = n.createAudit(bins: ['A-01-02', 'A-01-03']).id!;
        n.startBinCount(id, 'A-01-02');
        n.addCount(id, 'A-01-02', 'MI-20565R15', 15);
        n.addCount(id, 'A-01-02', 'GY-19565R15', 2);
        n.finishBinCount(id, 'A-01-02');
        n.submitRecount(id, 'A-01-02', {}, skip: true);
        final id2 = n.createAudit(bins: ['B-02-01']).id!;
        n.startBinCount(id2, 'B-02-01');
        n.addCount(id2, 'B-02-01', 'MI-20565R15', 10);
        n.finishBinCount(id2, 'B-02-01');
        n.submitRecount(id2, 'B-02-01', {}, skip: true);
        n.setLineReason(id2, 'B-02-01', 'p1', 'Perdido');
        n.closeAudit(id2);
        n.navigate(AppView.audit);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'Auditorías');
        await tapText(t, 'Ver cerradas y canceladas (1)');
        expect(t.takeException(), isNull, reason: 'cerradas');
        await tapText(t, 'Contar');
        expect(t.takeException(), isNull, reason: 'Contar');
        await tapText(t, 'Pendientes');
        expect(find.text('PENDIENTES ABIERTOS'), findsWidgets);
        await tapText(t, 'Resueltos');
        expect(t.takeException(), isNull, reason: 'Pendientes');
        await tapText(t, 'Reporte');
        expect(t.takeException(), isNull, reason: 'Reporte');
        n.navigate(AppView.transfers);
        await t.pumpAndSettle();
        await tapText(t, 'Canasta completa');
        expect(t.takeException(), isNull, reason: 'Canasta completa');
        n.navigate(AppView.dashboard);
        await t.pumpAndSettle();
        expect(find.text('PENDIENTES (UNID.)'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pump(const Duration(seconds: 3));
      });
    }
  }
}
