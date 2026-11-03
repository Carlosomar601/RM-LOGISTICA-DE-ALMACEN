import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/rm_api.dart';
import '../auth/audit_log.dart';
import '../auth/user_store.dart';
import '../config/app_config.dart';
import '../data/data_store.dart';
import '../data/seed.dart';
import '../models/admin_config.dart';
import '../models/app_user.dart';
import '../models/inv_row.dart';
import '../models/json_util.dart';
import '../models/movement.dart';
import '../models/order.dart';
import '../models/pick_session.dart';
import '../models/product.dart';
import '../models/receipt.dart';
import '../models/store_transfer.dart';
import '../sync/dispatch_ledger.dart';
import '../sync/sync_settings.dart';
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
        AppView.users => 'Administración',
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

/// Versión del formato de data.json.
const kDataVersion = 1;

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
    required this.stores,
    required this.bins,
    required this.settings,
    required this.rolePresets,
    required this.importedLineIds,
    this.currentView = AppView.dashboard,
    this.simulatedUserId,
    this.currentUserId,
    this.userStoreError,
    this.dataStoreError,
    this.lastConfigApiUrl,
    this.logoutReason,
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
    this.storeSeq = 4,
    this.binSeq = 1,
    this.productSeq = 11,
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
        stores: seedStores(),
        bins: seedBins(),
        settings: AppSettings(),
        rolePresets: {for (final r in kRoles) r: rolePreset(r)},
        importedLineIds: {},
      );

  /// PC instalado sin data.json: solo el almacén central con sus canastas de recepción.
  /// Tiendas, canastas, productos y existencias se crean en la app o llegan de RM.
  factory AppState.empty() {
    final central = seedStores().firstWhere((s) => s.isCentral);
    return AppState(
      products: [],
      inventory: [],
      orders: [],
      receipts: [],
      history: [],
      storeTransfers: [],
      binTransfers: [],
      users: [],
      pickSessions: {},
      stores: [central],
      bins: [
        for (final b in seedBins())
          if (b.storeId == central.id && b.special) b,
      ],
      settings: AppSettings(),
      rolePresets: {for (final r in kRoles) r: rolePreset(r)},
      importedLineIds: {},
      productSeq: 1,
      invSeq: 1,
    );
  }

  /// Contenido de data.json (sin usuarios ni datos de sesión/pantalla).
  Map<String, dynamic> toDataJson() => {
        'version': kDataVersion,
        'products': [for (final x in products) x.toJson()],
        'inventory': [for (final x in inventory) x.toJson()],
        'orders': [for (final x in orders) x.toJson()],
        'receipts': [for (final x in receipts) x.toJson()],
        'history': [for (final x in history) x.toJson()],
        'storeTransfers': [for (final x in storeTransfers) x.toJson()],
        'binTransfers': [for (final x in binTransfers) x.toJson()],
        'pickSessions': [for (final x in pickSessions.values) x.toJson()],
        'stores': [for (final x in stores) x.toJson()],
        'bins': [for (final x in bins) x.toJson()],
        'settings': settings.toJson(),
        'importedLineIds': (importedLineIds.toList()..sort()),
        if (lastConfigApiUrl != null) 'lastConfigApiUrl': lastConfigApiUrl,
        'seq': {
          'order': orderSeq,
          'receipt': receiptSeq,
          'lot': lotSeq,
          'tb': tbSeq,
          'ts': tsSeq,
          'movement': movementSeq,
          'inv': invSeq,
          'step': stepSeq,
          'store': storeSeq,
          'bin': binSeq,
          'product': productSeq,
        },
      };

  /// Lee data.json. Lanza [FormatException] si falta algo: el archivo se trata como dañado.
  factory AppState.fromDataJson(Map j) {
    final v = j['version'];
    if (v is! num || v.toInt() > kDataVersion) {
      throw FormatException('versión de datos no soportada: $v');
    }
    final seq = j['seq'] is Map ? j['seq'] as Map : throw const FormatException('falta "seq"');
    final settings = j['settings'] is Map ? j['settings'] as Map : throw const FormatException('falta "settings"');
    final stores = [for (final x in jList(j, 'stores')) Store.fromJson(x)];
    if (!stores.any((s) => s.isCentral)) throw const FormatException('no hay almacén central');
    return AppState(
      products: [for (final x in jList(j, 'products')) Product.fromJson(x)],
      inventory: [for (final x in jList(j, 'inventory')) InvRow.fromJson(x)],
      orders: [for (final x in jList(j, 'orders')) Order.fromJson(x)],
      receipts: [for (final x in jList(j, 'receipts')) Receipt.fromJson(x)],
      history: [for (final x in jList(j, 'history')) Movement.fromJson(x)],
      storeTransfers: [for (final x in jList(j, 'storeTransfers')) StoreTransfer.fromJson(x)],
      binTransfers: [for (final x in jList(j, 'binTransfers')) BinTransfer.fromJson(x)],
      users: [],
      pickSessions: {
        for (final p in [for (final x in jList(j, 'pickSessions')) PickSession.fromJson(x)]) p.key: p,
      },
      stores: stores,
      bins: [for (final x in jList(j, 'bins')) Bin.fromJson(x)],
      settings: AppSettings.fromJson(settings),
      rolePresets: {for (final r in kRoles) r: rolePreset(r)},
      importedLineIds: jStrings(j, 'importedLineIds').toSet(),
      lastConfigApiUrl: jStrOrNull(j, 'lastConfigApiUrl'),
      orderSeq: jInt(seq, 'order'),
      receiptSeq: jInt(seq, 'receipt'),
      lotSeq: jInt(seq, 'lot'),
      tbSeq: jInt(seq, 'tb'),
      tsSeq: jInt(seq, 'ts'),
      movementSeq: jInt(seq, 'movement'),
      invSeq: jInt(seq, 'inv'),
      stepSeq: jInt(seq, 'step'),
      storeSeq: jInt(seq, 'store'),
      binSeq: jInt(seq, 'bin'),
      productSeq: jInt(seq, 'product'),
    );
  }

  final List<Product> products;
  final List<InvRow> inventory;
  final List<Order> orders;
  final List<Receipt> receipts;
  final List<Movement> history;
  final List<StoreTransfer> storeTransfers;
  final List<BinTransfer> binTransfers;
  final List<AppUser> users;
  final Map<String, PickSession> pickSessions;
  final List<Store> stores;
  final List<Bin> bins;
  AppSettings settings;
  /// Líneas de recibo ya importadas desde RM: `storeId|LineID`.
  final Set<String> importedLineIds;
  final Map<String, Map<Area, bool>> rolePresets;
  AppView currentView;
  String? simulatedUserId;

  /// Usuario con sesión iniciada (null = pantalla de PIN).
  String? currentUserId;

  /// users.json dañado: no se puede iniciar sesión.
  String? userStoreError;

  /// data.json dañado: la app no guarda (para no sobrescribirlo) hasta restaurar o empezar vacío.
  String? dataStoreError;

  /// Última dirección API de config.json aplicada al almacén central: si el instalador la
  /// cambia se aplica al abrir; si no, manda la que se editó en Administración → Tiendas.
  String? lastConfigApiUrl;

  /// Motivo del último cierre automático, para mostrarlo en la pantalla de PIN.
  String? logoutReason;
  StoreTransferPrefill? transferPrefill;
  int orderSeq, receiptSeq, lotSeq, tbSeq, tsSeq, movementSeq, invSeq, stepSeq, userSeq, prefillSeq, storeSeq, binSeq, productSeq;

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
        stores: stores,
        bins: bins,
        settings: settings,
        rolePresets: rolePresets,
        importedLineIds: importedLineIds,
        currentView: currentView,
        simulatedUserId: simulatedUserId,
        currentUserId: currentUserId,
        userStoreError: userStoreError,
        dataStoreError: dataStoreError,
        lastConfigApiUrl: lastConfigApiUrl,
        logoutReason: logoutReason,
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
        storeSeq: storeSeq,
        binSeq: binSeq,
        productSeq: productSeq,
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
      inventory.where((r) => r.qty > 0 && ageDays(r.entryDate) >= settings.ageAlertDays).length;

  List<InvRow> get staleRows => fifoSorted(
      inventory.where((r) => r.qty > 0 && ageDays(r.entryDate) >= settings.staleDays));

  List<Receipt> get pendingReceipts => receipts.where((r) => r.isPending).toList();

  List<Order> get openOrders => orders.where((o) => o.isOpen).toList();

  List<Order> get completedOrders => orders.where((o) => !o.isOpen).toList();

  /// Categorías de cliente (por nombre) elegidas por el usuario en «Órdenes entrantes» (vacío = todas).
  Set<String> get orderCategoryFilter => {...?currentUser?.orderCategories};

  /// Niveles de precio (por nombre) elegidos por el usuario en «Órdenes entrantes» (vacío = todos).
  Set<String> get orderPriceLevelFilter => {...?currentUser?.orderPriceLevels};

  AppUser? get currentUser =>
      currentUserId == null ? null : users.firstWhereOrNull((u) => u.id == currentUserId);

  /// Quién firma los registros (inventario, movimientos, transferencias).
  String get actor => currentUser?.shortName ?? 'Sistema';

  AppUser? get simulatedUser =>
      simulatedUserId == null ? null : users.firstWhereOrNull((u) => u.id == simulatedUserId);

  bool allowed(AppView v) {
    final u = simulatedUser ?? currentUser;
    final a = v.area;
    if (u == null || a == null) return true;
    return u.can(a);
  }

  AppView firstAllowed() =>
      AppView.values.firstWhere((v) => v != AppView.about && allowed(v), orElse: () => AppView.about);

  List<Store> get activeStores => stores.where((s) => s.active).toList();

  Store? storeByName(String name) => stores.firstWhereOrNull((s) => s.name == name);

  Store get centralStore => stores.firstWhere((s) => s.isCentral);

  /// Canastas activas del almacén central (para recibir y transferir).
  List<String> get centralBinCodes =>
      bins
          .where((b) => b.storeId == centralStore.id && b.active && b.code != centralStore.receiveBin)
          .map((b) => b.code)
          .toList();

  Map<Area, bool> presetFor(String role) =>
      Map.of(rolePresets[role] ?? rolePreset(role));

  /// Bin de recepción de una tienda (parametrizado).
  String receiveBinOf(String store) => storeByName(store)?.receiveBin ?? receiveBinFor(store);

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

