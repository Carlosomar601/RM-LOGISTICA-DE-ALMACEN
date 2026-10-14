import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piqueo_fifo_centeno/api/rm_api.dart';
import 'package:piqueo_fifo_centeno/main.dart';
import 'package:piqueo_fifo_centeno/shell/sidebar.dart';
import 'package:piqueo_fifo_centeno/state/app_state.dart';

import 'fake_rm_api.dart';

void main() {
  for (final width in [360.0, 1440.0]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('sincronización y órdenes de RM sin overflow (${width.toInt()}px, ${mode.name})', (t) async {
        t.view.physicalSize = Size(width, 1200);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final api = FakeRmApi(
          lines: [line('1')],
          orders: [
            oline('7001', 'MI-20565R15', 4, customer: 'Ferretería con un nombre de cliente bastante largo, S.E.'),
            oline('7002', 'GY-19565R15', 3),
          ],
        );
        final c = ProviderContainer(overrides: [rmApiFactoryProvider.overrideWithValue((_) => api)]);
        addTearDown(c.dispose);
        c.read(themeModeProvider.notifier).state = mode;
        c.read(appProvider.notifier).login('1111'); // administrador demo
        await t.pumpWidget(UncontrolledProviderScope(container: c, child: const PiqueoApp()));
        await t.pumpAndSettle();
        final n = c.read(appProvider.notifier);
        n.updateStore('s0', apiUrl: 'http://srv:8180');

        // Administración → Parámetros → Sincronizar ahora.
        n.navigate(AppView.users);
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Parámetros'));
        await t.pumpAndSettle();
        await t.tap(find.text('Parámetros'));
        await t.pumpAndSettle();
        expect(find.textContaining(RegExp('sincronización con rm', caseSensitive: false)), findsOneWidget);
        await t.ensureVisible(find.text('Sincronizar ahora'));
        await t.tap(find.text('Sincronizar ahora'));
        await t.pumpAndSettle();
        expect(find.textContaining('Recibos: '), findsOneWidget);
        expect(find.textContaining('Órdenes · Almacén Central'), findsOneWidget);
        expect(t.takeException(), isNull);

        // Después RM factura la orden 7001 (con 2 unidades más) y hay una venta directa.
        api.invoices = [iline('F900', 'MI-20565R15', 6, order: '7001'), iline('F901', 'BS-22545R17', 1)];
        await t.tap(find.text('Sincronizar ahora'));
        await t.pumpAndSettle();
        n.navigate(AppView.orders);
        await t.pumpAndSettle();
        expect(find.textContaining('ORD-7001 — '), findsOneWidget);
        await t.ensureVisible(find.textContaining('ORD-7001 — '));
        await t.tap(find.textContaining('ORD-7001 — '));
        await t.pumpAndSettle();
        expect(find.textContaining('Facturada en RM · FAC F900'), findsOneWidget);
        expect(find.text('RM · Orden'), findsWidgets);
        await t.ensureVisible(find.textContaining('FAC-F900 — '));
        await t.tap(find.textContaining('FAC-F900 — '));
        await t.pumpAndSettle();
        expect(find.text('Adicional a ORD-7001'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pump(const Duration(seconds: 5)); // temporizador del toast
      });
    }
  }
}
