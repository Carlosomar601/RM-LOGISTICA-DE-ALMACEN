// Prueba de extremo a extremo contra la API real de RM (solo lectura).
//
//   flutter test integration_test/rm_import_live_test.dart -d windows
//
// Variable opcional: --dart-define=RM_API=http://localhost:8180
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piqueo_fifo_centeno/main.dart';
import 'package:rm_core/state/app_state.dart';
import 'package:rm_core/sync/sync_service.dart';

const _api = String.fromEnvironment('RM_API', defaultValue: 'http://localhost:8180');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Administración → Tiendas → importar recibos → ubicar en canasta', (t) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(container: container, child: const PiqueoApp()));
    await t.pumpAndSettle();

    // Pantalla de PIN: entrar como el administrador de demostración (sin users.json en la prueba).
    expect(find.text('INGRESA TU PIN'), findsOneWidget);
    for (final d in '1111'.split('')) {
      await t.tap(find.text(d).last);
      await t.pump();
    }
    await t.pumpAndSettle();
    expect(container.read(appProvider).currentUser?.name, 'Carlos Omar');

    Future<void> tapVisible(Finder f) async {
      await t.ensureVisible(f.first);
      await t.pumpAndSettle();
      await t.tap(f.first);
      await t.pumpAndSettle();
    }

    // La API real es asíncrona: esperamos con tiempo límite en lugar de pumpAndSettle.
    Future<void> waitFor(Finder f, {int seconds = 30}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (DateTime.now().isBefore(end)) {
        await t.pump(const Duration(milliseconds: 200));
        if (f.evaluate().isNotEmpty) return;
      }
      fail('No apareció $f en $seconds s');
    }

    // 1) Administración → Tiendas → Almacén Central: dirección API + Probar conexión.
    await tapVisible(find.text('Administración'));
    await tapVisible(find.text('Tiendas'));
    await tapVisible(find.text('Almacén Central'));
    final urlField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'http://servidor:8180/cse.api.v1');
    await t.enterText(urlField, _api);
    await t.pumpAndSettle();
    await tapVisible(find.text('Probar conexión'));
    await waitFor(find.textContaining('Última prueba: Conexión OK'));
    expect(container.read(appProvider).centralStore.apiUrl, _api);

    // 2) Recibido sin ubicar → Importar desde RM (rango de un año).
    await tapVisible(find.text('Recibido sin ubicar'));
    await tapVisible(find.text('Importar desde RM'));
    final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await t.enterText(fields.at(0), '2025-10-13');
    await t.enterText(fields.at(1), '2026-10-13');
    await t.pumpAndSettle();
    await tapVisible(find.text('Buscar'));
    await waitFor(find.textContaining('línea(s) en'));
    final summary = find.textContaining('línea(s) en').evaluate().single.widget as Text;
    final fresh = int.parse(RegExp(r'(\d+) nueva\(s\)').firstMatch(summary.data!)!.group(1)!);
    expect(fresh, greaterThan(0));
    final total = fresh; // botón = líneas importables
    expect(find.text('Importar $total línea(s)'), findsOneWidget);

    // 3) Importar.
    final receiptsBefore = container.read(appProvider).receipts.length;
    await tapVisible(find.text('Importar $total línea(s)'));
    final s = container.read(appProvider);
    final imported = s.receipts.where((r) => r.id.startsWith('RM-')).toList();
    expect(imported, isNotEmpty);
    expect(s.receipts.length, greaterThan(receiptsBefore));
    expect(find.byType(AlertDialog), findsNothing);
    final importedUnits = imported.fold<int>(0, (a, r) => a + r.items.fold(0, (b, i) => b + i.qtyReceived));
    expect(importedUnits, greaterThan(0));

    // 4) Ubicar un recibo importado en una canasta, desde la interfaz.
    final target = imported.first;
    final targetItem = target.items.first;
    await tapVisible(find.textContaining('${target.id} — '));
    await tapVisible(find.text('Ubicar'));
    await tapVisible(find.text('Confirmar ubicación'));
    final after = container.read(appProvider);
    final rec = after.receipts.firstWhere((r) => r.id == target.id);
    expect(rec.items.first.pending, 0, reason: 'el artículo quedó ubicado');
    final row = after.inventory.firstWhere((r) => r.receipt == target.id && r.productId == targetItem.productId);
    expect(row.qty, targetItem.qtyReceived);
    expect(row.entryDate, target.date, reason: 'la fecha de entrada es la del recibo de RM');

    // 5) Reimportar: nada nuevo.
    await tapVisible(find.text('Importar desde RM'));
    final fields2 = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await t.enterText(fields2.at(0), '2025-10-13');
    await t.enterText(fields2.at(1), '2026-10-13');
    await t.pumpAndSettle();
    await tapVisible(find.text('Buscar'));
    await waitFor(find.textContaining('0 nueva(s)'));
    expect(find.text('Ya importada'), findsWidgets);

    // 6) Un rango de más de 366 días no llega a la API y se explica en pantalla.
    await t.enterText(fields2.at(0), '2024-01-01');
    await t.pumpAndSettle();
    await tapVisible(find.text('Buscar'));
    expect(find.textContaining('366'), findsOneWidget);
    await tapVisible(find.text('Cancelar'));

    // 7) Administración → Parámetros → Sincronizar ahora contra la API real.
    await tapVisible(find.text('Administración'));
    await tapVisible(find.text('Parámetros'));
    await tapVisible(find.text('Sincronizar ahora'));
    await waitFor(find.textContaining('Recibos: '), seconds: 60);
    final parts = container.read(syncProvider).parts;
    final receipts = parts.firstWhere((p) => p.label == 'Recibos');
    expect(receipts.ok, isTrue, reason: receipts.message);
    // Órdenes y facturas: funcionan si la API ya tiene los endpoints; si no, se informa sin error.
    for (final p in parts.where((p) => p.label != 'Recibos')) {
      expect(p.ok || p.notAvailable, isTrue, reason: '${p.label}: ${p.message}');
    }
    for (final p in parts) {
      // ignore: avoid_print
      print('SYNC ${p.label}: ok=${p.ok} notAvailable=${p.notAvailable} ${p.message}');
    }
  });
}