class ImportResult {
  const ImportResult({
    required this.lines,
    required this.duplicates,
    required this.skipped,
    required this.fractional,
    required this.receiptsCreated,
    required this.receiptsUpdated,
    required this.productsCreated,
  });
  final int lines, duplicates, skipped, fractional, receiptsCreated, receiptsUpdated, productsCreated;
}

class OrderSyncResult {
  const OrderSyncResult({
    this.created = 0,
    this.updated = 0,
    this.flagged = 0,
    this.removed = 0,
    this.invoiced = 0,
    this.skipped = 0,
    this.alreadyDispatched = 0,
    this.productsCreated = 0,
    this.fractional = 0,
  });
  final int created, updated, flagged, removed, invoiced, skipped, alreadyDispatched, productsCreated, fractional;

  String get summary => [
        '$created nueva(s)',
        if (updated > 0) '$updated actualizada(s)',
        if (flagged > 0) '$flagged a revisar',
        if (removed > 0) '$removed cerrada(s) en RM',
        if (invoiced > 0) '$invoiced facturada(s)',
        if (alreadyDispatched > 0) '$alreadyDispatched ya despachada(s)',
        if (skipped > 0) '$skipped línea(s) omitida(s)',
      ].join(' · ');
}

class InvoiceSyncResult {
  const InvoiceSyncResult({
    this.created = 0,
    this.linked = 0,
    this.alreadyDispatched = 0,
    this.duplicates = 0,
    this.skipped = 0,
    this.productsCreated = 0,
    this.fractional = 0,
    this.registerSales = 0,
    this.voidUpdated = 0,
    this.voidFlagged = 0,
  });
  final int created, linked, alreadyDispatched, duplicates, skipped, productsCreated, fractional;

  /// Ventas en caja: el cliente se llevó la mercancía; no se despachan del almacén.
  final int registerSales;

  /// Facturas ya importadas con una anulación parcial posterior: ajustadas / a revisar.
  final int voidUpdated, voidFlagged;

  String get summary => [
        '$created nueva(s)',
        if (linked > 0) '$linked enlazada(s) a su orden',
        if (alreadyDispatched > 0) '$alreadyDispatched ya despachada(s) como orden',
        if (voidUpdated > 0) '$voidUpdated ajustada(s) por anulación',
        if (voidFlagged > 0) '$voidFlagged anulada(s) en parte (revisar)',
        if (registerSales > 0) '$registerSales venta(s) en caja (no se despachan)',
        if (skipped > 0) '$skipped línea(s) omitida(s)',
      ].join(' · ');
}

/// Ventas en caja (registradora): el cliente se lleva la mercancía, no pasan por despacho.
const kRegisterSaleTransactions = kDefaultSkipTransactions;

/// Reloj inyectable (las pruebas lo sustituyen).
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final appProvider = NotifierProvider<AppNotifier, AppState>(AppNotifier.new);

