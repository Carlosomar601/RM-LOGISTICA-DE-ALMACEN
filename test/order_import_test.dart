import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piqueo_fifo_centeno/models/order.dart';
import 'package:piqueo_fifo_centeno/state/app_state.dart';
import 'package:piqueo_fifo_centeno/sync/dispatch_ledger.dart';

import 'fake_rm_api.dart';

// MI-20565R15 (p1, 52 en central) y GY-19565R15 (p2) existen en la semilla con inventario.
const p1 = 'MI-20565R15';
const p2 = 'GY-19565R15';

void main() {
  late Directory tmp;
  late File ledgerFile;
  late ProviderContainer c;
  AppState s() => c.read(appProvider);
  AppNotifier n() => c.read(appProvider.notifier);

  /// Simula abrir la app: estado nuevo, libro de despachos leído del disco.
  void boot() {
    c = ProviderContainer(overrides: [
      ledgerProvider.overrideWithValue(DispatchLedger.load(ledgerFile)),
      clockProvider.overrideWithValue(() => DateTime(2026, 10, 13, 16)),
    ]);
  }

  /// Piquea completa una orden por la interfaz de estado (ruta FIFO → todo piqueado → confirmar).
  void pickAll(String orderId) {
    n().calcOrderRoute(orderId);
    for (final key in s().pickSessions.keys.where((k) => k.startsWith(orderId)).toList()) {
      for (final st in s().pickSessions[key]!.steps) {
        n().stepPicked(key, st.id);
      }
    }
    expect(n().confirmOrder(orderId), isFalse, reason: 'piqueo completo');
  }

  Order ord(String id) => s().orders.firstWhere((o) => o.id == id);
  bool has(String id) => s().orders.any((o) => o.id == id);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('piqueo_ledger');
    ledgerFile = File('${tmp.path}/ledger.json');
    boot();
  });
  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  group('órdenes abiertas (foto)', () {
    test('crea ORD-n con lo pendiente y omite servicios y combustible', () {
      final r = n().importOpenOrders('s0', [
        oline('7001', p1, 4),
        oline('7001', p2, 2),
        oline('7001', 'SERV-1', 1, service: true),
        oline('7001', 'Gasolina', 20, fuel: true),
      ]);
      expect((r.created, r.skipped), (1, 2));
      final o = ord('ORD-7001');
      expect(o.source, OrderSource.rmOrder);
      expect(o.items.map((i) => i.qty), [4, 2]);
      expect(o.store, 'Almacén Central');
    });

    test('sin tocar se actualiza; tocada se marca; desaparecida se quita o se marca', () {
      n().importOpenOrders('s0', [oline('7001', p1, 4), oline('7002', p2, 3)]);
      n().calcOrderRoute('ORD-7002'); // 7002 queda "tocada" (ruta en curso)

      final r = n().importOpenOrders('s0', [oline('7001', p1, 6), oline('7002', p2, 1)]);
      expect((r.updated, r.flagged), (1, 1));
      expect(ord('ORD-7001').items.single.qty, 6);
      expect(ord('ORD-7001').syncNote, isNull);
      expect(ord('ORD-7002').items.single.qty, 3, reason: 'no se cambia una orden en piqueo');
      expect(ord('ORD-7002').syncNote, contains('Cambió en RM'));

      final gone = n().importOpenOrders('s0', []);
      expect((gone.removed, gone.flagged), (1, 1));
      expect(has('ORD-7001'), isFalse);
      expect(ord('ORD-7002').syncNote, contains('Cerrada en RM'));
    });

    test('repetir la misma foto no cambia nada', () {
      n().importOpenOrders('s0', [oline('7001', p1, 4)]);
      final r = n().importOpenOrders('s0', [oline('7001', p1, 4)]);
      expect((r.created, r.updated, r.flagged), (0, 0, 0));
      expect(s().orders.where((o) => o.id == 'ORD-7001').length, 1);
    });
  });

  group('orden → factura: nunca se despacha dos veces', () {
    test('orden piqueada y luego facturada: no entra FAC y la orden queda "Facturada en RM"', () {
      n().importOpenOrders('s0', [oline('7001', p1, 4)]);
      pickAll('ORD-7001');

      final r = n().importInvoices('s0', [iline('F900', p1, 4, order: '7001')]);
      expect((r.created, r.linked), (0, 1));
      expect(has('FAC-F900'), isFalse);
      expect(ord('ORD-7001').syncNote, contains('Facturada en RM · FAC F900'));

      // Después la orden sale de la foto de RM: se marca facturada, no "cerrada".
      final o = n().importOpenOrders('s0', []);
      expect(o.invoiced, 0, reason: 'ya está completada');
      expect(ord('ORD-7001').status, 'completada');
    });

    test('orden importada sin piquear y facturada: tampoco entra FAC; se piquea la orden', () {
      n().importOpenOrders('s0', [oline('7001', p1, 4)]);
      final r = n().importInvoices('s0', [iline('F900', p1, 4, order: '7001')]);
      expect((r.created, r.linked), (0, 1));
      expect(has('FAC-F900'), isFalse);

      final o = n().importOpenOrders('s0', []); // la orden salió de RM al facturarse
      expect(o.invoiced, 1);
      expect(has('ORD-7001'), isTrue, reason: 'sigue para piquear');
      expect(ord('ORD-7001').syncNote, contains('Facturada en RM'));
    });

    test('factura con más cantidad que la orden: solo entra la diferencia', () {
      n().importOpenOrders('s0', [oline('7001', p1, 4)]);
      pickAll('ORD-7001');
      final r = n().importInvoices('s0', [iline('F900', p1, 6, order: '7001'), iline('F900', p2, 2, order: '7001')]);
      expect(r.created, 1);
      final fac = ord('FAC-F900');
      expect(fac.syncNote, 'Adicional a ORD-7001');
      expect({for (final i in fac.items) s().product(i.productId).code: i.qty}, {p1: 2, p2: 2});
    });

    test('factura que llega antes que su orden: la orden entra marcada "Revisar antes de piquear"', () {
      expect(n().importInvoices('s0', [iline('F900', p1, 4, order: '7001')]).created, 1);
      n().importOpenOrders('s0', [oline('7001', p1, 4)]);
      expect(ord('ORD-7001').syncNote, contains('Revisar antes de piquear: la factura FAC-F900'));
    });

    test('venta directa (sin orden) entra normal; la misma factura no entra dos veces', () {
      expect(n().importInvoices('s0', [iline('F901', p1, 3)]).created, 1);
      final again = n().importInvoices('s0', [iline('F901', p1, 3)]);
      expect((again.created, again.duplicates), (0, 1));
      expect(s().orders.where((o) => o.id == 'FAC-F901').length, 1);
    });

    test('ventas en caja (10/11/12/19) no se despachan; 50 y 61 sí', () {
      final r = n().importInvoices('s0', [
        iline('C1', p1, 1, transaction: 10),
        iline('C2', p1, 1, transaction: 19),
        iline('C3', p1, 1, transaction: 61),
        iline('C4', p1, 1, transaction: 50),
      ]);
      expect((r.created, r.registerSales), (2, 2));
      expect(r.summary, contains('2 venta(s) en caja (no se despachan)'));
      expect(has('FAC-C3') && has('FAC-C4'), isTrue);
      // Lista configurable: sin exclusiones, también entran.
      expect(n().importInvoices('s0', [iline('C5', p1, 1, transaction: 10)], skipTransactions: {}).created, 1);
    });

    test('se despacha vendido − anulado; una factura anulada por completo no entra', () {
      n().importInvoices('s0', [iline('F1', p1, 5, voided: 2), iline('F2', p1, 3, voided: 3)]);
      expect(ord('FAC-F1').items.single.qty, 3);
      expect(has('FAC-F2'), isFalse);
    });

    test('anulación parcial después de importar: se ajusta si no se piquea, se marca si ya se empezó', () {
      n().importInvoices('s0', [iline('F1', p1, 5), iline('F2', p2, 4)]);
      n().calcOrderRoute('FAC-F2'); // F2 en piqueo
      final r = n().importInvoices('s0', [iline('F1', p1, 5, voided: 2), iline('F2', p2, 4, voided: 1)]);
      expect((r.voidUpdated, r.voidFlagged), (1, 1));
      expect(ord('FAC-F1').items.single.qty, 3);
      expect(ord('FAC-F1').syncNote, contains('se ajustó'));
      expect(ord('FAC-F2').items.single.qty, 4);
      expect(ord('FAC-F2').syncNote, contains('Anulada en parte en RM (revisar): $p2: 4 → 3'));
    });

    test('omite devoluciones y anulaciones', () {
      final r = n().importInvoices('s0', [iline('F902', p1, 3, transaction: 70), iline('F903', p1, 1, transaction: 71)]);
      expect((r.created, r.skipped), (0, 2));
    });

    test('REINICIO: orden piqueada ayer, su factura llega hoy → no se vuelve a despachar', () {
      n().importOpenOrders('s0', [oline('7001', p1, 4)]);
      pickAll('ORD-7001');
      c.dispose();

      boot(); // la app se abre de nuevo: órdenes e inventario vuelven a la semilla
      expect(has('ORD-7001'), isFalse);
      final r = n().importInvoices('s0', [iline('F900', p1, 4, order: '7001')]);
      expect((r.created, r.alreadyDispatched), (0, 1));
      expect(has('FAC-F900'), isFalse);
    });

    test('REINICIO: orden piqueada en parte → solo entra el resto de la factura', () {
      // NOSTOCK-1 no tiene inventario: se piquea p1 y se declara faltante el resto.
      n().importOpenOrders('s0', [oline('7001', p1, 4), oline('7001', 'NOSTOCK-1', 2)]);
      n().calcOrderRoute('ORD-7001');
      for (final key in s().pickSessions.keys.toList()) {
        for (final st in s().pickSessions[key]!.steps) {
          n().stepPicked(key, st.id);
        }
        if (s().pickSessions[key]!.shortfall != null) n().declareShortfall(key);
      }
      expect(n().confirmOrder('ORD-7001'), isTrue, reason: 'queda parcial');
      c.dispose();

      boot();
      n().importInvoices('s0', [iline('F900', p1, 4, order: '7001'), iline('F900', 'NOSTOCK-1', 2, order: '7001')]);
      final fac = ord('FAC-F900');
      expect({for (final i in fac.items) s().product(i.productId).code: i.qty}, {'NOSTOCK-1': 2});
      expect(fac.syncNote, 'Resto de ORD-7001');
    });

    test('REINICIO: orden piqueada que sigue abierta en RM no vuelve a entrar', () {
      n().importOpenOrders('s0', [oline('7001', p1, 4)]);
      pickAll('ORD-7001');
      c.dispose();

      boot();
      final r = n().importOpenOrders('s0', [oline('7001', p1, 4)]);
      expect((r.created, r.alreadyDispatched), (0, 1));
      expect(has('ORD-7001'), isFalse);
    });

    test('REINICIO: orden sin piquear vuelve a entrar completa', () {
      n().importOpenOrders('s0', [oline('7001', p1, 4)]);
      c.dispose();
      boot();
      expect(n().importOpenOrders('s0', [oline('7001', p1, 4)]).created, 1);
      expect(ord('ORD-7001').items.single.remaining, 4);
    });
  });

  group('libro de despachos (archivo)', () {
    test('falta o está dañado → vacío; poda después de 90 días', () {
      expect(DispatchLedger.load(File('${tmp.path}/no.json')).length, 0);
      File('${tmp.path}/bad.json').writeAsStringSync('{roto');
      expect(DispatchLedger.load(File('${tmp.path}/bad.json')).length, 0);

      final l = DispatchLedger(file: ledgerFile)..recordOrder('s0', 'A', 'ORD-A', DateTime(2026, 1, 1));
      l.recordOrder('s0', 'B', 'ORD-B', DateTime(2026, 10, 1));
      l.save();
      final back = DispatchLedger.load(ledgerFile, now: DateTime(2026, 10, 13));
      expect(back.order('s0', 'A'), isNull);
      expect(back.order('s0', 'B')!.appId, 'ORD-B');
    });
  });
}
