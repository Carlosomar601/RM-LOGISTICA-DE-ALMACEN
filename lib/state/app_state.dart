import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/seed.dart';
import '../models/app_user.dart';
import '../models/inv_row.dart';
import '../models/movement.dart';
import '../models/order.dart';
import '../models/pick_session.dart';
import '../models/product.dart';
import '../models/receipt.dart';
import '../models/store_transfer.dart';
import '../util/clock.dart';
import '../util/format.dart';
import 'pick_engine.dart';

enum AppView { dashboard, receiving, orders, picking, transfers, history, users, about }

extension AppViewX on AppView {
  /// Área de permisos; null = siempre accesible.
  Area? get area => switch (this) {
        AppView.dashboard => Area.dashboard,
        AppView.receiving => Area.receiving,
        AppView.orders => Area.orders,
        AppView.picking => Area.picking,
        AppView.transfers => Area.transfers,
        AppView.history => Area.history,
        AppView.users => Area.users,
        AppView.about => null,
      };

  String get label => switch (this) {
        AppView.dashboard => 'Dashboard',
        AppView.receiving => 'Recibido sin ubicar',
        AppView.orders => 'Órdenes entrantes',
        AppView.picking => 'Piqueo FIFO',
        AppView.transfers => 'Transferencias',
        AppView.history => 'Historial',
        AppView.users => 'Usuarios',
        AppView.about => 'Resumen del proyecto',
      };
}

class StoreTransferPrefill {
  const StoreTransferPrefill({
    required this.seq,
    required this.productId,
    required this.fromStore,
    required this.toStore,
    required this.qty,
  });
  final int seq;
  final String productId;
  final String fromStore;
  final String toStore;
  final int qty;
}

const kSingleSessionKey = '__single__';

String orderSessionKey(String orderId, String productId) => '$orderId$productId';

class AppState {
  AppState({
    required this.products,
    required this.inventory,
    required this.orders,
    required this.receipts,
    required this.history,
    required this.storeTransfers,
    required this.binTransfers,
    required this.users,
    required this.pickSessions,
    this.currentView = AppView.dashboard,
    this.simulatedUserId,
    this.transferPrefill,
    this.orderSeq = 10504,
    this.receiptSeq = 3433,
    this.lotSeq = 2280,
    this.tbSeq = 2202,
    this.tsSeq = 89,
    this.movementSeq = 1009,
    this.invSeq = kSeedInvCount + 1,
    this.stepSeq = 1,
    this.userSeq = 5,
    this.prefillSeq = 1,
  });

  factory AppState.seed() => AppState(
        products: seedProducts(),
        inventory: seedInventory(),
        orders: seedOrders(),
        receipts: seedReceipts(),
        history: seedHistory(),
        storeTransfers: seedStoreTransfers(),
        binTransfers: seedBinTransfers(),
        users: seedUsers(),
        pickSessions: {},
      );

  final List<Product> products;
  final List<InvRow> inventory;
  final List<Order> orders;
  final List<Receipt> receipts;
  final List<Movement> history;
  final List<StoreTransfer> storeTransfers;
  final List<BinTransfer> binTransfers;
  final List<AppUser> users;
  final Map<String, PickSession> pickSessions;
  AppView currentView;
  String? simulatedUserId;
  StoreTransferPrefill? transferPrefill;
  int orderSeq, receiptSeq, lotSeq, tbSeq, tsSeq, movementSeq, invSeq, stepSeq, userSeq, prefillSeq;

  /// Copia superficial: nueva identidad para notificar a Riverpod.
  AppState clone() => AppState(
        products: products,
        inventory: inventory,
        orders: orders,
        receipts: receipts,
        history: history,
        storeTransfers: storeTransfers,
        binTransfers: binTransfers,
        users: users,
        pickSessions: pickSessions,
        currentView: currentView,
        simulatedUserId: simulatedUserId,
        transferPrefill: transferPrefill,
        orderSeq: orderSeq,
        receiptSeq: receiptSeq,
        lotSeq: lotSeq,
        tbSeq: tbSeq,
        tsSeq: tsSeq,
        movementSeq: movementSeq,
        invSeq: invSeq,
        stepSeq: stepSeq,
        userSeq: userSeq,
        prefillSeq: prefillSeq,
      );