class AppNotifier extends Notifier<AppState> {
  AppNotifier({Random? rng}) : _rng = rng ?? Random();

  final Random _rng;

  @override
  AppState build() {
    ref.onDispose(() => _saveTimer?.cancel());
    final installed = ref.read(appConfigProvider).source != null;
    final load = ref.read(dataLoadProvider);
    AppState s;
    String? dataError;
    switch (load.status) {
      case DataStoreStatus.ok:
        try {
          s = AppState.fromDataJson(load.json!);
        } catch (e) {
          s = AppState.empty();
          dataError = 'No se pudieron leer los datos del almacén (${ref.read(dataFileProvider)?.path ?? 'data.json'}): $e';
        }
      case DataStoreStatus.broken:
        s = AppState.empty();
        dataError = load.error;
      case DataStoreStatus.missing:
        s = installed ? AppState.empty() : AppState.seed();
    }
    s.dataStoreError = dataError;
    _applyUsers(s, ref.read(userStoreProvider));
    final url = ref.read(appConfigProvider).apiUrl;
    if (url.isNotEmpty && url != s.lastConfigApiUrl) {
      s.centralStore.apiUrl = url;
      s.lastConfigApiUrl = url;
    }
    return s;
  }

  void _applyUsers(AppState s, UserStoreData store) {
    s.users
      ..clear()
      ..addAll(store.users);
    s.rolePresets
      ..clear()
      ..addAll(store.rolePresets);
    s.settings.autoLogoutMinutes = store.autoLogoutMinutes;
    s.userStoreError = store.status == UserStoreStatus.broken ? store.error : null;
    final maxId = s.users.map((u) => int.tryParse(u.id.replaceFirst('u', '')) ?? 0).fold(0, max);
    s.userSeq = store.status == UserStoreStatus.ok ? maxId + 1 : max(s.userSeq, maxId + 1);
  }

  void _emit() {
    state = state.clone();
    _scheduleSave();
  }

  // ---------- Guardado de data.json ----------

  Timer? _saveTimer;

  /// Espera tras el último cambio antes de escribir (agrupa ráfagas de cambios).
  static const saveDelay = Duration(seconds: 2);

  /// Último error al guardar (sin permiso, disco lleno…); null = guardado al día.
  String? lastSaveError;

  bool get _canSave => ref.read(dataFileProvider) != null && state.dataStoreError == null;

