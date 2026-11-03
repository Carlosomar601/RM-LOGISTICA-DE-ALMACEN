// Motor de auditoría de canastas — Dart puro, sin dependencias de Flutter.
import 'dart:math';

import '../models/audit.dart';
import '../models/inv_row.dart';
import 'pick_engine.dart';

/// Nombre del área donde queda lo que falta.
const kPendingArea = 'PENDIENTES';

/// Unidades esperadas por producto según la foto de la canasta.
Map<String, int> expectedByProduct(List<AuditExpected> expected) {
  final m = <String, int>{};
  for (final e in expected) {
    m[e.productId] = (m[e.productId] ?? 0) + e.qty;
  }
  return m;
}

/// Conteo final: el reconteo reemplaza al primer conteo en las líneas reconteadas.
Map<String, int> finalCounts(AuditBin b) => {...b.counts, ...?b.recounts};

AuditResult classify(int expected, int counted) {
  if (counted == expected) return AuditResult.ok;
  if (expected == 0) return AuditResult.noRegistrado;
  if (counted == 0) return AuditResult.noEsta;
  return counted < expected ? AuditResult.faltante : AuditResult.sobrante;
}

/// Productos cuyo primer conteo no coincide con lo esperado (se ofrecen para reconteo).
/// Orden: primero los esperados (en el orden de la foto), luego los no registrados.
List<String> diffProducts(AuditBin b) {
  final exp = expectedByProduct(b.expected);
  final ids = <String>[...exp.keys, ...b.counts.keys.where((k) => !exp.containsKey(k))];
  return [for (final id in ids) if ((b.counts[id] ?? 0) != (exp[id] ?? 0)) id];
}

/// Calcula las líneas de resultado. Conserva el motivo ya asignado a un producto
/// si su resultado no cambió.
List<AuditLine> computeLines(AuditBin b) {
  final exp = expectedByProduct(b.expected);
  final counts = finalCounts(b);
  final ids = <String>[...exp.keys, ...counts.keys.where((k) => !exp.containsKey(k))];
  final prev = {for (final l in b.lines) l.productId: l};
  final lines = <AuditLine>[];
  for (final id in ids) {
    final e = exp[id] ?? 0;
    final c = counts[id] ?? 0;
    if (e == 0 && c == 0) continue;
    final r = classify(e, c);
    final old = prev[id];
    final keep = old != null && old.result == r;
    lines.add(AuditLine(
      productId: id,
      expected: e,
      counted: c,
      result: r,
      reason: keep ? old.reason : null,
      reasonNote: keep ? old.reasonNote : null,
      matchedPendingId: keep ? old.matchedPendingId : null,
    ));
  }
  return lines;
}

/// Error si alguna diferencia no tiene motivo (o «Otro» sin nota). null = se puede cerrar.
String? linesReadyToClose(List<AuditLine> lines) {
  for (final l in lines) {
    if (l.isOk) continue;
    if (l.reason == null || l.reason!.isEmpty) return 'Toda diferencia necesita un motivo.';
    if (l.reason == kReasonOther && (l.reasonNote ?? '').trim().isEmpty) {
      return 'El motivo «Otro» necesita una nota.';
    }
  }
  return null;
}

/// Porción descontada de una fila de inventario (conserva lote, fecha y recibo).
class TakenPortion {
  const TakenPortion({
    required this.productId,
    required this.qty,
    required this.lot,
    required this.entryDate,
    required this.receipt,
    required this.bin,
  });
  final String productId;
  final int qty;
  final String lot;
  final DateTime entryDate;
  final String receipt;
  final String bin;
}