  // ---------- Selectores ----------

  Product product(String id) => products.firstWhere((p) => p.id == id);

  List<InvRow> rowsOf(String productId) =>
      inventory.where((r) => r.productId == productId && r.qty > 0).toList();

  List<InvRow> fifoRowsOf(String productId) => fifoSorted(rowsOf(productId));

  List<InvRow> centralFifoRowsOf(String productId) =>
      fifoSorted(rowsOf(productId).where((r) => r.store == kCentral));

  int total(String productId) => rowsOf(productId).fold(0, (a, r) => a + r.qty);

  int central(String productId) => storeQty(productId, kCentral);

  int storeQty(String productId, String store) =>
      rowsOf(productId).where((r) => r.store == store).fold(0, (a, r) => a + r.qty);

  int disponible(String productId) => total(productId) - product(productId).committed;

  int get totalUnits => inventory.where((r) => r.qty > 0).fold(0, (a, r) => a + r.qty);

  int get totalCommitted => products.fold(0, (a, p) => a + p.committed);

  int get ageAlerts =>
      inventory.where((r) => r.qty > 0 && ageDays(r.entryDate) >= kAgeAlertDays).length;

  List<InvRow> get staleRows => fifoSorted(
      inventory.where((r) => r.qty > 0 && ageDays(r.entryDate) >= kStaleDays));

  List<Receipt> get pendingReceipts => receipts.where((r) => r.isPending).toList();

  List<Order> get openOrders => orders.where((o) => o.isOpen).toList();

  List<Order> get completedOrders => orders.where((o) => !o.isOpen).toList();

  AppUser? get simulatedUser =>
      simulatedUserId == null ? null : users.firstWhereOrNull((u) => u.id == simulatedUserId);

  bool allowed(AppView v) {
    final u = simulatedUser;
    final a = v.area;
    if (u == null || a == null) return true;
    return u.can(a);
  }

  AppView firstAllowed() =>
      AppView.values.firstWhere((v) => v != AppView.about && allowed(v), orElse: () => AppView.about);

  bool orderCanConfirm(Order o) {
    final items = o.items.where((i) => i.remaining > 0).toList();
    if (items.isEmpty) return false;
    for (final i in items) {
      final s = pickSessions[orderSessionKey(o.id, i.productId)];
      if (s == null || !sessionCanConfirm(s)) return false;
    }
    return true;
  }

  bool orderHasRoute(Order o) => o.items
      .where((i) => i.remaining > 0)
      .any((i) => pickSessions.containsKey(orderSessionKey(o.id, i.productId)));
}

/// Bin de recepción en la tienda destino: 2 primeras letras de la palabra
/// distintiva del nombre + "-RX" (p. ej. "Sucursal Bayamón" → "BA-RX").
String receiveBinFor(String store) {
  final name = store.startsWith('Sucursal ') ? store.substring('Sucursal '.length) : store;
  final word = stripAccents(name.split(' ').first).toUpperCase();
  return '${word.length >= 2 ? word.substring(0, 2) : word}-RX';
}

final appProvider = NotifierProvider<AppNotifier, AppState>(AppNotifier.new);

class AppNotifier extends Notifier<AppState> {
  AppNotifier({Random? rng}) : _rng = rng ?? Random();

  final Random _rng;

  @override
  AppState build() => AppState.seed();

  void _emit() => state = state.clone();

  String _mvId() => 'MV-${state.movementSeq++}';
  String _stepId() => 'st-${state.stepSeq++}';
  String _invId() => 'inv-${state.invSeq++}';

  void _log(Movement m) => state.history.insert(0, m);

  void _logAll(List<Movement> ms) {
    for (final m in ms) {
      _log(m);
    }
  }

  Movement _mv(String type, String productId, int qty, String doc, String from, String to) =>
      Movement(
        id: _mvId(),
        type: type,
        productId: productId,
        qty: qty,
        doc: doc,
        user: kCurrentUser,
        dateTime: kToday,
        from: from,
        to: to,
      );

  // ---------- Navegación ----------

  bool navigate(AppView v) {
    if (!state.allowed(v)) return false;
    state.currentView = v;
    _emit();
    return true;
  }

  void _ensureViewAllowed() {
    if (!state.allowed(state.currentView)) state.currentView = state.firstAllowed();
  }

