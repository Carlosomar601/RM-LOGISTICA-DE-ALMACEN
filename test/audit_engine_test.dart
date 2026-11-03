import 'package:flutter_test/flutter_test.dart';
import 'package:piqueo_fifo_centeno/data/seed.dart';
import 'package:piqueo_fifo_centeno/models/audit.dart';
import 'package:piqueo_fifo_centeno/models/inv_row.dart';
import 'package:piqueo_fifo_centeno/state/audit_engine.dart';

AuditExpected exp(String pid, int qty, {String lot = 'L-1', DateTime? date}) => AuditExpected(
      invId: 'inv-$pid-$lot',
      productId: pid,
      qty: qty,
      lot: lot,
      entryDate: date ?? DateTime(2026, 9, 1),
      receipt: 'REC-1',
    );

InvRow row(String id, String pid, String bin, int qty, DateTime date, String lot) => InvRow(
      id: id,
      productId: pid,
      store: kCentral,
      bin: bin,
      qty: qty,
      entryDate: date,
      receipt: 'REC-$lot',
      lot: lot,
      user: 'M. Rivera',
    );

void main() {
  test('clasifica los cinco resultados', () {
    expect(classify(10, 10), AuditResult.ok);
    expect(classify(10, 7), AuditResult.faltante);
    expect(classify(10, 0), AuditResult.noEsta);
    expect(classify(10, 12), AuditResult.sobrante);
    expect(classify(0, 3), AuditResult.noRegistrado);
  });

  test('líneas: esperado por producto, no contado = NO ESTÁ, el reconteo gana', () {
    final b = AuditBin(bin: 'A-01-01', zone: 'Zona A', expected: [
      exp('p1', 6, lot: 'L-1'),
      exp('p1', 4, lot: 'L-2'),
      exp('p2', 5),
      exp('p3', 2),
    ], counts: {
      'p1': 8,
      'p2': 5,
      'p9': 1,
    });
    expect(diffProducts(b), ['p1', 'p3', 'p9']);
    b.recounts = {'p1': 10, 'p3': 0, 'p9': 1};
    final lines = {for (final l in computeLines(b)) l.productId: l};
    expect(lines['p1']!.expected, 10);
    expect(lines['p1']!.result, AuditResult.ok);
    expect(lines['p2']!.result, AuditResult.ok);
    expect(lines['p3']!.result, AuditResult.noEsta);
    expect(lines['p3']!.diff, -2);
    expect(lines['p9']!.result, AuditResult.noRegistrado);
  });

  test('recalcular conserva el motivo si el resultado no cambia', () {
    final b = AuditBin(bin: 'X', zone: '', expected: [exp('p1', 5)], counts: {'p1': 3});
    b.lines = computeLines(b);
    b.lines.single.reason = 'Dañado';
    expect(computeLines(b).single.reason, 'Dañado');
    b.counts['p1'] = 7;
    expect(computeLines(b).single.reason, isNull);
  });

  test('toda diferencia exige motivo; «Otro» exige nota', () {
    final lines = [
      AuditLine(productId: 'p1', expected: 5, counted: 5, result: AuditResult.ok),
      AuditLine(productId: 'p2', expected: 5, counted: 3, result: AuditResult.faltante),
    ];
    expect(linesReadyToClose(lines), isNotNull);
    lines[1].reason = kReasonOther;
    expect(linesReadyToClose(lines), contains('nota'));
    lines[1].reasonNote = 'se mojó';
    expect(linesReadyToClose(lines), isNull);
  });

  test('descuenta de la fila más antigua y conserva lote y fecha', () {
    final old = DateTime(2026, 8, 1), mid = DateTime(2026, 8, 20), young = DateTime(2026, 9, 10);
    final inv = [
      row('a', 'p1', 'A-01-01', 3, young, 'L-NEW'),
      row('b', 'p1', 'A-01-01', 4, old, 'L-OLD'),
      row('c', 'p1', 'A-01-01', 5, mid, 'L-MID'),
      row('d', 'p1', 'B-01-01', 9, old, 'L-OTHER'),
    ];
    final taken = takeOldestFromBin(inv, kCentral, 'A-01-01', 'p1', 6);
    expect(taken.map((t) => (t.lot, t.qty)).toList(), [('L-OLD', 4), ('L-MID', 2)]);
    expect(taken.first.entryDate, old);
    expect(inv.any((r) => r.id == 'b'), isFalse, reason: 'la fila en 0 se elimina');
    expect(inv.firstWhere((r) => r.id == 'c').qty, 3);
    expect(inv.firstWhere((r) => r.id == 'd').qty, 9, reason: 'otra canasta no se toca');
  });

  test('exactitud por canasta, auditor, motivo y total', () {
    AuditBin closed(String bin, String auditor, List<AuditLine> lines) => AuditBin(
          bin: bin,
          zone: 'Zona A',
          status: AuditBinStatus.cerrada,
          auditor: auditor,
          closedAt: DateTime(2026, 9, 15),
          lines: lines,
        );
    final a = Audit(
      id: 'AUD-1',
      scopeLabel: 'Zona A',
      createdBy: 'M. Rivera',
      createdAt: DateTime(2026, 9, 15),
      status: AuditStatus.cerrada,
      bins: [
        closed('A-01-01', 'A. Torres', [
          AuditLine(productId: 'p1', expected: 10, counted: 10, result: AuditResult.ok),
          AuditLine(productId: 'p2', expected: 10, counted: 8, result: AuditResult.faltante, reason: 'Perdido'),
        ]),
        closed('A-01-02', 'J. Nieves', [
          AuditLine(productId: 'p3', expected: 20, counted: 20, result: AuditResult.ok),
        ]),
        AuditBin(bin: 'A-01-03', zone: 'Zona A', status: AuditBinStatus.cancelada),
      ],
    );
    final total = accuracyTotal([a]);
    expect(total.lines, 3);
    expect(total.okLines, 2);
    expect(total.lineAccuracy, closeTo(2 / 3, 1e-9));
    expect(total.unitAccuracy, closeTo(1 - 2 / 40, 1e-9));

    final byBin = {for (final r in accuracyBy([a], AccuracyGroup.canasta)) r.key: r};
    expect(byBin.keys, ['A-01-01', 'A-01-02']);
    expect(byBin['A-01-01']!.unitAccuracy, closeTo(0.9, 1e-9));
    expect(byBin['A-01-02']!.lineAccuracy, 1);

    final byAuditor = {for (final r in accuracyBy([a], AccuracyGroup.auditor)) r.key: r};
    expect(byAuditor['A. Torres']!.lineAccuracy, 0.5);

    final byReason = accuracyBy([a], AccuracyGroup.motivo);
    expect(byReason.map((r) => (r.key, r.lines, r.diffUnits)).toList(), [('Perdido', 1, 2)]);

    expect(accuracyBy([a], AccuracyGroup.zona).single.key, 'Zona A');
    expect(accuracyTotal([a], from: DateTime(2026, 9, 16)).lines, 0, reason: 'fuera del periodo');
  });
}