/// Descuenta [qty] unidades de [productId] en la canasta, de la fila más antigua a la más nueva.
/// Elimina las filas que quedan en 0. Devuelve lo descontado por fila.
List<TakenPortion> takeOldestFromBin(List<InvRow> inventory, String store, String bin, String productId, int qty) {
  final rows = fifoSorted(
      inventory.where((r) => r.store == store && r.bin == bin && r.productId == productId && r.qty > 0));
  var remaining = qty;
  final out = <TakenPortion>[];
  for (final r in rows) {
    if (remaining <= 0) break;
    final take = min(r.qty, remaining);
    r.qty -= take;
    remaining -= take;
    out.add(TakenPortion(
      productId: productId,
      qty: take,
      lot: r.lot,
      entryDate: r.entryDate,
      receipt: r.receipt,
      bin: bin,
    ));
  }
  inventory.removeWhere((r) => r.qty <= 0);
  return out;
}

// ---------- Reporte de exactitud ----------

enum AccuracyGroup { canasta, zona, auditor, motivo }

const kAccuracyGroupLabels = <AccuracyGroup, String>{
  AccuracyGroup.canasta: 'Canasta',
  AccuracyGroup.zona: 'Zona',
  AccuracyGroup.auditor: 'Auditor',
  AccuracyGroup.motivo: 'Motivo',
};

class AccuracyRow {
  AccuracyRow(this.key);
  final String key;
  int lines = 0;
  int okLines = 0;
  int expectedUnits = 0;
  int diffUnits = 0;

  /// Líneas OK / líneas (1.0 = 100 %).
  double get lineAccuracy => lines == 0 ? 1 : okLines / lines;

  /// 1 − Σ|diferencia| / Σ esperado (mínimo 0).
  double get unitAccuracy =>
      expectedUnits == 0 ? (diffUnits == 0 ? 1 : 0) : max(0, 1 - diffUnits / expectedUnits).toDouble();
}

/// Canastas cerradas dentro del rango (por fecha de cierre, inclusivo por día).
Iterable<(Audit, AuditBin)> closedAuditBins(Iterable<Audit> audits, {DateTime? from, DateTime? to}) sync* {
  for (final a in audits) {
    for (final b in a.bins) {
      if (b.status != AuditBinStatus.cerrada || b.closedAt == null) continue;
      final d = DateTime(b.closedAt!.year, b.closedAt!.month, b.closedAt!.day);
      if (from != null && d.isBefore(DateTime(from.year, from.month, from.day))) continue;
      if (to != null && d.isAfter(DateTime(to.year, to.month, to.day))) continue;
      yield (a, b);
    }
  }
}

/// Total general (todas las líneas de las canastas cerradas del rango).
AccuracyRow accuracyTotal(Iterable<Audit> audits, {DateTime? from, DateTime? to}) {
  final row = AccuracyRow('Total');
  for (final (_, b) in closedAuditBins(audits, from: from, to: to)) {
    for (final l in b.lines) {
      _add(row, l);
    }
  }
  return row;
}

/// Exactitud agrupada. Por motivo solo entran las líneas con diferencia.
List<AccuracyRow> accuracyBy(Iterable<Audit> audits, AccuracyGroup g, {DateTime? from, DateTime? to}) {
  final rows = <String, AccuracyRow>{};
  for (final (_, b) in closedAuditBins(audits, from: from, to: to)) {
    for (final l in b.lines) {
      final String key;
      switch (g) {
        case AccuracyGroup.canasta:
          key = b.bin;
        case AccuracyGroup.zona:
          key = b.zone.isEmpty ? 'Sin zona' : b.zone;
        case AccuracyGroup.auditor:
          key = b.auditor ?? '—';
        case AccuracyGroup.motivo:
          if (l.isOk) continue;
          key = l.reason ?? 'Sin motivo';
      }
      _add(rows.putIfAbsent(key, () => AccuracyRow(key)), l);
    }
  }
  final list = rows.values.toList()..sort((a, b) => a.key.compareTo(b.key));
  return list;
}

void _add(AccuracyRow row, AuditLine l) {
  row.lines++;
  if (l.isOk) row.okLines++;
  row.expectedUnits += l.expected;
  row.diffUnits += l.diff.abs();
}