  // ---------- Recibido sin ubicar ----------

  String simulateReceipt() {
    final id = 'REC-${state.receiptSeq++}';
    final supplier = kSuppliers[_rng.nextInt(kSuppliers.length)];
    final ids = state.products.map((p) => p.id).toList()..shuffle(_rng);
    final n = 1 + _rng.nextInt(2);
    state.receipts.insert(
      0,
      Receipt(
        id: id,
        supplier: supplier,
        date: kToday,
        items: [
          for (final pid in ids.take(n))
            ReceiptItem(productId: pid, qtyReceived: (2 + _rng.nextInt(8)) * 5),
        ],
      ),
    );
    _emit();
    return id;
  }

  /// Ubica unidades de un artículo del recibo en canastas. Devuelve error o null.
  String? allocateReceiptItem(String receiptId, String productId, List<(String, int)> rows) {
    final rec = state.receipts.firstWhereOrNull((r) => r.id == receiptId);
    final item = rec?.items.firstWhereOrNull((i) => i.productId == productId);
    if (rec == null || item == null) return 'Recibo no encontrado.';
    final valid = rows.where((r) => r.$2 > 0).toList();
    if (valid.isEmpty) return 'Agrega al menos una canasta con cantidad mayor que 0.';
    final sum = valid.fold(0, (a, r) => a + r.$2);
    if (sum > item.pending) return 'Lo asignado excede lo pendiente ($sum de ${item.pending}).';
    for (final (bin, qty) in valid) {
      final existing = state.inventory.firstWhereOrNull(
          (r) => r.productId == productId && r.store == kCentral && r.bin == bin && r.qty > 0);
      if (existing != null) {
        existing.qty += qty;
      } else {
        state.inventory.add(InvRow(
          id: _invId(),
          productId: productId,
          store: kCentral,
          bin: bin,
          qty: qty,
          entryDate: rec.date,
          receipt: rec.id,
          lot: 'L-${state.lotSeq++}',
          user: kCurrentUser,
        ));
      }
      _log(_mv('entrada', productId, qty, rec.id, '—', '$kCentral / $bin'));
    }
    item.qtyAllocated += sum;
    _emit();
    return null;
  }

  // ---------- Órdenes entrantes ----------

  String simulateOrder() {
    final id = 'OV-${state.orderSeq++}';
    final ids = state.products.map((p) => p.id).toList()..shuffle(_rng);
    final n = 2 + _rng.nextInt(2);
    final stores = kStores.where((s) => s != kCentral).toList();
    state.orders.insert(
      0,
      Order(
        id: id,
        customer: kCustomers[_rng.nextInt(kCustomers.length)],
        store: stores[_rng.nextInt(stores.length)],
        date: kToday,
        status: 'pendiente',
        items: [
          for (final pid in ids.take(n)) OrderItem(productId: pid, qty: 1 + _rng.nextInt(6)),
        ],
      ),
    );
    _emit();
    return id;
  }

  void calcOrderRoute(String orderId) {
    final o = state.orders.firstWhereOrNull((x) => x.id == orderId);
    if (o == null) return;
    for (final i in o.items.where((i) => i.remaining > 0)) {
      final key = orderSessionKey(o.id, i.productId);
      state.pickSessions[key] = createPickSession(
        state.inventory,
        key: key,
        productId: i.productId,
        qty: i.remaining,
        doc: o.id,
        nextId: _stepId,
      );
    }
    _emit();
  }

  /// Reconstruye desde cero una sesión existente.
  void recalcSession(String key) {
    final s = state.pickSessions[key];
    if (s == null) return;
    state.pickSessions[key] = createPickSession(
      state.inventory,
      key: key,
      productId: s.productId,
      qty: s.qtyRequested,
      doc: s.doc,
      nextId: _stepId,
    );
    _emit();
  }

