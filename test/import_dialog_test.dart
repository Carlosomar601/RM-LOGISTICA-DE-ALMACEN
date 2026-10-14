import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piqueo_fifo_centeno/api/rm_api.dart';
import 'package:piqueo_fifo_centeno/main.dart';
import 'package:piqueo_fifo_centeno/state/app_state.dart';

import 'fake_rm_api.dart';

void main() {
  for (final width in [360.0, 1440.0]) {
    testWidgets('importar recibos desde RM (${width.toInt()}px)', (t) async {
      t.view.physicalSize = Size(width, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final container = ProviderContainer(overrides: [
        rmApiFactoryProvider.overrideWithValue((_) => FakeRmApi(lines: [
              line('1', code: 'MI-20565R15', qty: 12),
              line('2', code: 'THH12N', desc: 'THHN #12 NEGRO', qty: 500, receipt: '5002', supplier: 'ALL TOOLS, INC.'),
              line('3', code: 'GRANEL-1', desc: 'Producto a granel', qty: 0.39, receipt: '5002', supplier: 'ALL TOOLS, INC.'),
            ])),
      ]);
      addTearDown(container.dispose);
      container.read(appProvider.notifier).login('1111'); // administrador demo
      await t.pumpWidget(UncontrolledProviderScope(container: container, child: const PiqueoApp()));
      await t.pumpAndSettle();

      final n = container.read(appProvider.notifier);
      n.navigate(AppView.receiving);
      await t.pumpAndSettle();

      // Sin dirección API configurada.
      await t.tap(find.text('Importar desde RM'));
      await t.pumpAndSettle();
      expect(find.textContaining('Ninguna tienda tiene dirección API'), findsOneWidget);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();

      n.updateStore('s0', apiUrl: 'http://srv:8180');
      await t.pumpAndSettle();
      await t.tap(find.text('Importar desde RM'));
      await t.pumpAndSettle();
      await t.tap(find.text('Buscar'));
      await t.pumpAndSettle();
      expect(find.textContaining('3 línea(s) en 2 recibo(s) · 2 nueva(s)'), findsOneWidget);
      expect(find.textContaining('Se omitirá: cantidad 0.39'), findsOneWidget);
      expect(t.takeException(), isNull);

      await t.tap(find.text('Importar 2 línea(s)'));
      await t.pumpAndSettle();
      final s = container.read(appProvider);
      expect(s.receipts.map((r) => r.id), containsAll(['RM-5001', 'RM-5002']));
      expect(find.text('RM-5002 — ALL TOOLS, INC.'), findsOneWidget);
      expect(t.takeException(), isNull);

      // Segunda importación: todo figura como ya importado.
      await t.tap(find.text('Importar desde RM'));
      await t.pumpAndSettle();
      await t.tap(find.text('Buscar'));
      await t.pumpAndSettle();
      expect(find.textContaining('0 nueva(s)'), findsOneWidget);
      expect(find.text('Ya importada'), findsNWidgets(2));
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 5)); // deja vencer el temporizador del toast
    });
  }
}
