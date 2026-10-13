import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piqueo_fifo_centeno/data/seed.dart';
import 'package:piqueo_fifo_centeno/models/app_user.dart';
import 'package:piqueo_fifo_centeno/state/app_state.dart';
import 'package:piqueo_fifo_centeno/util/clock.dart';

void main() {
  late ProviderContainer c;
  AppState s() => c.read(appProvider);
  AppNotifier n() => c.read(appProvider.notifier);

  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  test('dashboard: totales y estancados', () {
    expect(s().products.length, 10);
    expect(s().total('p1'), 58);
    expect(s().central('p1'), 52);
    expect(s().disponible('p1'), 52);
    final stale = s().staleRows;
    expect(stale.map((r) => (r.productId, r.bin, ageDays(r.entryDate))).toList(), [
      ('p10', 'B-03-03', 300),
      ('p7', 'C-01-02', 250),
      ('p8', 'A-03-03', 210),
      ('p5', 'C-02-01', 195),
    ]);
  });

  test('transferencia entre bins conserva fecha, recibo y lote', () {
    final src = s().inventory.firstWhere((r) => r.productId == 'p1' && r.bin == 'A-01-02');
    final err = n().binTransfer(productId: 'p1', srcRowId: src.id, destBin: 'C-01-01', qty: 10, obs: 'demo');
    expect(err, isNull);
    final dest = s().inventory.firstWhere((r) => r.productId == 'p1' && r.bin == 'C-01-01');
    expect(dest.qty, 10);
    expect(dest.entryDate, src.entryDate);
    expect(dest.receipt, 'REC-3358');
    expect(dest.lot, 'L-2231');
    expect(src.qty, 10);
    expect(s().history.first.type, 'transfer-bin');
    expect(s().history.first.doc, 'TB-2202');
  });

  test('transferencia entre bins: validaciones', () {
    final src = s().inventory.firstWhere((r) => r.productId == 'p1' && r.bin == 'A-01-02');
    expect(n().binTransfer(productId: 'p1', srcRowId: null, destBin: 'C-01-01', qty: 1), isNotNull);
    expect(n().binTransfer(productId: 'p1', srcRowId: src.id, destBin: 'C-01-01', qty: 99), isNotNull);
    expect(n().binTransfer(productId: 'p1', srcRowId: src.id, destBin: 'A-01-02', qty: 1), isNotNull);
    expect(n().binTransfer(productId: 'p1', srcRowId: src.id, destBin: 'C-01-01', qty: 0), isNotNull);
  });

  test('transferencia entre tiendas: envío queda pendiente hasta confirmar', () {
    final r = n().storeTransferSend(productId: 'p1', fromStore: 'Sucursal Ponce', toStore: kCentral, qty: 8);
    expect(r.error, isNotNull); // Ponce solo tiene 6
    final ok = n().storeTransferSend(productId: 'p1', fromStore: 'Sucursal Ponce', toStore: kCentral, qty: 6);
    expect(ok.error, isNull);
    expect(ok.id, 'TS-0089');
    expect(s().storeQty('p1', 'Sucursal Ponce'), 0);
    expect(s().central('p1'), 52); // aún no disponible en destino
    expect(s().history.first.type, 'transfer-store-out');
    n().storeTransferConfirm(ok.id!);
    expect(s().central('p1'), 58);
    final row = s().inventory.firstWhere((x) => x.receipt == 'TS-0089');
    expect(row.bin, 'AL-RX');
    expect(row.entryDate, kToday);
    expect(s().storeTransfers.first.status, 'recibido');
    expect(s().history.first.type, 'transfer-store-in');
  });

  test('bin de recepción', () {
    expect(receiveBinFor('Sucursal Bayamón'), 'BA-RX');
    expect(receiveBinFor('Sucursal Río Piedras'), 'RI-RX');
    expect(receiveBinFor('Sucursal Ponce'), 'PO-RX');
    expect(receiveBinFor(kCentral), 'AL-RX');
  });

  test('ubicar recibo REC-3430 en 25/25/50', () {
    expect(n().allocateReceiptItem('REC-3430', 'p1', [('C-01-01', 60), ('C-01-02', 50)]), isNotNull);
    final err = n().allocateReceiptItem(
        'REC-3430', 'p1', [('C-01-01', 25), ('C-01-02', 25), ('C-02-01', 50)]);
    expect(err, isNull);
    expect(s().pendingReceipts.any((r) => r.id == 'REC-3430'), isFalse);
    expect(s().history.take(3).every((m) => m.type == 'entrada' && m.doc == 'REC-3430'), isTrue);
    final lots = s().inventory.where((r) => r.receipt == 'REC-3430').map((r) => r.lot).toList();
    expect(lots, ['L-2280', 'L-2281', 'L-2282']);
  });

  test('orden OV-10501 parcial con faltante declarado', () {
    n().calcOrderRoute('OV-10501');
    final k1 = orderSessionKey('OV-10501', 'p1');
    final k3 = orderSessionKey('OV-10501', 'p3');
    final k6 = orderSessionKey('OV-10501', 'p6');
    for (final k in [k1, k3]) {
      for (final st in [...s().pickSessions[k]!.steps]) {
        n().stepPicked(k, st.id);
      }
    }
    final s6 = s().pickSessions[k6]!;
    n().stepPicked(k6, s6.steps[0].id);
    n().stepMissingHere(k6, s6.steps[1].id);
    expect(s().pickSessions[k6]!.shortfall!.take, 3);
    expect(s().orderCanConfirm(s().orders.firstWhere((o) => o.id == 'OV-10501')), isFalse);
    n().declareShortfall(k6);
    final partial = n().confirmOrder('OV-10501');
    expect(partial, isTrue);
    final o = s().orders.firstWhere((o) => o.id == 'OV-10501');
    expect(o.status, 'parcial');
    final types = s().history.map((m) => m.type).toSet();
    expect(types.containsAll({'piqueo', 'discrepancia', 'no-encontrado'}), isTrue);
  });

  test('simulación RBAC: Juan Nieves (Piqueador)', () {
    n().navigate(AppView.transfers);
    n().startSimulation('u3');
    expect(s().currentView, AppView.dashboard);
    final unlocked = AppView.values.where((v) => s().allowed(v)).toList();
    expect(unlocked, [AppView.dashboard, AppView.orders, AppView.picking, AppView.about]);
    n().navigate(AppView.picking);
    n().setPerm('u3', Area.picking, false);
    expect(s().currentView, AppView.dashboard);
    n().exitSimulation();
    expect(AppView.values.every((v) => s().allowed(v)), isTrue);
  });
}
