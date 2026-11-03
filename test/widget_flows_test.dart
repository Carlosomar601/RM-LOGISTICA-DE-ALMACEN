import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piqueo_fifo_centeno/main.dart';
import 'package:piqueo_fifo_centeno/shell/sidebar.dart';
import 'package:piqueo_fifo_centeno/state/app_state.dart';

late ProviderContainer container;

Future<void> pumpApp(WidgetTester t, {Size size = const Size(1440, 1000)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(appProvider.notifier).login('1111'); // administrador demo
  await t.pumpWidget(UncontrolledProviderScope(container: container, child: const PiqueoApp()));
  await t.pumpAndSettle();
}

AppNotifier get n => container.read(appProvider.notifier);
AppState get s => container.read(appProvider);

Future<void> go(WidgetTester t, AppView v) async {
  n.navigate(v);
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
  for (final size in const [Size(360, 800), Size(768, 1024), Size(1440, 1000)]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('pantallas sin overflow a ${size.width.toInt()}px (${mode.name})', (t) async {
        await pumpApp(t, size: size);
        container.read(themeModeProvider.notifier).state = mode;
        await t.pumpAndSettle();
        for (final v in AppView.values) {
          await go(t, v);
          expect(t.takeException(), isNull, reason: 'error en ${v.name}');
        }
        // Estados expandidos / con sesiones activas.
        n.calcOrderRoute('OV-10501');
        n.suggestSingle('p1', 40, 'OV-10482');
        await go(t, AppView.orders);
        await tapText(t, 'OV-10501 — AutoExpress Caguas');
        expect(t.takeException(), isNull);
        await go(t, AppView.picking);
        expect(t.takeException(), isNull);
        await go(t, AppView.receiving);
        await tapText(t, 'Ubicar');
        expect(t.takeException(), isNull);
        await go(t, AppView.users);
        await tapText(t, 'Juan Nieves');
        expect(t.takeException(), isNull);
        for (final tab in ['Tiendas', 'Canastas', 'Roles', 'Parámetros', 'Respaldos']) {
          await tapText(t, tab);
          expect(t.takeException(), isNull, reason: 'tab $tab');
        }
        await tapText(t, 'Tiendas');
        await tapText(t, 'Sucursal Bayamón');
        expect(t.takeException(), isNull);
        await go(t, AppView.dashboard);
        await tapText(t, 'MI-20565R15');
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('OV-10501: ruta FIFO, faltante, sugerencia y confirmación parcial', (t) async {
    await pumpApp(t, size: const Size(1440, 1400));
    await go(t, AppView.orders);
    await tapText(t, 'OV-10501 — AutoExpress Caguas');
    await tapText(t, 'Calcular ruta de piqueo (todos los artículos)');
    expect(find.textContaining('2 canastas — ninguna sola cubría las 15'), findsOneWidget);
    expect(find.textContaining('2 canastas — ninguna sola cubría las 10'), findsOneWidget);
    expect(find.text('1 canasta'), findsOneWidget);

    final k6 = orderSessionKey('OV-10501', 'p6');
    final b2 = s.pickSessions[k6]!.steps[1];
    expect(b2.bin, 'B-01-02');
    n.stepMissingHere(k6, b2.id);
    await t.pumpAndSettle();
    expect(find.text('Sucursal Bayamón · SB-02 · 5 disponibles'), findsOneWidget);
    expect(find.text('Transferir 3 a Almacén Central'), findsOneWidget);

    await tapText(t, 'Transferir 3 a Almacén Central');
    expect(s.currentView, AppView.transfers);
    expect(find.text('Enviar transferencia'), findsOneWidget);
    expect(find.text('Sucursal Bayamón'), findsWidgets);

    // Volver, declarar faltante y confirmar todo.
    await go(t, AppView.orders);
    await tapText(t, 'OV-10501 — AutoExpress Caguas');
    for (final key in s.pickSessions.keys.toList()) {
      for (final st in s.pickSessions[key]!.steps.toList()) {
        n.stepPicked(key, st.id);
      }
    }
    await t.pumpAndSettle();
    await tapText(t, 'Marcar como no encontrado en almacén');
    await tapText(t, 'Confirmar piqueo de la orden');
    expect(find.text('Piqueo de orden OV-10501 confirmado (parcial — hay faltantes declarados)'), findsOneWidget);
    expect(s.orders.firstWhere((o) => o.id == 'OV-10501').status, 'parcial');
    final types = s.history.take(8).map((m) => m.type).toSet();
    expect(types.containsAll({'piqueo', 'discrepancia', 'no-encontrado'}), isTrue);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('Recibo: excede lo pendiente bloquea confirmar', (t) async {
    await pumpApp(t);
    await go(t, AppView.receiving);
    await tapText(t, 'Ubicar');
    await t.enterText(find.byType(TextField).first, '120');
    await t.pumpAndSettle();
    expect(find.text('Asignado 120 de 100 pendientes — excede lo pendiente'), findsOneWidget);
    final btn = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar ubicación'));
    expect(btn.onPressed, isNull);
    await t.enterText(find.byType(TextField).first, '100');
    await t.pumpAndSettle();
    await tapText(t, 'Confirmar ubicación');
    expect(s.pendingReceipts.any((r) => r.id == 'REC-3430'), isFalse);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('Piqueo FIFO por defecto: 3 canastas y confirmación', (t) async {
    await pumpApp(t, size: const Size(1440, 1400));
    await go(t, AppView.picking);
    await tapText(t, 'Sugerir ruta de piqueo');
    expect(find.text('3 por verificar'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tapText(t, '✔ Recogido');
    }
    expect(find.text('Todo verificado · 3 canastas'), findsOneWidget);
    await tapText(t, 'Confirmar piqueo');
    expect(s.inventory.firstWhere((r) => r.productId == 'p1' && r.bin == 'B-02-01').qty, 12);
    expect(s.inventory.where((r) => r.productId == 'p1' && r.bin.startsWith('A-01')), isEmpty);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('RBAC: ver como Juan Nieves', (t) async {
    await pumpApp(t);
    await go(t, AppView.users);
    await tapText(t, 'Ver como este usuario');
    expect(find.textContaining('Viendo el dashboard como Juan Nieves (Piqueador)'), findsOneWidget);
    await tapText(t, 'Historial');
    expect(find.text('🔒 Juan Nieves (Piqueador) no tiene acceso a esta sección.'), findsOneWidget);
    await tapText(t, 'Salir de la vista previa');
    expect(s.simulatedUserId, isNull);
    await t.pump(const Duration(seconds: 3));
  });
}