  void _scheduleSave() {
    if (!_canSave) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, flush);
  }

  /// Guarda ya lo pendiente (antes de un respaldo, al cerrar sesión o la ventana).
  void flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final file = ref.read(dataFileProvider);
    if (file == null || state.dataStoreError != null) return;
    try {
      DataStore.write(file, state.toDataJson());
      lastSaveError = null;
    } catch (e) {
      lastSaveError = 'No se pudieron guardar los datos: $e';
    }
  }

  /// data.json dañado → lo aparta (`data.danado-….json`) y sigue con un almacén vacío.
  void startFresh() {
    final file = ref.read(dataFileProvider);
    if (file != null) {
      try {
        DataStore.setAsideBroken(file, ref.read(clockProvider)());
      } catch (_) {}
    }
    final fresh = AppState.empty()
      ..users.addAll(state.users)
      ..currentUserId = state.currentUserId
      ..currentView = state.currentView
      ..settings.autoLogoutMinutes = state.settings.autoLogoutMinutes
      ..userSeq = state.userSeq
      ..lastConfigApiUrl = state.lastConfigApiUrl;
    fresh.rolePresets
      ..clear()
      ..addAll(state.rolePresets);
    final url = ref.read(appConfigProvider).apiUrl;
    if (url.isNotEmpty) fresh.centralStore.apiUrl = url;
    _audit('datos dañados apartados; se empezó vacío', state.currentUser?.name ?? '—');
    state = fresh;
    flush();
  }

  /// Reemplaza todo con un respaldo ya validado y cierra la sesión (los usuarios pudieron cambiar).
  void restoreFrom(AppState data, UserStoreData users) {
    final by = state.currentUser?.name ?? '—';
    data
      ..dataStoreError = null
      ..currentView = AppView.dashboard
      ..logoutReason = 'Respaldo restaurado. Entra con tu PIN.';
    _applyUsers(data, users);
    final url = ref.read(appConfigProvider).apiUrl;
    if (url.isNotEmpty) {
      // La dirección API de este PC (config.json) no viaja con el respaldo.
      data.centralStore.apiUrl = url;
      data.lastConfigApiUrl = url;
    }
    _failedPins = 0;
    _lockedUntil = null;
    _audit('respaldo restaurado', by);
    state = data;
    flush();
    _saveUsers();
  }

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
        user: state.actor,
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
          user: state.actor,
        ));
      }
      _log(_mv('entrada', productId, qty, rec.id, '—', '$kCentral / $bin'));
    }
    item.qtyAllocated += sum;
    _emit();
    return null;
  }

  // ---------- Importación desde RM ----------

  /// Trae de la API de una tienda las líneas recibidas en un rango de fechas.
  Future<List<RmReceiptLine>> fetchReceiptLines(String storeId, DateTime from, DateTime to) async {
    final st = state.stores.firstWhereOrNull((s) => s.id == storeId);
    if (st == null) throw RmApiException('Tienda no encontrada.');
    if (st.apiUrl.trim().isEmpty) {
      throw RmApiException('${st.name} no tiene dirección API. Configúrala en Administración → Tiendas.');
    }
    return ref.read(rmApiFactoryProvider)(st.apiUrl).receiptsByDate(from, to);
  }

  bool isLineImported(String storeId, RmReceiptLine l) => state.importedLineIds.contains('$storeId|${l.lineId}');

  /// Por qué una línea no se puede importar (null = se puede).
  static String? skipReason(RmReceiptLine l) {
    if (l.lineId.isEmpty || l.receiptNumber.isEmpty || l.itemCode.isEmpty) return 'datos incompletos';
    if (l.quantityReceived.round() <= 0) return 'cantidad ${l.quantityReceived} se redondea a 0';
    return null;
  }

  /// Importa líneas como recibos pendientes de ubicar. Es idempotente por LineID.
  ImportResult importReceiptLines(String storeId, List<RmReceiptLine> lines) {
    var duplicates = 0, skipped = 0, fractional = 0, imported = 0;
    final created = <String>{}, updated = <String>{};
    var productsCreated = 0;
    for (final l in lines) {
      final key = '$storeId|${l.lineId}';
      if (skipReason(l) != null) {
        skipped++;
        continue;
      }
      if (state.importedLineIds.contains(key)) {
        duplicates++;
        continue;
      }
      final qty = l.quantityReceived.round();
      if (qty != l.quantityReceived) fractional++;
      final (product, isNew) = _ensureProduct(l.itemCode, l.description);
      if (isNew) productsCreated++;
      final rid = 'RM-${l.receiptNumber}';
      var rec = state.receipts.firstWhereOrNull((r) => r.id == rid);
      if (rec == null) {
        rec = Receipt(id: rid, supplier: l.supplierName, date: l.receiptDate, items: []);
        state.receipts.insert(0, rec);
        created.add(rid);
      } else if (!created.contains(rid)) {
        updated.add(rid);
      }
      final item = rec.items.firstWhereOrNull((i) => i.productId == product.id);
      if (item == null) {
        rec.items.add(ReceiptItem(productId: product.id, qtyReceived: qty));
      } else {
        item.qtyReceived += qty;
      }
      state.importedLineIds.add(key);
      imported++;
    }
    if (imported > 0) _emit();
    return ImportResult(
      lines: imported,
      duplicates: duplicates,
      skipped: skipped,
      fractional: fractional,
      receiptsCreated: created.length,
      receiptsUpdated: updated.length,
      productsCreated: productsCreated,
    );
  }

  /// Busca el producto por código o lo crea con la descripción de RM.
  (Product, bool) _ensureProduct(String code, String desc) {
    final p = state.products.firstWhereOrNull((p) => p.code.toLowerCase() == code.toLowerCase());
    if (p != null) return (p, false);
    final n = Product(id: 'p${state.productSeq++}', code: code, desc: desc);
    state.products.add(n);
    return (n, true);
  }

  String _codeOf(String productId) => state.product(productId).code.toLowerCase();

  /// Una orden está "tocada" si ya se piqueó algo o tiene una ruta de piqueo en curso.
  bool orderTouched(Order o) =>
      o.items.any((i) => i.delivered > 0) ||
      o.items.any((i) => state.pickSessions.containsKey(orderSessionKey(o.id, i.productId)));

  Order? _rmOrder(String source, String storeId, String number) => state.orders
      .firstWhereOrNull((o) => o.source == source && o.rmStore == storeId && o.rmNumber == number);

  static String? orderSkipReason(RmOrderLine l) {
    if (l.orderNumber.isEmpty || l.itemCode.isEmpty) return 'datos incompletos';
    if (l.isFuel) return 'combustible';
    if (l.isService) return 'servicio';
    if (l.pending.round() <= 0) return 'pendiente ${l.pending} se redondea a 0';
    return null;
  }

  /// Por qué una línea de factura no entra al almacén (null = entra). La cantidad se evalúa
  /// aparte, porque una línea anulada por completo después sigue contando para detectar el cambio.
  static String? invoiceSkipReason(RmInvoiceLine l, {Set<int> skipTransactions = kRegisterSaleTransactions}) {
    if (l.invoiceNumber.isEmpty || l.itemCode.isEmpty) return 'datos incompletos';
    if (l.isReturnOrVoid) return 'devolución o anulación';
    if (skipTransactions.contains(l.transaction)) return 'venta en caja';
    if (l.isService) return 'servicio';
    return null;
  }

  Store? _storeById(String id) => state.stores.firstWhereOrNull((s) => s.id == id);

  RmApi _apiFor(String storeId) {
    final st = _storeById(storeId);
    if (st == null) throw RmApiException('Tienda no encontrada.');
    if (st.apiUrl.trim().isEmpty) {
      throw RmApiException('${st.name} no tiene dirección API. Configúrala en Administración → Tiendas.');
    }
    return ref.read(rmApiFactoryProvider)(st.apiUrl);
  }

  Future<List<RmOrderLine>> fetchOpenOrders(String storeId) => _apiFor(storeId).openOrders();

  Future<List<RmInvoiceLine>> fetchInvoices(String storeId, DateTime from, DateTime to) =>
      _apiFor(storeId).invoicesByDate(from, to);

  /// Compara la foto de órdenes abiertas de RM con lo que hay en la app.
  /// Nuevas → ORD-n; sin tocar → se actualizan; tocadas → aviso; desaparecidas → se quitan o se marcan.
  OrderSyncResult importOpenOrders(String storeId, List<RmOrderLine> lines) {
    final ledger = ref.read(ledgerProvider);
    final now = ref.read(clockProvider)();
    final storeName = _storeById(storeId)?.name ?? storeId;
    var created = 0, updated = 0, flagged = 0, removed = 0, invoiced = 0, skipped = 0;
    var dispatched = 0, productsCreated = 0, fractional = 0;

    final groups = <String, List<RmOrderLine>>{};
    for (final l in lines) {
      if (orderSkipReason(l) != null) {
        skipped++;
        continue;
      }
      groups.putIfAbsent(l.orderNumber, () => []).add(l);
    }

    for (final MapEntry(key: number, value: ls) in groups.entries) {
      // Cantidad pendiente por código de artículo.
      final want = <String, int>{};
      final descs = <String, String>{};
      for (final l in ls) {
        final q = l.pending.round();
        if (q != l.pending) fractional++;
        final k = l.itemCode.toLowerCase();
        want[k] = (want[k] ?? 0) + q;
        descs[k] = l.description;
        descs['$k#code'] = l.itemCode;
      }
      List<OrderItem> buildItems(LedgerEntry? entry) => [
            for (final MapEntry(key: k, value: q) in want.entries)
              () {
                final (p, isNew) = _ensureProduct(descs['$k#code']!, descs[k]!);
                if (isNew) productsCreated++;
                return OrderItem(productId: p.id, qty: q, delivered: min(entry?.pickedOf(k) ?? 0, q));
              }(),
          ];

      final existing = _rmOrder(OrderSource.rmOrder, storeId, number);
      final entry = ledger.order(storeId, number);
      if (existing == null) {
        final items = buildItems(entry);
        // Tras un reinicio: si ya se piqueó todo bajo esta orden, no vuelve a entrar.
        if (entry != null && entry.anyPicked && items.every((i) => i.remaining == 0)) {
          dispatched++;
          continue;
        }
        final id = 'ORD-$number';
        final first = ls.first;
        final o = Order(
          id: id,
          customer: first.customerName,
          customerId: first.customer,
          categoryId: first.categoryId,
          categoryName: categoryNameOf(first.categoryId, first.categoryName),
          priceLevelId: first.priceLevelId,
          priceLevelName: priceLevelNameOf(first.priceLevelId, first.priceLevelName),
          store: storeName,
          date: first.orderDate,
          status: items.any((i) => i.delivered > 0) ? 'parcial' : 'pendiente',
          items: items,
          source: OrderSource.rmOrder,
          rmStore: storeId,
          rmNumber: number,
          invoices: [...?entry?.invoices],
        );
        if (entry != null && entry.appId.startsWith('FAC-')) {
          // Su factura entró antes que la orden (se facturó entre dos sincronizaciones):
          // no se adivina qué parte ya va en la factura; se pide revisión.
          o.syncNote = 'Revisar antes de piquear: la factura ${entry.appId} de esta orden ya se importó; '
              'confirma que no se despache dos veces';
        } else if (o.invoices.isNotEmpty) {
          o.syncNote = 'Facturada en RM · FAC ${o.invoices.join(', ')}';
        }
        state.orders.insert(0, o);
        ledger.recordOrder(storeId, number, id, now);
        created++;
        continue;
      }

      // La categoría y el nivel del cliente se leen en vivo: si cambian en RM, la orden abierta los sigue.
      final f = ls.first;
      _setCustomer(existing, f.customer, f.categoryId, f.categoryName, f.priceLevelId, f.priceLevelName);
      final have = {for (final i in existing.items) _codeOf(i.productId): i.qty};
      final same = have.length == want.length && want.entries.every((e) => have[e.key] == e.value);
      if (same) continue;
      if (!orderTouched(existing) && existing.invoices.isEmpty) {
        existing.items
          ..clear()
          ..addAll(buildItems(null));
        existing.syncNote = null;
        updated++;
      } else {
        final changes = [
          for (final k in {...have.keys, ...want.keys})
            if (have[k] != want[k]) '${descs['$k#code'] ?? k}: ${have[k] ?? 0} → ${want[k] ?? 0}',
        ];
        existing.syncNote = 'Cambió en RM (revisar): ${changes.join('; ')}';
        flagged++;
      }
    }

    // Órdenes que ya no están abiertas en RM.
    for (final o in state.orders
        .where((o) => o.source == OrderSource.rmOrder && o.rmStore == storeId && o.isOpen && !groups.containsKey(o.rmNumber))
        .toList()) {
      if (o.invoices.isNotEmpty) {
        o.syncNote = 'Facturada en RM · FAC ${o.invoices.join(', ')}';
        invoiced++;
      } else if (!orderTouched(o)) {
        state.orders.remove(o);
        removed++;
      } else {
        o.syncNote = 'Cerrada en RM (revisar): ya no está abierta, pero se empezó a piquear';
        flagged++;
      }
    }

    ledger.save();
    _emit();
    return OrderSyncResult(
      created: created,
      updated: updated,
      flagged: flagged,
      removed: removed,
      invoiced: invoiced,
      skipped: skipped,
      alreadyDispatched: dispatched,
      productsCreated: productsCreated,
      fractional: fractional,
    );
  }

  /// Importa facturas de venta como FAC-n. Una factura que viene de una orden ya importada
  /// NO se vuelve a despachar: se enlaza a la orden y solo entra lo que excede lo ordenado
  /// (o, tras un reinicio, lo que no se piqueó bajo la orden).
  InvoiceSyncResult importInvoices(String storeId, List<RmInvoiceLine> lines,
      {Set<int> skipTransactions = kRegisterSaleTransactions}) {
    final ledger = ref.read(ledgerProvider);
    final now = ref.read(clockProvider)();
    final storeName = _storeById(storeId)?.name ?? storeId;
    var created = 0, linked = 0, dispatched = 0, duplicates = 0, skipped = 0, productsCreated = 0, fractional = 0;
    var voidUpdated = 0, voidFlagged = 0;

    final groups = <String, List<RmInvoiceLine>>{};
    final registerInvoices = <String>{};
    for (final l in lines) {
      final why = invoiceSkipReason(l, skipTransactions: skipTransactions);
      if (why == 'venta en caja') {
        registerInvoices.add(l.invoiceNumber);
        continue;
      }
      if (why != null) {
        skipped++;
        continue;
      }
      groups.putIfAbsent(l.invoiceNumber, () => []).add(l);
    }

    for (final MapEntry(key: number, value: ls) in groups.entries) {
      // Cantidad a despachar por artículo: vendido − anulado.
      final qty = <String, int>{};
      final descs = <String, String>{};
      for (final l in ls) {
        final q = l.toShip.round();
        if (q != l.toShip) fractional++;
        final k = l.itemCode.toLowerCase();
        qty[k] = (qty[k] ?? 0) + (q > 0 ? q : 0);
        descs[k] = l.description;
        descs['$k#code'] = l.itemCode;
      }

      final invEntry = ledger.invoice(storeId, number);
      final existingFac = _rmOrder(OrderSource.rmInvoice, storeId, number);
      final alreadyHere =
          existingFac != null || (invEntry != null && state.orders.any((o) => o.id == invEntry.appId));
      if (alreadyHere) {
        if (existingFac != null) {
          final f = ls.first;
          _setCustomer(existingFac, f.customer, f.categoryId, f.categoryName, f.priceLevelId, f.priceLevelName);
        }
        // Anulación parcial posterior en RM (VoidParcial): se ajusta si aún no se piquea.
        if (existingFac != null && existingFac.isOpen) {
          final have = {for (final i in existingFac.items) _codeOf(i.productId): i.qty};
          final changed = have.entries.where((e) => e.value > (qty[e.key] ?? 0)).toList();
          if (changed.isNotEmpty) {
            if (!orderTouched(existingFac)) {
              for (final i in existingFac.items) {
                i.qty = min(i.qty, qty[_codeOf(i.productId)] ?? 0);
              }
              existingFac.items.removeWhere((i) => i.qty <= 0);
              existingFac.syncNote = 'Anulada en parte en RM: se ajustó la cantidad';
              if (existingFac.items.isEmpty) state.orders.remove(existingFac);
              voidUpdated++;
            } else {
              final detail = [
                for (final e in changed) '${descs['${e.key}#code'] ?? e.key}: ${e.value} → ${qty[e.key] ?? 0}',
              ].join('; ');
              existingFac.syncNote = 'Anulada en parte en RM (revisar): $detail';
              voidFlagged++;
            }
            continue;
          }
        }
        duplicates++;
        continue;
      }
      if (qty.values.every((q) => q <= 0)) {
        skipped += ls.length; // anulada por completo antes de importarla
        continue;
      }

      final orderNumber = ls.first.orderNumber;
      final ordEntry = orderNumber.isEmpty ? null : ledger.order(storeId, orderNumber);
      final toDispatch = Map.of(qty);
      String? note;
      var appId = 'FAC-$number';

      if (ordEntry != null) {
        ordEntry.invoices.add(number);
        final order = _rmOrder(OrderSource.rmOrder, storeId, orderNumber);
        if (order != null) {
          // La orden sigue en la app: ella despacha lo facturado; solo entra lo adicional.
          if (!order.invoices.contains(number)) order.invoices.add(number);
          order.syncNote = 'Facturada en RM · FAC ${order.invoices.join(', ')}';
          final ordered = {for (final i in order.items) _codeOf(i.productId): i.qty};
          for (final k in qty.keys) {
            toDispatch[k] = qty[k]! - (ordered[k] ?? 0);
          }
          note = 'Adicional a ${order.id}';
          appId = order.id;
          linked++;
        } else {
          // La orden ya no está en la app (reinicio o cerrada): descontar lo ya piqueado bajo ella.
          for (final k in qty.keys) {
            toDispatch[k] = qty[k]! - ordEntry.pickedOf(k);
          }
          if (ordEntry.anyPicked) note = 'Resto de ${ordEntry.appId}';
        }
      }
      // Factura ya piqueada en parte antes de un reinicio.
      if (invEntry != null) {
        for (final k in qty.keys) {
          toDispatch[k] = toDispatch[k]! - invEntry.pickedOf(k);
        }
      }

      final items = <OrderItem>[];
      for (final MapEntry(key: k, value: q) in toDispatch.entries) {
        if (q <= 0) continue;
        final (p, isNew) = _ensureProduct(descs['$k#code']!, descs[k]!);
        if (isNew) productsCreated++;
        items.add(OrderItem(productId: p.id, qty: q));
      }

      if (items.isEmpty) {
        if (ordEntry != null && appId.startsWith('FAC-')) dispatched++;
        ledger.recordInvoice(storeId, number, appId, now);
        continue;
      }
      final first = ls.first;
      state.orders.insert(
        0,
        Order(
          id: 'FAC-$number',
          customer: first.customerName,
          customerId: first.customer,
          categoryId: first.categoryId,
          categoryName: categoryNameOf(first.categoryId, first.categoryName),
          priceLevelId: first.priceLevelId,
          priceLevelName: priceLevelNameOf(first.priceLevelId, first.priceLevelName),
          store: storeName,
          date: first.invoiceDate,
          status: 'pendiente',
          items: items,
          source: OrderSource.rmInvoice,
          rmStore: storeId,
          rmNumber: number,
          syncNote: note,
        ),
      );
      ledger.recordInvoice(storeId, number, 'FAC-$number', now);
      // Factura de una orden que aún no conocíamos: se anota para no traer la orden después sin aviso.
      if (orderNumber.isNotEmpty && ordEntry == null) {
        ledger.recordOrder(storeId, orderNumber, 'FAC-$number', now).invoices.add(number);
      }
      created++;
    }

    ledger.save();
    _emit();
    return InvoiceSyncResult(
      created: created,
      linked: linked,
      alreadyDispatched: dispatched,
      duplicates: duplicates,
      skipped: skipped,
      productsCreated: productsCreated,
      fractional: fractional,
      registerSales: registerInvoices.length,
      voidUpdated: voidUpdated,
      voidFlagged: voidFlagged,
    );
  }

  /// Actualiza el cliente, su categoría y su nivel de precio vigentes en una orden de RM ya importada.
  void _setCustomer(Order o, String customerId, int? categoryId, String categoryName, int? priceLevelId,
      String priceLevelName) {
    o.customerId = customerId.isEmpty ? o.customerId : customerId;
    o.categoryId = categoryId;
    o.categoryName = categoryNameOf(categoryId, categoryName);
    o.priceLevelId = priceLevelId;
    o.priceLevelName = priceLevelNameOf(priceLevelId, priceLevelName);
  }

  /// Anota en el libro de despachos lo piqueado de una orden o factura de RM.
  void _recordPicked(Order o, String productId, int qty) {
    if (!o.isRm || o.rmStore == null || o.rmNumber == null || qty <= 0) return;
    final ledger = ref.read(ledgerProvider);
    final now = ref.read(clockProvider)();
    final entry = o.source == OrderSource.rmOrder
        ? ledger.order(o.rmStore!, o.rmNumber!) ?? ledger.recordOrder(o.rmStore!, o.rmNumber!, o.id, now)
        : ledger.invoice(o.rmStore!, o.rmNumber!) ?? ledger.recordInvoice(o.rmStore!, o.rmNumber!, o.id, now);
    ledger.addPicked(entry, _codeOf(productId), qty);
  }

  // ---------- Órdenes entrantes ----------

  String simulateOrder() {
    final id = 'OV-${state.orderSeq++}';
    final ids = state.products.map((p) => p.id).toList()..shuffle(_rng);
    final n = 2 + _rng.nextInt(2);
    final stores = state.activeStores.where((s) => !s.isCentral).map((s) => s.name).toList();
    if (stores.isEmpty) stores.add(kCentral);
    final cust = kDemoCustomers[_rng.nextInt(kDemoCustomers.length)];
    state.orders.insert(
      0,
      Order(
        id: id,
        customer: cust.name,
        customerId: cust.id,
        categoryId: cust.categoryId,
        categoryName: cust.categoryName,
        priceLevelId: cust.priceLevelId,
        priceLevelName: cust.priceLevelName,
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

  /// Guarda las categorías de cliente (por nombre) elegidas por el usuario que inició sesión (vacío = todas).
  void setOrderCategoryFilter(Set<String> labels) {
    final u = state.currentUser;
    if (u == null) return;
    u.orderCategories = labels.toList()..sort();
    _saveUsers();
    _emit();
  }

  /// Guarda los niveles de precio (por nombre) elegidos por el usuario que inició sesión (vacío = todos).
  void setOrderPriceLevelFilter(Set<String> labels) {
    final u = state.currentUser;
    if (u == null) return;
    u.orderPriceLevels = labels.toList()..sort();
    _saveUsers();
    _emit();
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
        user: state.actor,
        now: kToday,
        nextMovementId: _mvId,
      );
      _logAll(res.movements);
      i.delivered += res.delivered;
      _recordPicked(o, i.productId, res.delivered);
      state.pickSessions.remove(key);
    }
    if (o.isRm) ref.read(ledgerProvider).save();
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
      user: state.actor,
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
        user: state.actor,
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
      bin: state.receiveBinOf(t.toStore),
      qty: t.qty,
      entryDate: kToday,
      receipt: t.id,
      lot: '—',
      user: state.actor,
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

  // ---------- Sesión (PIN) ----------

  int _failedPins = 0;
  DateTime? _lockedUntil;
  static const maxPinAttempts = 5;
  static const lockDuration = Duration(seconds: 30);

  /// Segundos que faltan para poder intentar de nuevo (0 = no bloqueado).
  int lockSecondsLeft() {
    final until = _lockedUntil;
    if (until == null) return 0;
    final left = until.difference(ref.read(clockProvider)()).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }

  void _audit(String event, String user) =>
      ref.read(auditProvider).add(AuditEvent(ref.read(clockProvider)(), event, user));

  /// Inicia sesión con un PIN de 4 dígitos. Devuelve el mensaje de error o null.
  String? login(String pin) {
    if (state.userStoreError != null) return 'No se pudieron leer los usuarios. Avisa al administrador.';
    if (lockSecondsLeft() > 0) return 'Demasiados intentos. Espera ${lockSecondsLeft()} s.';
    if (!isValidPin(pin)) return 'El PIN tiene 4 dígitos.';
    final match = state.users.firstWhereOrNull((u) => u.checkPin(pin));
    if (match == null || !match.active) {
      _failedPins++;
      _audit(match == null ? 'PIN incorrecto' : 'usuario inactivo', match?.name ?? '—');
      if (_failedPins >= maxPinAttempts) {
        _failedPins = 0;
        _lockedUntil = ref.read(clockProvider)().add(lockDuration);
        _audit('bloqueo ${lockDuration.inSeconds} s', '—');
        _emit();
        return 'Demasiados intentos. Espera ${lockDuration.inSeconds} s.';
      }
      _emit();
      return match == null ? 'PIN incorrecto' : 'Usuario inactivo. Avisa al administrador.';
    }
    _failedPins = 0;
    _lockedUntil = null;
    state.currentUserId = match.id;
    state.simulatedUserId = null;
    state.logoutReason = null;
    _audit('inicio de sesión', match.name);
    _ensureViewAllowed();
    _emit();
    return null;
  }

  void logout({String? reason}) {
    final u = state.currentUser;
    if (u == null) return;
    _audit(reason == null ? 'cierre de sesión' : 'cierre de sesión ($reason)', u.name);
    state.currentUserId = null;
    state.simulatedUserId = null;
    state.logoutReason = reason == null ? null : 'Sesión cerrada por $reason.';
    _emit();
  }

  void _saveUsers() {
    try {
      UserStoreData.save(
        ref.read(userStoreFileProvider),
        users: state.users,
        rolePresets: state.rolePresets,
        autoLogoutMinutes: state.settings.autoLogoutMinutes,
      );
    } catch (_) {
      // Sin permiso de escritura: el cambio queda en memoria; el instalador da permiso a la carpeta.
    }
  }

  /// Administradores activos que pueden iniciar sesión.
  bool _isLastLoginAdmin(String id) {
    final admins = state.users.where((u) => u.active && u.can(Area.users) && u.hasPin).toList();
    return admins.length == 1 && admins.first.id == id;
  }

  /// Asigna o cambia el PIN. Devuelve el error o null.
  String? setPin(String userId, String pin) {
    final u = state.users.firstWhereOrNull((x) => x.id == userId);
    if (u == null) return 'Usuario no encontrado.';
    if (!isValidPin(pin)) return 'El PIN debe tener exactamente 4 dígitos.';
    if (state.users.any((x) => x.id != userId && x.checkPin(pin))) return 'Ese PIN ya lo usa otro empleado.';
    u.setPin(pin);
    _saveUsers();
    _emit();
    return null;
  }

  String? clearPin(String userId) {
    final u = state.users.firstWhereOrNull((x) => x.id == userId);
    if (u == null) return 'Usuario no encontrado.';
    if (_isLastLoginAdmin(userId)) return 'Debe quedar al menos un administrador activo con PIN.';
    u.clearPin();
    _saveUsers();
    _emit();
    return null;
  }

  void setAutoLogoutMinutes(int minutes) {
    state.settings.autoLogoutMinutes = minutes.clamp(0, 600);
    _saveUsers();
    _emit();
  }

  // ---------- Usuarios y permisos ----------

  String addUser() {
    final id = 'u${state.userSeq++}';
    state.users.add(AppUser(
      id: id,
      name: 'Nuevo usuario',
      email: '',
      role: 'Piqueador',
      active: true,
      perms: state.presetFor('Piqueador'),
    ));
    _saveUsers();
    _emit();
    return id;
  }

  void updateUser(String id, {String? name, String? email, String? role, bool? active}) {
    final u = state.users.firstWhereOrNull((x) => x.id == id);
    if (u == null) return;
    if (name != null) u.name = name;
    if (email != null) u.email = email;
    if (role != null) u.role = role;
    if (active != null && !(active == false && _isLastAdmin(id))) u.active = active;
    if (state.simulatedUserId == id && !u.active) state.simulatedUserId = null;
    _saveUsers();
    _ensureViewAllowed();
    _emit();
  }

  void applyRolePreset(String id) {
    final u = state.users.firstWhereOrNull((x) => x.id == id);
    if (u == null) return;
    u.perms = state.presetFor(u.role);
    _saveUsers();
    _ensureViewAllowed();
    _emit();
  }

  void setPerm(String id, Area area, bool value) {
    final u = state.users.firstWhereOrNull((x) => x.id == id);
    if (u == null) return;
    if (!value && area == Area.users && _isLastAdmin(id)) return;
    u.perms = {...u.perms, area: value};
    _saveUsers();
    _ensureViewAllowed();
    _emit();
  }

  /// true si `id` es el único usuario activo con acceso a Administración.
  bool _isLastAdmin(String id) {
    final admins = state.users.where((u) => u.active && u.can(Area.users)).toList();
    return (admins.length == 1 && admins.first.id == id) || _isLastLoginAdmin(id);
  }

  bool isLastAdmin(String id) => _isLastAdmin(id);

  void deleteUser(String id) {
    if (_isLastAdmin(id)) return;
    if (state.currentUserId == id) return;
    state.users.removeWhere((u) => u.id == id);
    if (state.simulatedUserId == id) state.simulatedUserId = null;
    _saveUsers();
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

  // ---------- Administración: tiendas ----------

  bool _hasStoreHistory(Store st) =>
      state.inventory.any((r) => r.store == st.name) ||
      state.orders.any((o) => o.store == st.name) ||
      state.storeTransfers.any((t) => t.fromStore == st.name || t.toStore == st.name);

  bool storeHasHistory(String id) {
    final st = state.stores.firstWhereOrNull((s) => s.id == id);
    return st != null && _hasStoreHistory(st);
  }

  static final _urlRe = RegExp(r'^https?://[^\s/$.?#][^\s]*$', caseSensitive: false);

  /// Crea una tienda vacía lista para editar. Devuelve su id.
  String addStore() {
    var n = state.stores.length;
    var code = 'T$n';
    while (state.stores.any((s) => s.code == code)) {
      n++;
      code = 'T$n';
    }
    final id = 's${state.storeSeq++}';
    state.stores.add(Store(id: id, name: 'Nueva tienda $code', code: code, receiveBin: '$code-RX'));
    state.bins.add(Bin(id: 'b-$code-RX', storeId: id, code: '$code-RX', zone: 'Recepción', special: true));
    _emit();
    return id;
  }

  /// Actualiza una tienda. Devuelve un mensaje de error o null.
  String? updateStore(String id, {String? name, String? code, String? apiUrl, String? apiKey, bool? active}) {
    final st = state.stores.firstWhereOrNull((s) => s.id == id);
    if (st == null) return 'Tienda no encontrada.';
    if (name != null && name != st.name) {
      if (st.isCentral) return 'El nombre del almacén central no se puede cambiar.';
      if (name.trim().isEmpty) return 'El nombre es obligatorio.';
      if (_hasStoreHistory(st)) {
        return 'No se puede renombrar: la tienda tiene inventario o movimientos. Desactívala y crea otra.';
      }
      if (state.stores.any((s) => s.id != id && s.name == name.trim())) {
        return 'Ya existe una tienda con ese nombre.';
      }
      st.name = name.trim();
    }
    if (code != null && code != st.code) {
      final c = code.trim().toUpperCase();
      if (c.isEmpty) return 'El código es obligatorio.';
      if (state.stores.any((s) => s.id != id && s.code == c)) return 'Ya existe una tienda con ese código.';
      st.code = c;
    }
    if (apiKey != null) st.apiKey = apiKey;
    String? err;
    if (apiUrl != null) {
      st.apiUrl = apiUrl;
      final u = apiUrl.trim();
      if (u.isNotEmpty && !_urlRe.hasMatch(u)) err = 'La dirección API debe comenzar con http:// o https://';
    }
    if (active != null) {
      if (!active && st.isCentral) return 'El almacén central no se puede desactivar.';
      st.active = active;
    }
    _emit();
    return err;
  }

  String? deleteStore(String id) {
    final st = state.stores.firstWhereOrNull((s) => s.id == id);
    if (st == null) return null;
    if (st.isCentral) return 'El almacén central no se puede eliminar.';
    if (_hasStoreHistory(st)) return 'Tiene inventario o movimientos. Desactívala en su lugar.';
    state.stores.remove(st);
    state.bins.removeWhere((b) => b.storeId == id);
    _emit();
    return null;
  }

  /// Prueba la conexión real (HealthCheck) con la API de la tienda.
  Future<String> testStoreConnection(String id) async {
    final st = state.stores.firstWhereOrNull((s) => s.id == id);
    if (st == null) return 'Tienda no encontrada.';
    final u = st.apiUrl.trim();
    String res;
    if (u.isEmpty) {
      res = 'Sin dirección API configurada.';
    } else if (!_urlRe.hasMatch(u)) {
      res = 'Dirección inválida.';
    } else {
      try {
        res = await ref.read(rmApiFactoryProvider)(u).healthCheck();
      } on RmApiException catch (e) {
        res = e.message;
      }
    }
    st.lastCheck = res;
    _emit();
    return res;
  }

  // ---------- Administración: canastas ----------

  /// Agrega una canasta a un almacén. Devuelve error o null.
  String? addBin(String storeId, String code, {String zone = '', int? capacity}) {
    final c = code.trim().toUpperCase();
    if (c.isEmpty) return 'Ingresa el código de la canasta.';
    if (state.bins.any((b) => b.storeId == storeId && b.code == c)) {
      return 'La canasta $c ya existe en este almacén.';
    }
    state.bins.add(Bin(
      id: 'bn-${state.binSeq++}',
      storeId: storeId,
      code: c,
      zone: zone.trim(),
      capacity: capacity,
    ));
    _emit();
    return null;
  }

  bool binHasStock(Bin b) {
    final st = state.stores.firstWhereOrNull((s) => s.id == b.storeId);
    if (st == null) return false;
    return state.inventory.any((r) => r.store == st.name && r.bin == b.code && r.qty > 0);
  }

  String? updateBin(String id,
      {String? code, String? zone, int? capacity, bool clearCapacity = false, bool? active}) {
    final b = state.bins.firstWhereOrNull((x) => x.id == id);
    if (b == null) return 'Canasta no encontrada.';
    if (code != null && code.trim().toUpperCase() != b.code) {
      final c = code.trim().toUpperCase();
      if (b.special) return 'Esta canasta es de recepción y no se puede renombrar.';
      if (c.isEmpty) return 'El código es obligatorio.';
      if (state.bins.any((x) => x.id != id && x.storeId == b.storeId && x.code == c)) {
        return 'La canasta $c ya existe en este almacén.';
      }
      if (binHasStock(b)) return 'Tiene inventario; muévelo antes de renombrar.';
      b.code = c;
    }
    if (zone != null) b.zone = zone;
    if (clearCapacity) b.capacity = null;
    if (capacity != null) b.capacity = capacity;
    if (active != null) {
      if (!active && b.special) return 'Las canastas de recepción no se pueden desactivar.';
      if (!active && binHasStock(b)) return 'Tiene inventario; muévelo antes de desactivar.';
      b.active = active;
    }
    _emit();
    return null;
  }

  String? deleteBin(String id) {
    final b = state.bins.firstWhereOrNull((x) => x.id == id);
    if (b == null) return null;
    if (b.special) return 'Las canastas de recepción no se pueden eliminar.';
    if (binHasStock(b)) return 'Tiene inventario; muévelo antes de eliminar.';
    state.bins.remove(b);
    _emit();
    return null;
  }

  // ---------- Administración: roles y parámetros ----------

  void setRolePerm(String role, Area area, bool value) {
    if (role == 'Administrador' && area == Area.users) return;
    final cur = state.presetFor(role);
    cur[area] = value;
    state.rolePresets[role] = cur;
    _saveUsers();
    _emit();
  }

  void resetRolePreset(String role) {
    state.rolePresets[role] = rolePreset(role);
    _saveUsers();
    _emit();
  }

  /// Valida y guarda parámetros. Devuelve error o null.
  String? updateSettings({int? ageAlertDays, int? staleDays, String? companyName, String? warehouseName}) {
    final age = ageAlertDays ?? state.settings.ageAlertDays;
    final stale = staleDays ?? state.settings.staleDays;
    if (age < 1 || stale < 1) return 'Los días deben ser mayores que 0.';
    if (age >= stale) return 'La alerta de antigüedad debe ser menor que el umbral sin movimiento.';
    final s = state.settings;
    s.ageAlertDays = age;
    s.staleDays = stale;
    if (companyName != null) s.companyName = companyName;
    if (warehouseName != null) s.warehouseName = warehouseName;
    _emit();
    return null;
  }
}
