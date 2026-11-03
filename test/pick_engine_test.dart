import 'package:flutter_test/flutter_test.dart';
import 'package:rm_core/data/seed.dart';
import 'package:rm_core/models/inv_row.dart';
import 'package:rm_core/models/pick_session.dart';
import 'package:rm_core/state/pick_engine.dart';
import 'package:rm_core/util/clock.dart';

void main() {
  late List<InvRow> inv;
  var n = 0;
  String nextId() => 'id${n++}';

  setUp(() {
    inv = seedInventory();
    n = 0;
  });

  InvRow row(String pid, String bin) =>
      inv.firstWhere((r) => r.productId == pid && r.bin == bin);

  group('fifoSorted', () {
    test('ordena del más antiguo al más reciente', () {
      final rows = fifoSorted(inv.where((r) => r.productId == 'p1'));
      expect(rows.map((r) => r.bin).toList(), ['A-01-01', 'A-01-02', 'SP-01', 'B-02-01']);
    });
  });

  group('buildLocationSteps', () {
    test('p1 × 40 recorre 3 canastas FIFO de Almacén Central (14 + 20 + 6)', () {
      final b = buildLocationSteps(inv, 'p1', 40, {}, nextId);
      expect(b.steps.map((s) => (s.bin, s.take)).toList(),
          [('A-01-01', 14), ('A-01-02', 20), ('B-02-01', 6)]);
      expect(b.shortfall, 0);
    });

    test('ignora sucursales y reporta faltante', () {
      final b = buildLocationSteps(inv, 'p6', 30, {}, nextId);
      expect(b.steps.map((s) => s.bin).toList(), ['A-01-04', 'B-01-02']);
      expect(b.shortfall, 12);
    });

    test('excluye ids indicados', () {
      final b = buildLocationSteps(inv, 'p3', 5, {row('p3', 'C-03-02').id}, nextId);
      expect(b.steps.single.bin, 'A-02-01');
    });

    test('OV-10501: p1→A-01-01(4); p3→C-03-02(8)+A-02-01(7); p6→A-01-04(7)+B-01-02(3)', () {
      expect(buildLocationSteps(inv, 'p1', 4, {}, nextId).steps.map((s) => (s.bin, s.take)),
          [('A-01-01', 4)]);
      expect(buildLocationSteps(inv, 'p3', 15, {}, nextId).steps.map((s) => (s.bin, s.take)),
          [('C-03-02', 8), ('A-02-01', 7)]);
      expect(buildLocationSteps(inv, 'p6', 10, {}, nextId).steps.map((s) => (s.bin, s.take)),
          [('A-01-04', 7), ('B-01-02', 3)]);
    });
  });

  group('reflowSession', () {
    test('"No está aquí" agrega reemplazos y luego un faltante sin resolver', () {
      final s = createPickSession(inv, key: 'k', productId: 'p6', qty: 10, doc: 'OV', nextId: nextId);
      expect(s.shortfall, isNull);
      final b2 = s.steps[1];
      markMissingHere(s, b2.id, inv, nextId);
      expect(b2.status, StepStatus.missingHere);
      expect(s.steps.length, 2); // no hay más canastas en Almacén Central
      expect(s.shortfall!.take, 3);
      expect(s.shortfall!.status, ShortfallStatus.unresolved);
      expect(sessionCanConfirm(s), isFalse);
    });

    test('reemplazo se agrega al final y excluye los ya usados', () {
      final s = createPickSession(inv, key: 'k', productId: 'p1', qty: 10, doc: 'OV', nextId: nextId);
      expect(s.steps.single.bin, 'A-01-01');
      markMissingHere(s, s.steps.first.id, inv, nextId);
      expect(s.steps.map((st) => (st.bin, st.take)).toList(), [('A-01-01', 10), ('A-01-02', 10)]);
      expect(s.shortfall, isNull);
    });

    test('declarar faltante permite confirmar', () {
      final s = createPickSession(inv, key: 'k', productId: 'p6', qty: 10, doc: 'OV', nextId: nextId);
      markPicked(s, s.steps[0].id);
      markMissingHere(s, s.steps[1].id, inv, nextId);
      declareShortfallMissing(s, inv, nextId);
      expect(s.shortfall!.status, ShortfallStatus.missing);
      expect(sessionCanConfirm(s), isTrue);
    });

    test('al aparecer existencia nueva, el faltante sin resolver se elimina', () {
      final s = createPickSession(inv, key: 'k', productId: 'p9', qty: 3, doc: 'OV', nextId: nextId);
      expect(s.steps, isEmpty);
      expect(s.shortfall!.take, 3);
      inv.add(InvRow(
          id: 'new', productId: 'p9', store: kCentral, bin: 'AL-RX', qty: 4,
          entryDate: kToday, receipt: 'TS-0089', lot: '—', user: 'C. Omar'));
      reflowSession(s, inv, nextId);
      expect(s.steps.single.take, 3);
      expect(s.shortfall, isNull);
    });
  });

  group('commitPickSession', () {
    test('herramienta individual p1 × 40: B-02-01 queda en 12 y A-01-01/A-01-02 desaparecen', () {
      final s = createPickSession(inv, key: 'k', productId: 'p1', qty: 40, doc: 'OV-10482', nextId: nextId);
      for (final st in s.steps) {
        markPicked(s, st.id);
      }
      final r = commitPickSession(s, inv,
          docLabel: 'OV-10482', dispatchLabel: 'Despacho', user: 'C. Omar', now: kToday, nextMovementId: nextId);
      expect(r.delivered, 40);
      expect(r.shortQty, 0);
      expect(row('p1', 'B-02-01').qty, 12);
      expect(inv.where((x) => x.productId == 'p1' && x.bin.startsWith('A-01')), isEmpty);
      expect(r.movements.map((m) => m.type), ['piqueo', 'piqueo', 'piqueo']);
    });

    test('parcial: piqueo + a-pendientes + no-encontrado', () {
      final s = createPickSession(inv, key: 'k', productId: 'p6', qty: 10, doc: 'OV-10501', nextId: nextId);
      markPicked(s, s.steps[0].id);
      markMissingHere(s, s.steps[1].id, inv, nextId);
      declareShortfallMissing(s, inv, nextId);
      final r = commitPickSession(s, inv,
          docLabel: 'OV-10501', dispatchLabel: 'Sucursal Río Piedras', user: 'C. Omar', now: kToday,
          nextMovementId: nextId);
      expect(r.delivered, 7);
      expect(r.shortQty, 3);
      expect(r.movements.map((m) => m.type), ['piqueo', 'a-pendientes', 'no-encontrado']);
      expect(r.movements[1].qty, 11);
      expect(r.movements[1].to, 'PENDIENTES');
      expect(r.movements[1].note, kPickMissingReason);
      expect(r.movements[2].qty, 3);
      // Lo que no estaba sale con su lote y fecha para PENDIENTES.
      expect(r.pendingOut.length, 1);
      expect(r.pendingOut.single.bin, 'B-01-02');
      expect(r.pendingOut.single.qty, 11);
      expect(r.pendingOut.single.movementId, r.movements[1].id);
      // A-01-04 (7) piqueado por completo y B-01-02 ajustado a 0 → ambos desaparecen.
      expect(inv.where((x) => x.productId == 'p6' && x.store == kCentral), isEmpty);
    });
  });
}
