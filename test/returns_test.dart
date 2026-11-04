import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rm_core/api/rm_api.dart';
import 'package:rm_core/auth/user_store.dart';
import 'package:rm_core/models/app_user.dart';
import 'package:rm_core/models/pick_session.dart';
import 'package:rm_core/models/receipt.dart';
import 'package:rm_core/models/return_entry.dart';
import 'package:rm_core/remote/commands.dart';
import 'package:rm_core/state/app_state.dart';
import 'package:rm_core/state/pick_engine.dart';
import 'package:rm_core/sync/dispatch_ledger.dart';
import 'package:rm_core/sync/sync_service.dart';
import 'package:rm_core/sync/sync_settings.dart';
import 'package:rm_core/util/clock.dart';

import 'fake_rm_api.dart';

/// Fecha anterior al "hoy" de demostración (15 sep 2026).
final _d = DateTime(2026, 9, 10, 11);

void main() {
  late ProviderContainer c;
  AppState s() => c.read(appProvider);
  AppNotifier n() => c.read(appProvider.notifier);
  DispatchLedger ledger() => c.read(ledgerProvider);

  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  RmReturnLine ret(
    String doc,
    double qty, {
    String code = 'MI-20565R15',
    int type = 70,
    String lineId = '',
    String original = '',
    DateTime? originalDate,
  }) => rline(doc, code, qty, type: type, lineId: lineId, date: _d, original: original, originalDate: originalDate);

  ReturnEntry only() => s().returns.single;

  group('fuente provisional (SalesInvoicesByDate)', () {
    test('solo 70/71; cantidad en valor absoluto; VP se cuenta desde su documento', () {
      expect(RmReturnLine.fromInvoiceLine(iline('F1', 'X', 2)), isNull, reason: 'venta normal');
      expect(
        RmReturnLine.fromInvoiceLine(iline('F1', 'X', 2, voided: 1)),
        isNull,
        reason: 'el VoidParcial de la factura original no es una devolución (sin doble conteo)',
      );
      expect(RmReturnLine.fromInvoiceLine(iline('V78', 'X', -2, transaction: 70))!.quantity, 2);
      expect(RmReturnLine.fromInvoiceLine(iline('V79', 'X', 3, transaction: 70))!.quantity, 3);
      final vp = RmReturnLine.fromInvoiceLine(iline('VP5', 'X', 0, transaction: 71, voided: 1, original: 'F9'))!;
      expect((vp.quantity, vp.returnType, vp.originalInvoice), (1.0, 71, 'F9'));
    });

    test('sin SalesReturnsByDate se usan las facturas; con él, el endpoint nuevo', () async {
      final api = FakeRmApi(
        invoices: [
          iline('F1', 'MI-20565R15', 2),
          iline('V78', 'MI-20565R15', -2, transaction: 70, date: _d),
        ],
      );
      c.dispose();
      c = ProviderContainer(overrides: [rmApiFactoryProvider.overrideWithValue((_) => api)]);
      n().updateStore('s0', apiUrl: 'http://srv');
      var (lines, provisional) = await n().fetchReturns('s0', _d, _d);
      expect((lines.length, lines.single.returnNumber, provisional), (1, 'V78', true));

      api.returns = [ret('V80', 1)];
      (lines, provisional) = await n().fetchReturns('s0', _d, _d);
      expect((lines.single.returnNumber, provisional), ('V80', false));
    });
  });

  group('importar', () {
    test('queda por revisar, sin tocar inventario; volver a importar no duplica', () {
      final before = s().total('p1');
      final r = n().importReturns('s0', [ret('V78', 2), ret('V78', 1, code: 'GY-19565R15')]);
      expect((r.created, r.duplicates), (2, 0));
      expect(s().openReturns.length, 2);
      expect(s().total('p1'), before, reason: 'nada entra hasta aceptarla');
      expect(s().receipts.any((x) => x.isReturn), isFalse);

      final again = n().importReturns('s0', [ret('V78', 2), ret('V78', 1, code: 'GY-19565R15')]);
      expect((again.created, again.duplicates), (0, 2));
      expect(s().returns.length, 2);
    });

    test('cambio de fuente con otro LineID: se empareja por documento, artículo y cantidad', () {
      n().importReturns('s0', [ret('V78', 2, lineId: '991')]);
      final r = n().importReturns('s0', [ret('V78', 2, lineId: 'V78-1'), ret('V78', 2, lineId: 'V78-2')]);
      expect((r.created, r.duplicates), (1, 1), reason: 'la segunda línea igual sí es nueva');
      expect(s().returns.length, 2);
    });

    test('omite servicios, combustible, datos incompletos y cantidades que redondean a 0', () {
      final r = n().importReturns('s0', [
        rline('V1', 'SRV', 1, service: true, date: _d),
        rline('V2', 'GAS', 5, fuel: true, date: _d),
        rline('V3', '', 1, date: _d),
        ret('V4', 0.3),
        ret('V5', 1.6),
      ]);
      expect((r.created, r.skipped, r.fractional), (1, 4, 1));
      expect(only().qty, 2);
    });

    test('fecha de entrada: la de la venta original (API, luego la factura en la app); si no, la del documento', () {
      final orig = DateTime(2026, 8, 1);
      n().importReturns('s0', [ret('V1', 1, original: 'F1', originalDate: orig)]);
      expect((s().returns.first.entryDate, s().returns.first.originalDate), (orig, orig));

      n().importInvoices('s0', [iline('F2', 'MI-20565R15', 3, date: DateTime(2026, 8, 20))]);
      n().importReturns('s0', [ret('V2', 1, original: 'F2')]);
      expect(s().returns.first.entryDate, DateTime(2026, 8, 20));

      n().importReturns('s0', [ret('V3', 1, original: 'F404')]);
      expect((s().returns.first.entryDate, s().returns.first.originalDate), (_d, null));
    });

    test('despacho según el libro: despachada, no salió del almacén u origen desconocido', () {
      final now = DateTime(2026, 9, 1);
      final e = ledger().recordInvoice('s0', 'F1', 'FAC-F1', now);
      ledger().addPicked(e, 'mi-20565r15', 2);
      ledger().recordInvoice('s0', 'F2', 'FAC-F2', now);
      // Factura enlazada a una orden: lo piqueado está bajo la orden.
      ledger().recordInvoice('s0', 'F3', 'ORD-7001', now);
      ledger().addPicked(ledger().recordOrder('s0', '7001', 'ORD-7001', now), 'mi-20565r15', 4);

      n().importReturns('s0', [
        ret('V1', 2, original: 'F1'),
        ret('V2', 1, original: 'F2'),
        ret('V3', 1, original: 'F3'),
        ret('V4', 1, original: 'F999'),
        ret('V5', 1),
      ]);
      ReturnEntry byDoc(String d) => s().returns.firstWhere((r) => r.docNumber == d);
      expect((byDoc('V1').shipped, byDoc('V1').notShipped), (2, false));
      expect((byDoc('V2').shipped, byDoc('V2').notShipped), (0, true));
      expect(byDoc('V3').shipped, 4);
      expect(byDoc('V4').shipped, isNull);
      expect(byDoc('V4').shipNote, contains('no pasó por el almacén'));
      expect(byDoc('V5').shipNote, contains('no indica'));
    });
  });

  group('revisar', () {
    test('aceptar crea el recibo DEV con la fecha elegida; al ubicar, fila propia y movimiento devolución', () {
      n().importReturns('s0', [ret('V78', 3, original: 'F1')]);
      final id = only().id;
      final entry = DateTime(2026, 8, 3);
      expect(n().acceptReturn(id, 3, kToday.add(const Duration(days: 1))), contains('futura'));
      expect(n().acceptReturn(id, 4, entry), isNotNull);
      expect(n().acceptReturn(id, 3, entry, condition: 'Caja abierta'), isNull);
      expect(n().acceptReturn(id, 3, entry), contains('ya se revisó'));

      final rec = s().receipts.firstWhere((r) => r.id == id);
      expect((rec.kind, rec.date, rec.refDoc, rec.items.single.qtyReceived), (ReceiptKind.devolucion, entry, 'F1', 3));
      expect((only().status, only().receiptId, only().reason), (ReturnStatus.aceptada, id, 'Caja abierta'));

      // A-01-02 ya tiene p1 (lote L-2231): la devolución no se mezcla con esa fila.
      final rowsBefore = s().inventory.length;
      expect(n().allocateReceiptItem(id, 'p1', [('A-01-02', 2), ('B-02-01', 1)]), isNull);
      expect(s().inventory.length, rowsBefore + 2);
      final mine = s().inventory.where((r) => r.receipt == id).toList();
      expect(mine.every((r) => r.entryDate == entry), isTrue);
      expect(s().inventory.firstWhere((r) => r.lot == 'L-2231').qty, 20);
      expect(s().history.first.type, 'devolucion');
      expect(s().history.first.note, contains('F1'));
      expect(s().pendingReceipts.any((r) => r.id == id), isFalse);
    });

    test('aceptar menos: el resto queda descartado («no llegó»)', () {
      n().importReturns('s0', [ret('V78', 5)]);
      final id = only().id;
      expect(n().acceptReturn(id, 3, _d), isNull);
      final rest = s().returns.firstWhere((r) => r.id != id);
      expect((rest.qty, rest.status, rest.reason), (2, ReturnStatus.descartada, kReturnShortReason));
      expect(s().receipts.firstWhere((r) => r.id == id).items.single.qtyReceived, 3);
      // El contenido original (5) sigue reconocido si cambia el LineID.
      expect(n().importReturns('s0', [ret('V78', 5, lineId: 'otro')]).created, 0);
    });

    test('dar de baja y descartar no crean inventario; en parte, el resto sigue por revisar', () {
      n().importReturns('s0', [ret('V78', 4)]);
      final id = only().id;
      final units = s().total('p1');
      expect(n().writeOffReturn(id, 1, ''), isNotNull);
      expect(n().writeOffReturn(id, 1, 'Otro'), contains('nota'));
      expect(n().writeOffReturn(id, 1, 'Dañada', note: 'llanta cortada'), isNull);
      expect(s().history.first.type, 'baja');
      expect(n().discardReturn(id, 3, 'No llegó al almacén'), isNull);
      expect(s().openReturns, isEmpty);
      expect(s().total('p1'), units);
      expect(s().receipts.any((r) => r.isReturn), isFalse);
      expect(s().returns.map((r) => r.status).toSet(), {ReturnStatus.baja, ReturnStatus.descartada});
    });

    test('aceptar varias omite las que no salieron del almacén', () {
      ledger().recordInvoice('s0', 'F2', 'FAC-F2', DateTime(2026, 9, 1));
      n().importReturns('s0', [ret('V1', 1), ret('V2', 1, original: 'F2')]);
      final r = n().acceptReturns([for (final e in s().returns) e.id]);
      expect((r.accepted, r.skipped), (1, 1));
      expect(s().openReturns.single.docNumber, 'V2');
    });

    test('una canasta en auditoría no recibe la devolución', () {
      n().importReturns('s0', [ret('V1', 1)]);
      final id = only().id;
      n().acceptReturn(id, 1, _d);
      final aud = n().createAudit(bins: ['A-01-02']).id!;
      n().startBinCount(aud, 'A-01-02');
      expect(n().allocateReceiptItem(id, 'p1', [('A-01-02', 1)]), contains('auditoría'));
    });
  });

  group('no encontrado del piqueo', () {
    test('sale en la bandeja; las acciones de devoluciones solo tocan faltantes del piqueo', () {
      final pick = n().resolvePickMissingFound;
      n().suggestSingle('p1', 2, 'DOC-1');
      final key = s().singleKey;
      final st = s().pickSessions[key]!.steps.first;
      expect(n().stepMissingHere(key, st.id), isNull);
      for (final x in s().pickSessions[key]!.steps.where((x) => x.status == StepStatus.pending)) {
        n().stepPicked(key, x.id);
      }
      expect(n().confirmSingle(), isNotNull);
      final pen = s().pickMissingOpen.single;
      expect(pen.reason, kPickMissingReason);
      expect(s().returnsToReview, 1);
      expect(pick(pen.id, pen.originBin, pen.qty), isNull);
      expect(s().pickMissingOpen, isEmpty);
    });
  });

  group('permisos', () {
    test('users.json v2: admin y supervisor reciben «revisar devoluciones»; los demás no', () {
      final v2 = jsonEncode({
        'permsVersion': 2,
        'users': [
          {
            'id': 'u1',
            'name': 'A',
            'email': '',
            'role': 'Administrador',
            'active': true,
            'perms': ['dashboard', 'users'],
            'permsVersion': 2,
          },
          {
            'id': 'u2',
            'name': 'S',
            'email': '',
            'role': 'Supervisor de almacén',
            'active': true,
            'perms': ['audit'],
            'permsVersion': 2,
          },
          {
            'id': 'u3',
            'name': 'P',
            'email': '',
            'role': 'Piqueador',
            'active': true,
            'perms': ['picking'],
            'permsVersion': 2,
          },
        ],
        'rolePresets': {
          'Supervisor de almacén': ['dashboard'],
        },
      });
      final d = UserStoreData.parse(v2);
      final u = {for (final x in d.users) x.id: x};
      expect(u['u1']!.can(Area.returns), isTrue);
      expect(u['u2']!.can(Area.returns), isTrue);
      expect(u['u2']!.can(Area.auditManage), isFalse, reason: 'v2 ya traía auditoría: se respeta');
      expect(u['u3']!.can(Area.returns), isFalse);
      expect(d.rolePresets['Supervisor de almacén']![Area.returns], isTrue);
      // v1 recibe ambas tandas.
      expect(migratePerms({for (final a in Area.values) a: false}, 'Administrador', null)[Area.returns], isTrue);
      expect(migratePerms({for (final a in Area.values) a: false}, 'Administrador', null)[Area.audit], isTrue);
      expect(migratePerms({for (final a in Area.values) a: false}, 'Administrador', 3)[Area.returns], isFalse);
    });

    test('las acciones remotas piden el permiso correcto', () {
      AppUser user(Set<Area> on) => AppUser(
        id: 'x',
        name: 'X',
        email: '',
        role: 'Piqueador',
        active: true,
        perms: {for (final a in Area.values) a: on.contains(a)},
      );
      final returnsOnly = user({Area.returns});
      final manager = user({Area.auditManage});
      for (final cmd in ['acceptReturn', 'acceptReturns', 'writeOffReturn', 'discardReturn']) {
        expect(kRemoteCommands[cmd]!.can(returnsOnly, {}), isTrue, reason: cmd);
        expect(kRemoteCommands[cmd]!.can(manager, {}), isFalse, reason: cmd);
      }
      expect(kRemoteCommands['resolvePickMissingFound']!.can(returnsOnly, {}), isTrue);
      expect(kRemoteCommands['resolvePickMissingFound']!.can(manager, {}), isTrue);
      expect(
        kRemoteCommands['resolvePendingFound']!.can(returnsOnly, {}),
        isFalse,
        reason: 'quien solo revisa devoluciones no resuelve pendientes de auditoría',
      );
    });

    test('resolver un pendiente que no viene del piqueo se rechaza', () {
      final id = n().createAudit(bins: ['A-01-02']).id!;
      n().startBinCount(id, 'A-01-02');
      n().addCount(id, 'A-01-02', 'MI-20565R15', 16);
      final r = n().finishBinCount(id, 'A-01-02');
      if (r.recount.isNotEmpty) n().submitRecount(id, 'A-01-02', {}, skip: true);
      n().setLineReason(id, 'A-01-02', 'p1', 'Error de piqueo');
      expect(n().closeAuditBin(id, 'A-01-02'), isNull);
      final pen = s().openPending.single;
      expect(n().resolvePickMissingFound(pen.id, 'A-01-02', 1), contains('no viene del piqueo'));
      expect(n().writeOffPickMissing(pen.id, 1, 'Dañada'), contains('no viene del piqueo'));
      expect(s().pickMissingOpen, isEmpty);
    });

    test('quien solo revisa devoluciones entra a Auditoría', () {
      final u = s().users.firstWhere((x) => x.id == 'u3');
      u.perms = {for (final a in Area.values) a: a == Area.returns};
      s().currentUserId = 'u3';
      expect(s().allowed(AppView.audit), isTrue);
      expect((s().canReviewReturns, s().canManageAudits, s().canCountAudits), (true, false, false));
    });
  });

  group('datos', () {
    test('data.json anterior (sin devoluciones) carga; ida y vuelta conserva todo', () {
      final j = s().toDataJson()
        ..remove('returns')
        ..remove('importedReturnIds');
      (j['seq'] as Map).remove('return');
      final old = AppState.fromDataJson(jsonDecode(jsonEncode(j)) as Map);
      expect(old.returns, isEmpty);
      expect(old.importedReturnIds, isEmpty);
      expect(old.returnSeq, 1001);

      n().importReturns('s0', [ret('V1', 3, original: 'F1', originalDate: DateTime(2026, 8, 1))]);
      n().acceptReturn(only().id, 2, DateTime(2026, 8, 2), note: 'ok');
      final back = AppState.fromDataJson(jsonDecode(jsonEncode(s().toDataJson())) as Map);
      expect(jsonEncode(back.toDataJson()), jsonEncode(s().toDataJson()));
      expect(back.receipts.firstWhere((r) => r.isReturn).refDoc, 'F1');
    });
  });

  group('sincronización', () {
    late Directory tmp;
    late FakeRmApi api;
    var now = DateTime(2026, 10, 13, 16);

    ProviderContainer boot() {
      final cont = ProviderContainer(
        overrides: [
          userDataDirProvider.overrideWithValue(tmp),
          clockProvider.overrideWithValue(() => now),
          rmApiFactoryProvider.overrideWithValue((_) => api),
        ],
      );
      cont.read(appProvider.notifier).updateStore('s0', apiUrl: 'http://srv');
      return cont;
    }

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('piqueo_returns');
      now = DateTime(2026, 10, 13, 16);
      api = FakeRmApi(returns: [ret('V78', 2)]);
      c.dispose();
      c = boot();
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    SyncService sync() => c.read(syncProvider.notifier);

    test('apagado por defecto: no pide devoluciones', () async {
      final parts = await sync().syncNow();
      expect(parts.any((p) => p.label == 'Devoluciones'), isFalse);
      expect(api.lastReturnsFrom, isNull);
      expect(s().returns, isEmpty);
    });

    test('primera vez 30 días; después, desde la última detección − 1 día; sobrevive al reinicio', () async {
      sync().setReturnsEnabled(true);
      var parts = await sync().syncNow();
      final part = parts.firstWhere((p) => p.label == 'Devoluciones');
      expect((part.ok, part.newItems), (true, 1));
      expect(api.lastReturnsFrom, now.subtract(const Duration(days: 30)));
      expect(s().openReturns.single.docNumber, 'V78');

      final first = now;
      now = now.add(const Duration(days: 3));
      c.dispose();
      c = boot();
      expect(c.read(syncProvider).settings.returnsEnabled, isTrue);
      parts = await sync().syncNow();
      expect(api.lastReturnsFrom, first.subtract(const Duration(days: 1)));
      expect(parts.firstWhere((p) => p.label == 'Devoluciones').ok, isTrue);
    });

    test('si falla, no avanza la fecha (se vuelve a pedir el mismo rango)', () async {
      sync().setReturnsEnabled(true);
      sync().setReturnsFirstRunDays(10);
      api.returns = null;
      api.invoicesError = RmApiException('caída');
      final parts = await sync().syncNow();
      expect(parts.firstWhere((p) => p.label == 'Devoluciones').ok, isFalse);
      expect(c.read(syncProvider).settings.returnsLastSync, isNull);
      expect(SyncSettings.load(File('${tmp.path}\\settings.json')).returnsFirstRunDays, 10);
    });
  });
}