  /// Confirma el piqueo de la orden. Devuelve true si quedó parcial.
  bool? confirmOrder(String orderId) {
    final o = state.orders.firstWhereOrNull((x) => x.id == orderId);
    if (o == null || !state.orderCanConfirm(o)) return null;
    for (final i in o.items.where((i) => i.remaining > 0)) {
      final key = orderSessionKey(o.id, i.productId);
      final s = state.pickSessions[key]!;
      final res = commitPickSession(
        s,
        state.inventory,
        docLabel: o.id,
        dispatchLabel: o.store,
        user: kCurrentUser,
        now: kToday,
        nextMovementId: _mvId,
      );
      _logAll(res.movements);
      i.delivered += res.delivered;
      state.pickSessions.remove(key);
    }
    final partial = o.items.any((i) => i.remaining > 0);
    o.status = partial ? 'parcial' : 'completada';
    _emit();
    return partial;
  }

  // ---------- Piqueo FIFO (herramienta individual) ----------

  void suggestSingle(String productId, int qty, String doc) {
    state.pickSessions[kSingleSessionKey] = createPickSession(
      state.inventory,
      key: kSingleSessionKey,
      productId: productId,
      qty: qty,
      doc: doc,
      nextId: _stepId,
    );
    _emit();
  }

  void cancelSingle() {
    state.pickSessions.remove(kSingleSessionKey);
    _emit();
  }

  CommitResult? confirmSingle() {
    final s = state.pickSessions[kSingleSessionKey];
    if (s == null || !sessionCanConfirm(s)) return null;
    final res = commitPickSession(
      s,
      state.inventory,
      docLabel: s.doc,
      dispatchLabel: 'Despacho',
      user: kCurrentUser,
      now: kToday,
      nextMovementId: _mvId,
    );
    _logAll(res.movements);
    state.pickSessions.remove(kSingleSessionKey);
    _emit();
    return res;
  }

  // ---------- Acciones sobre pasos ----------

  void stepPicked(String key, String stepId) {
    final s = state.pickSessions[key];
    if (s == null) return;
    markPicked(s, stepId);
    _emit();
  }

  void stepMissingHere(String key, String stepId) {
    final s = state.pickSessions[key];
    if (s == null) return;
    markMissingHere(s, stepId, state.inventory, _stepId);
    _emit();
  }

  void declareShortfall(String key) {
    final s = state.pickSessions[key];
    if (s == null) return;
    declareShortfallMissing(s, state.inventory, _stepId);
    _emit();
  }

  // ---------- Transferencias entre bins ----------

  String? binTransfer({
    required String productId,
    required String? srcRowId,
    required String destBin,
    required int qty,
    String obs = '',
  }) {
    final src = state.inventory.firstWhereOrNull(
        (r) => r.id == srcRowId && r.productId == productId && r.store == kCentral && r.qty > 0);
    if (src == null) return 'Selecciona un bin de origen.';
    if (qty <= 0) return 'Ingresa una cantidad válida (mayor que 0).';
    if (qty > src.qty) return 'La cantidad excede lo disponible en ${src.bin} (${src.qty}).';
    if (src.bin == destBin) return 'El bin destino debe ser diferente al de origen.';
    src.qty -= qty;
    final dest = state.inventory.firstWhereOrNull((r) =>
        r.id != src.id &&
        r.productId == productId &&
        r.store == kCentral &&
        r.bin == destBin &&
        r.qty > 0);
    if (dest != null) {
      dest.qty += qty;
    } else {
      state.inventory.add(InvRow(
        id: _invId(),
        productId: productId,
        store: kCentral,
        bin: destBin,
        qty: qty,
        entryDate: src.entryDate,
        receipt: src.receipt,
        lot: src.lot,
        user: src.user,
      ));
    }
    state.inventory.removeWhere((r) => r.qty <= 0);
    final id = 'TB-${state.tbSeq++}';
    final note = obs.trim().isEmpty ? '—' : obs.trim();
    state.binTransfers.insert(
      0,
      BinTransfer(
        id: id,
        productId: productId,
        qty: qty,
        from: src.bin,
        to: destBin,
        user: kCurrentUser,
        dateTime: kToday,
        obs: note,
      ),
    );
    _log(_mv('transfer-bin', productId, qty, id, '$kCentral / ${src.bin}', '$kCentral / $destBin'));
    _emit();
    return null;
  }

  // ---------- Transferencias entre tiendas ----------

