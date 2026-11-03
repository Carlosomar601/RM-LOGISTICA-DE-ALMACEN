import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rm_core/auth/user_store.dart';
import 'package:rm_core/data/seed.dart';
import 'package:rm_core/models/app_user.dart';
import 'package:rm_core/models/audit.dart';
import 'package:rm_core/models/pending_item.dart';
import 'package:rm_core/models/pick_session.dart';
import 'package:rm_core/state/app_state.dart';
import 'package:rm_core/state/audit_engine.dart';

void main() {
  late ProviderContainer c;
  AppState s() => c.read(appProvider);
  AppNotifier n() => c.read(appProvider.notifier);

  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  int qtyIn(String pid, String bin) => s()
      .inventory
      .where((r) => r.productId == pid && r.store == kCentral && r.bin == bin)
      .fold(0, (a, r) => a + r.qty);

  /// Cuenta A-01-02 (sistema: p1 × 20, lote L-2231) con [p1] unidades y [p2] de un producto no registrado.
  String countA0102({int p1 = 16, int p2 = 0, bool close = true}) {
    final id = n().createAudit(bins: ['A-01-02']).id!;
    expect(n().startBinCount(id, 'a-01-02'), isNull);
    expect(n().addCount(id, 'A-01-02', 'mi-20565r15', p1), isNull);
    if (p2 > 0) expect(n().addCount(id, 'A-01-02', 'GY-19565R15', p2), isNull);
    final r = n().finishBinCount(id, 'A-01-02');
    if (r.recount.isNotEmpty) expect(n().submitRecount(id, 'A-01-02', {}, skip: true), isNull);
    if (close) {
      n().setLineReason(id, 'A-01-02', 'p1', 'Error de piqueo');
      if (p2 > 0) n().setLineReason(id, 'A-01-02', 'p2', 'En otra canasta');
      expect(n().closeAuditBin(id, 'A-01-02'), isNull);
    }
    return id;
  }

  test('crear por zona incluye todas sus canastas; una canasta no entra en dos auditorías', () {
    final r = n().createAudit(zone: 'Zona A');
    expect(r.error, isNull);
    final a = s().audits.first;
    expect(a.scopeLabel, 'Zona: Zona A');
    expect(a.bins.map((b) => b.bin), containsAll(['A-01-01', 'A-01-02', 'A-03-03']));
    expect(a.bins.every((b) => b.bin.startsWith('A-')), isTrue);
    expect(n().createAudit(bins: ['A-01-02']).error, contains(r.id!));
    expect(n().createAudit(bins: ['RECIBO']).error, isNotNull, reason: 'recepción no se audita');
    expect(n().createAudit().error, isNotNull);
    expect(s().lockedBins, isEmpty, reason: 'se bloquea al escanear, no al crear');
  });

  test('canasta en conteo: bloquea piqueo, transferencias, recibo y administración', () {
    final id = n().createAudit(bins: ['A-01-02']).id!;
    expect(n().startBinCount(id, 'A-01-99'), isNotNull);
    expect(n().startBinCount(id, 'A-01-02'), isNull);
    expect(s().lockedBins, {'A-01-02'});
    expect(s().audits.first.bins.single.expected.single.qty, 20);

    // Piqueo: la ruta FIFO salta A-01-02.
    n().suggestSingle('p1', 40, 'OV-1');
    final sess = s().pickSessions[s().singleKey]!;
    expect(sess.steps.map((st) => st.bin), ['A-01-01', 'B-02-01']);
    expect(sess.shortfall!.take, 8);

    final src = s().inventory.firstWhere((r) => r.productId == 'p1' && r.bin == 'A-01-02');
    expect(n().binTransfer(productId: 'p1', srcRowId: src.id, destBin: 'C-01-01', qty: 1), contains('auditoría'));
    final src2 = s().inventory.firstWhere((r) => r.productId == 'p1' && r.bin == 'A-01-01');
    expect(n().binTransfer(productId: 'p1', srcRowId: src2.id, destBin: 'A-01-02', qty: 1), contains('auditoría'));
    expect(n().binTransferAll(from: 'A-01-02', to: 'C-01-01'), contains('auditoría'));
    expect(n().allocateReceiptItem('REC-3430', 'p1', [('A-01-02', 5)]), contains('auditoría'));
    expect(n().storeTransferSend(productId: 'p1', fromStore: kCentral, toStore: 'Sucursal Ponce', qty: 40).error,
        isNotNull);
    final bin = s().bins.firstWhere((b) => b.code == 'A-01-02');
    expect(n().updateBin(bin.id, active: false), contains('auditoría'));
    expect(n().deleteBin(bin.id), contains('auditoría'));
    expect(n().updateBin(bin.id, zone: 'Pasillo 1'), isNull, reason: 'cambiar la zona sí se permite');
  });

  test('al bloquear, los pasos por recoger en esa canasta se reubican', () {
    n().suggestSingle('p1', 10, 'OV-1');
    expect(s().pickSessions[s().singleKey]!.steps.single.bin, 'A-01-01');
    final id = n().createAudit(bins: ['A-01-01']).id!;
    expect(n().startBinCount(id, 'A-01-01'), isNull);
    expect(s().pickSessions[s().singleKey]!.steps.single.bin, 'A-01-02');
  });

  test('no se empieza a contar si hay mercancía recogida sin confirmar en la canasta', () {
    n().suggestSingle('p1', 10, 'OV-77');
    final st = s().pickSessions[s().singleKey]!.steps.single;
    n().stepPicked(s().singleKey, st.id);
    final id = n().createAudit(bins: ['A-01-01']).id!;
    expect(n().startBinCount(id, 'A-01-01'), contains('OV-77'));
    expect(s().lockedBins, isEmpty);
    n().confirmSingle();
    expect(n().startBinCount(id, 'A-01-01'), isNull);
  });

  test('un paso ya trazado en una canasta bloqueada no se puede marcar', () {
    n().suggestSingle('p1', 40, 'OV-1');
    final step = s().pickSessions[s().singleKey]!.steps.firstWhere((st) => st.bin == 'A-01-02');
    // Bloqueo directo (sin reubicar) para simular una sesión vieja.
    final id = n().createAudit(bins: ['A-01-02']).id!;
    s().audits.first.bins.single.status = AuditBinStatus.contando;
    expect(n().stepPicked(s().singleKey, step.id), contains(id));
    expect(step.status, StepStatus.pending);
  });

  test('conteo, reconteo y cierre: faltante a PENDIENTES con lote y fecha; no registrado se suma', () {
    final date = s().inventory.firstWhere((r) => r.productId == 'p1' && r.bin == 'A-01-02').entryDate;
    final id = n().createAudit(bins: ['A-01-02']).id!;
    expect(n().addCount(id, 'A-01-02', 'MI-20565R15', 1), isNotNull, reason: 'primero se escanea la canasta');
    n().startBinCount(id, 'A-01-02');
    expect(n().addCount(id, 'A-01-02', 'NO-EXISTE', 1), contains('No existe'));
    n().addCount(id, 'A-01-02', 'mi-20565r15', 10);
    n().addCount(id, 'A-01-02', 'MI-20565R15', 5);
    n().addCount(id, 'A-01-02', 'GY-19565R15', 2);
    final r = n().finishBinCount(id, 'A-01-02');
    expect(r.recount, ['p1', 'p2']);
    expect(n().addCount(id, 'A-01-02', 'MI-20565R15', 1), isNotNull, reason: 'el primer conteo quedó fijo');
    expect(n().submitRecount(id, 'A-01-02', {'p1': 16}), isNotNull, reason: 'falta p2');
    expect(n().submitRecount(id, 'A-01-02', {'p1': 16, 'p2': 2}), isNull);
    final b = s().audits.first.bins.single;
    expect(b.status, AuditBinStatus.contada);
    expect(b.counts['p1'], 15);
    final lines = {for (final l in b.lines) l.productId: l};
    expect(lines['p1']!.result, AuditResult.faltante);
    expect(lines['p1']!.diff, -4);
    expect(lines['p2']!.result, AuditResult.noRegistrado);
    expect(s().lockedBins, {'A-01-02'}, reason: 'sigue bloqueada hasta cerrar');

    expect(n().closeAuditBin(id, 'A-01-02'), contains('motivo'));
    n().setLineReason(id, 'A-01-02', 'p1', 'Error de piqueo');
    n().setLineReason(id, 'A-01-02', 'p2', kReasonOther);
    expect(n().closeAuditBin(id, 'A-01-02'), contains('nota'));
    n().setLineReason(id, 'A-01-02', 'p2', kReasonOther, note: 'etiqueta cambiada');
    expect(n().closeAuditBin(id, 'A-01-02'), isNull);

    expect(qtyIn('p1', 'A-01-02'), 16);
    expect(qtyIn('p2', 'A-01-02'), 2);
    final pen = s().openPending.single;
    expect((pen.productId, pen.qty, pen.lot, pen.entryDate, pen.receipt), ('p1', 4, 'L-2231', date, 'REC-3358'));
    expect((pen.originBin, pen.sourceDoc, pen.reason), ('A-01-02', id, 'Error de piqueo'));
    expect(lines['p1']!.pendingIds, [pen.id]);
    final types = s().history.take(2).map((m) => m.type).toSet();
    expect(types, {'a-pendientes', 'auditoria-sobrante'});
    expect(s().history.firstWhere((m) => m.type == 'auditoria-sobrante').note, contains('etiqueta cambiada'));
    expect(s().lockedBins, isEmpty);
    expect(s().audits.first.status, AuditStatus.cerrada);
    expect(s().disponible('p1'), 52 - 4, reason: 'lo pendiente no cuenta como existencia');
  });

  test('un sobrante identificado con un pendiente recupera su lote y fecha', () {
    countA0102(p1: 16); // PEN: p1 × 4, lote L-2231
    final pen = s().openPending.single;
    final id = n().createAudit(bins: ['B-02-01']).id!; // sistema: p1 × 18
    n().startBinCount(id, 'B-02-01');
    n().addCount(id, 'B-02-01', 'MI-20565R15', 21);
    n().finishBinCount(id, 'B-02-01');
    n().submitRecount(id, 'B-02-01', {}, skip: true);
    expect(n().matchSurplusToPending(id, 'B-02-01', 'p1', 'PEN-999'), isNotNull);
    expect(n().matchSurplusToPending(id, 'B-02-01', 'p1', pen.id), isNull);
    n().setLineReason(id, 'B-02-01', 'p1', 'En otra canasta');
    expect(n().closeAudit(id), isNull);

    final found = s().pendingItems.firstWhere((p) => p.status == PendingStatus.encontrado);
    expect((found.qty, found.foundBin), (3, 'B-02-01'));
    expect(pen.qty, 1, reason: 'queda 1 unidad abierta');
    expect(pen.isOpen, isTrue);
    final back = s().inventory.firstWhere((r) => r.bin == 'B-02-01' && r.lot == 'L-2231');
    expect((back.qty, back.entryDate), (3, pen.entryDate));
    expect(qtyIn('p1', 'B-02-01'), 21);
    expect(s().history.first.type, 'pendiente-encontrado');
  });

  test('PENDIENTES: encontrado parcial en otra canasta y baja con motivo', () {
    countA0102(p1: 16);
    final pen = s().openPending.single;
    expect(n().resolvePendingFound(pen.id, 'C-01-01', 5), isNotNull);
    expect(n().resolvePendingFound(pen.id, 'Z-99', 1), isNotNull);
    expect(n().resolvePendingFound(pen.id, 'C-01-01', 2), isNull);
    final row = s().inventory.firstWhere((r) => r.bin == 'C-01-01' && r.productId == 'p1');
    expect((row.qty, row.lot, row.entryDate), (2, 'L-2231', pen.entryDate));
    expect(pen.qty, 2);

    expect(n().writeOffPending(pen.id, 2, kReasonOther), contains('nota'));
    expect(n().writeOffPending(pen.id, 2, 'Dañado', note: 'llanta cortada'), isNull);
    expect(s().openPending, isEmpty);
    expect(pen.status, PendingStatus.baja);
    expect(s().history.first.type, 'baja');
    expect(s().history.first.note, 'Dañado · llanta cortada');
    expect(n().writeOffPending(pen.id, 1, 'Dañado'), isNotNull, reason: 'ya está resuelto');
  });

  test('cerrar auditoría cancela lo no contado; cancelar desbloquea sin tocar inventario', () {
    final id = n().createAudit(bins: ['A-01-01', 'A-01-02']).id!;
    n().startBinCount(id, 'A-01-01');
    expect(n().closeAudit(id), contains('A-01-01'), reason: 'se está contando');
    expect(n().cancelAudit(id), isNull);
    expect(s().lockedBins, isEmpty);
    expect(qtyIn('p1', 'A-01-01'), 14);

    final id2 = n().createAudit(bins: ['A-01-01', 'A-01-02']).id!;
    n().startBinCount(id2, 'A-01-01');
    n().addCount(id2, 'A-01-01', 'MI-20565R15', 14);
    expect(n().finishBinCount(id2, 'A-01-01').recount, isEmpty);
    expect(n().closeAudit(id2), isNull);
    final a = s().audits.firstWhere((x) => x.id == id2);
    expect(a.status, AuditStatus.cerrada);
    expect(a.binOf('A-01-02')!.status, AuditBinStatus.cancelada);
    expect(a.binOf('A-01-01')!.lines.single.result, AuditResult.ok);
    expect(accuracyTotal(s().audits).lineAccuracy, 1);
  });

  test('transferir canasta completa conserva lote, recibo y fecha de cada fila', () {
    final before = s().inventory.where((r) => r.bin == 'A-03-01').map((r) => r.copy()).toList();
    expect(n().binTransferAll(from: 'A-03-01', to: 'A-03-01'), isNotNull);
    expect(n().binTransferAll(from: 'A-03-01', to: 'C-03-02', obs: 'reorganizar'), isNull);
    expect(s().inventory.where((r) => r.bin == 'A-03-01'), isEmpty);
    for (final b in before) {
      final moved = s().inventory.firstWhere((r) => r.id == b.id);
      expect((moved.bin, moved.lot, moved.receipt, moved.entryDate, moved.qty), ('C-03-02', b.lot, b.receipt, b.entryDate, b.qty));
    }
    expect(s().binTransfers.first.obs, contains('Canasta completa A-03-01 → C-03-02'));
    expect(s().history.first.type, 'transfer-bin');
    expect(n().binTransferAll(from: 'A-03-01', to: 'C-03-02'), isNotNull, reason: 'origen vacío');
  });

  test('data.json guarda auditorías y pendientes; un data.json anterior sin ellos se lee', () {
    final id = countA0102(p1: 16, close: false);
    n().setLineReason(id, 'A-01-02', 'p1', 'Perdido');
    final again = AppState.fromDataJson(jsonDecode(jsonEncode(s().toDataJson())) as Map);
    expect(jsonEncode(again.toDataJson()), jsonEncode(s().toDataJson()));
    expect(again.lockedBins, {'A-01-02'});
    expect(again.audits.single.bins.single.lines.single.reason, 'Perdido');

    n().closeAuditBin(id, 'A-01-02');
    final j = jsonDecode(jsonEncode(s().toDataJson())) as Map;
    expect(AppState.fromDataJson(j).openPending.single.lot, 'L-2231');

    j.remove('audits');
    j.remove('pendingItems');
    (j['seq'] as Map)
      ..remove('audit')
      ..remove('pending');
    final old = AppState.fromDataJson(j);
    expect(old.audits, isEmpty);
    expect(old.pendingItems, isEmpty);
    expect((old.auditSeq, old.pendingSeq), (1, 1));
  });

  group('roles y permisos', () {
    test('Auditor: solo Dashboard y Auditoría (contar); no administra', () {
      expect(n().login('5555'), isNull);
      expect(s().currentUser!.role, 'Auditor');
      expect(AppView.values.where((v) => s().allowed(v)), [AppView.dashboard, AppView.audit, AppView.about]);
      expect(s().canManageAudits, isFalse);
    });

    test('auditoría asignada a otro: el auditor no la ve ni la puede contar', () {
      final id = n().createAudit(bins: ['A-01-01'], assignedTo: 'u2').id!;
      n().login('5555');
      expect(s().auditsToCount, isEmpty);
      expect(n().startBinCount(id, 'A-01-01'), contains('María Rivera'));
    });

    test('el conteo es de quien escaneó la canasta', () {
      final id = n().createAudit(bins: ['A-01-01']).id!;
      n().login('5555');
      n().startBinCount(id, 'A-01-01');
      n().logout();
      n().login('2222');
      expect(n().startBinCount(id, 'A-01-01'), contains('A. Torres'));
      expect(n().addCount(id, 'A-01-01', 'MI-20565R15', 1), isNotNull);
    });

    test('users.json anterior (sin permsVersion): admin y supervisor reciben las áreas de auditoría', () {
      final old = jsonEncode({
        'version': 1,
        'users': [
          {'id': 'u1', 'name': 'Admin', 'email': '', 'role': 'Administrador', 'active': true,
            'perms': ['dashboard', 'users']},
          {'id': 'u2', 'name': 'Sup', 'email': '', 'role': 'Supervisor de almacén', 'active': true,
            'perms': ['dashboard', 'picking']},
          {'id': 'u3', 'name': 'Pic', 'email': '', 'role': 'Piqueador', 'active': true, 'perms': ['picking']},
        ],
        'rolePresets': {
          'Supervisor de almacén': ['dashboard', 'picking'],
        },
      });
      final d = UserStoreData.parse(old);
      final u = {for (final x in d.users) x.id: x};
      expect(u['u1']!.can(Area.audit) && u['u1']!.can(Area.auditManage), isTrue);
      expect(u['u2']!.can(Area.auditManage), isTrue);
      expect(u['u2']!.can(Area.receiving), isFalse, reason: 'lo demás no cambia');
      expect(u['u3']!.can(Area.audit), isFalse);
      expect(d.rolePresets['Supervisor de almacén']![Area.audit], isTrue);

      // Ya guardado con la versión nueva: se respeta lo elegido.
      final saved = UserStoreData.encode(users: d.users..first.perms[Area.audit] = false, rolePresets: d.rolePresets, autoLogoutMinutes: 10);
      expect(UserStoreData.parse(saved).users.first.can(Area.audit), isFalse);
    });
  });
}
