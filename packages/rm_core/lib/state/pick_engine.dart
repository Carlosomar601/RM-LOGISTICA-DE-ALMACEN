// Motor de sesiones de piqueo FIFO — Dart puro, sin dependencias de Flutter.
import '../models/inv_row.dart';
import '../models/movement.dart';
import '../models/pick_session.dart';

const kCentralStore = 'Almacén Central';

typedef IdFn = String Function();

/// Ordena ascendentemente por fecha de entrada (el más antiguo primero).
/// Orden estable: empates conservan el orden original.
List<InvRow> fifoSorted(Iterable<InvRow> rows) {
  final indexed = rows.toList().asMap().entries.toList()
    ..sort((a, b) {
      final c = a.value.entryDate.compareTo(b.value.entryDate);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}

class BuiltSteps {
  const BuiltSteps(this.steps, this.shortfall);
  final List<PickStep> steps;
  final int shortfall;
}

BuiltSteps buildLocationSteps(
  List<InvRow> inventory,
  String productId,
  int qty,
  Set<String> excludeInvIds,
  IdFn nextStepId, {
  Set<String> lockedBins = const {},
}) {
  final rows = fifoSorted(inventory.where((r) =>
      r.productId == productId &&
      r.store == kCentralStore &&
      r.qty > 0 &&
      !lockedBins.contains(r.bin) &&
      !excludeInvIds.contains(r.id)));
  var remaining = qty;
  final steps = <PickStep>[];
  for (final row in rows) {
    if (remaining <= 0) break;
    final take = row.qty < remaining ? row.qty : remaining;
    steps.add(PickStep(
      id: nextStepId(),
      invId: row.id,
      bin: row.bin,
      receipt: row.receipt,
      entryDate: row.entryDate,
      available: row.qty,
      take: take,
    ));
    remaining -= take;
  }
  return BuiltSteps(steps, remaining < 0 ? 0 : remaining);
}

PickSession createPickSession(
  List<InvRow> inventory, {
  required String key,
  required String productId,
  required int qty,
  required String doc,
  required IdFn nextId,
  Set<String> lockedBins = const {},
}) {
  final built = buildLocationSteps(inventory, productId, qty, const {}, nextId, lockedBins: lockedBins);
  return PickSession(
    key: key,
    productId: productId,
    qtyRequested: qty,
    doc: doc,
    steps: built.steps,
    shortfall: built.shortfall > 0 ? Shortfall(id: nextId(), take: built.shortfall) : null,
  );
}

int committedQty(PickSession s) => s.steps
    .where((st) => st.status == StepStatus.pending || st.status == StepStatus.picked)
    .fold(0, (a, st) => a + st.take);

int acceptedMissingQty(PickSession s) =>
    s.shortfall?.status == ShortfallStatus.missing ? s.shortfall!.take : 0;

int pickedQty(PickSession s) =>
    s.steps.where((st) => st.status == StepStatus.picked).fold(0, (a, st) => a + st.take);

void reflowSession(PickSession s, List<InvRow> inventory, IdFn nextId, {Set<String> lockedBins = const {}}) {
  final used = s.steps.map((st) => st.invId).toSet();
  final need = s.qtyRequested - committedQty(s) - acceptedMissingQty(s);
  if (need > 0) {
    final built = buildLocationSteps(inventory, s.productId, need, used, nextId, lockedBins: lockedBins);
    s.steps.addAll(built.steps);
    if (built.shortfall > 0) {
      final prev = s.shortfall;
      if (prev != null && prev.status == ShortfallStatus.missing) {
        // Ya hay un faltante aceptado: se acumula el nuevo como no resuelto.
        s.shortfall = Shortfall(id: prev.id, take: prev.take + built.shortfall);
      } else {
        s.shortfall = Shortfall(id: prev?.id ?? nextId(), take: built.shortfall);
      }
    } else if (s.shortfall?.status == ShortfallStatus.unresolved) {
      s.shortfall = null;
    }
  } else if (s.shortfall?.status == ShortfallStatus.unresolved) {
    s.shortfall = null;
  }
}

bool sessionCanConfirm(PickSession s) =>
    s.steps.every((st) => st.status != StepStatus.pending) &&
    (s.shortfall == null || s.shortfall!.status != ShortfallStatus.unresolved);

int pendingCount(PickSession s) => s.steps.where((st) => st.status == StepStatus.pending).length;

// ---- Acciones ----

void markPicked(PickSession s, String stepId) {
  for (final st in s.steps) {
    if (st.id == stepId && st.status == StepStatus.pending) st.status = StepStatus.picked;
  }
}

void markMissingHere(PickSession s, String stepId, List<InvRow> inventory, IdFn nextId,
    {Set<String> lockedBins = const {}}) {
  var changed = false;
  for (final st in s.steps) {
    if (st.id == stepId && st.status == StepStatus.pending) {
      st.status = StepStatus.missingHere;
      changed = true;
    }
  }
  if (changed) reflowSession(s, inventory, nextId, lockedBins: lockedBins);
}

void declareShortfallMissing(PickSession s, List<InvRow> inventory, IdFn nextId,
    {Set<String> lockedBins = const {}}) {
  final sf = s.shortfall;
  if (sf == null || sf.status != ShortfallStatus.unresolved) return;
  sf.status = ShortfallStatus.missing;
  reflowSession(s, inventory, nextId, lockedBins: lockedBins);
}

/// Lo que no estaba en una canasta al piquear: pasa a PENDIENTES con su lote y fecha.
class PickPendingOut {
  const PickPendingOut({
    required this.movementId,
    required this.productId,
    required this.qty,
    required this.bin,
    required this.lot,
    required this.entryDate,
    required this.receipt,
  });
  final String movementId;
  final String productId;
  final int qty;
  final String bin;
  final String lot;
  final DateTime entryDate;
  final String receipt;
}

/// Motivo con que el piqueo envía a PENDIENTES.
const kPickMissingReason = 'No estaba en la canasta (piqueo)';

class CommitResult {
  const CommitResult(this.delivered, this.shortQty, this.movements, [this.pendingOut = const []]);
  final int delivered;
  final int shortQty;

  /// Movimientos en orden cronológico (el último es el más reciente).
  final List<Movement> movements;

  /// Filas «No estaba aquí» que van a PENDIENTES.
  final List<PickPendingOut> pendingOut;
}

CommitResult commitPickSession(
  PickSession s,
  List<InvRow> inventory, {
  required String docLabel,
  required String dispatchLabel,
  required String user,
  required DateTime now,
  required IdFn nextMovementId,
}) {
  final movements = <Movement>[];
  final pendingOut = <PickPendingOut>[];
  InvRow? rowById(String id) {
    for (final r in inventory) {
      if (r.id == id) return r;
    }
    return null;
  }

  var delivered = 0;
  for (final st in s.steps) {
    if (st.status == StepStatus.picked) {
      final row = rowById(st.invId);
      if (row != null) row.qty = (row.qty - st.take).clamp(0, 1 << 30);
      delivered += st.take;
      movements.add(Movement(
        id: nextMovementId(),
        type: 'piqueo',
        productId: s.productId,
        qty: st.take,
        doc: docLabel,
        user: user,
        dateTime: now,
        from: '$kCentralStore / ${st.bin}',
        to: dispatchLabel,
      ));
    } else if (st.status == StepStatus.missingHere) {
      final row = rowById(st.invId);
      // Solo se aparta lo que todavía está registrado en la fila (puede haber cambiado).
      final qty = row == null ? 0 : (row.qty < st.available ? row.qty : st.available);
      if (row == null || qty <= 0) continue;
      row.qty -= qty;
      final id = nextMovementId();
      movements.add(Movement(
        id: id,
        type: 'a-pendientes',
        productId: s.productId,
        qty: qty,
        doc: docLabel,
        user: user,
        dateTime: now,
        from: '$kCentralStore / ${st.bin}',
        to: 'PENDIENTES',
        note: kPickMissingReason,
      ));
      pendingOut.add(PickPendingOut(
        movementId: id,
        productId: s.productId,
        qty: qty,
        bin: st.bin,
        lot: row.lot,
        entryDate: row.entryDate,
        receipt: row.receipt,
      ));
    }
  }
  inventory.removeWhere((r) => r.qty <= 0);

  final sf = s.shortfall;
  if (sf != null && sf.status == ShortfallStatus.missing) {
    movements.add(Movement(
      id: nextMovementId(),
      type: 'no-encontrado',
      productId: s.productId,
      qty: sf.take,
      doc: docLabel,
      user: user,
      dateTime: now,
      from: kCentralStore,
      to: '—',
    ));
  }
  return CommitResult(delivered, s.qtyRequested - delivered, movements, pendingOut);
}