  ({String? error, String? id}) storeTransferSend({
    required String productId,
    required String fromStore,
    required String toStore,
    required int qty,
  }) {
    if (fromStore == toStore) {
      return (error: 'La tienda origen y la tienda destino deben ser diferentes.', id: null);
    }
    final avail = state.storeQty(productId, fromStore);
    if (qty < 1 || qty > avail) {
      return (error: 'Cantidad inválida: $fromStore tiene $avail unidad(es) de este producto.', id: null);
    }
    var remaining = qty;
    final rows = fifoSorted(state.rowsOf(productId).where((r) => r.store == fromStore));
    for (final r in rows) {
      if (remaining <= 0) break;
      final take = min(r.qty, remaining);
      r.qty -= take;
      remaining -= take;
    }
    state.inventory.removeWhere((r) => r.qty <= 0);
    final id = 'TS-${(state.tsSeq++).toString().padLeft(4, '0')}';
    state.storeTransfers.insert(
      0,
      StoreTransfer(
        id: id,
        productId: productId,
        qty: qty,
        fromStore: fromStore,
        toStore: toStore,
        sentAt: kToday,
      ),
    );
    _log(_mv('transfer-store-out', productId, qty, id, fromStore, toStore));
    _emit();
    return (error: null, id: id);
  }

  void storeTransferConfirm(String id) {
    final t = state.storeTransfers.firstWhereOrNull((x) => x.id == id);
    if (t == null || t.status != 'pendiente') return;
    state.inventory.add(InvRow(
      id: _invId(),
      productId: t.productId,
      store: t.toStore,
      bin: receiveBinFor(t.toStore),
      qty: t.qty,
      entryDate: kToday,
      receipt: t.id,
      lot: '—',
      user: kCurrentUser,
    ));
    _log(_mv('transfer-store-in', t.productId, t.qty, t.id, t.fromStore, t.toStore));
    t.status = 'recibido';
    t.receivedAt = kToday;
    _emit();
  }

  /// Prepara Transferencias → Entre tiendas con los datos sugeridos.
  /// Devuelve false si el usuario simulado no tiene acceso a Transferencias.
  bool prefillStoreTransfer({required String productId, required String fromStore, required int qty}) {
    if (!state.allowed(AppView.transfers)) return false;
    state.transferPrefill = StoreTransferPrefill(
      seq: state.prefillSeq++,
      productId: productId,
      fromStore: fromStore,
      toStore: kCentral,
      qty: qty,
    );
    state.currentView = AppView.transfers;
    _emit();
    return true;
  }

  /// Marca el prefill como consumido (sin reconstruir).
  void consumePrefill() => state.transferPrefill = null;

  // ---------- Usuarios y permisos ----------

  String addUser() {
    final id = 'u${state.userSeq++}';
    state.users.add(AppUser(
      id: id,
      name: 'Nuevo usuario',
      email: '',
      role: 'Piqueador',
      active: true,
      perms: rolePreset('Piqueador'),
    ));
    _emit();
    return id;
  }

  void updateUser(String id, {String? name, String? email, String? role, bool? active}) {
    final u = state.users.firstWhereOrNull((x) => x.id == id);
    if (u == null) return;
    if (name != null) u.name = name;
    if (email != null) u.email = email;
    if (role != null) u.role = role;
    if (active != null) u.active = active;
    if (state.simulatedUserId == id && !u.active) state.simulatedUserId = null;
    _ensureViewAllowed();
    _emit();
  }

  void applyRolePreset(String id) {
    final u = state.users.firstWhereOrNull((x) => x.id == id);
    if (u == null) return;
    u.perms = rolePreset(u.role);
    _ensureViewAllowed();
    _emit();
  }

  void setPerm(String id, Area area, bool value) {
    final u = state.users.firstWhereOrNull((x) => x.id == id);
    if (u == null) return;
    u.perms = {...u.perms, area: value};
    _ensureViewAllowed();
    _emit();
  }

  void deleteUser(String id) {
    state.users.removeWhere((u) => u.id == id);
    if (state.simulatedUserId == id) state.simulatedUserId = null;
    _ensureViewAllowed();
    _emit();
  }

  void startSimulation(String id) {
    final u = state.users.firstWhereOrNull((x) => x.id == id);
    if (u == null || !u.active) return;
    state.simulatedUserId = id;
    _ensureViewAllowed();
    _emit();
  }

  void exitSimulation() {
    state.simulatedUserId = null;
    _emit();
  }
}
