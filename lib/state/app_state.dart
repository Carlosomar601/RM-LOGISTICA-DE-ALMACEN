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
import '../models/audit.dart';
import '../models/inv_row.dart';
import '../models/json_util.dart';
import '../models/movement.dart';
import '../models/order.dart';
import '../models/pending_item.dart';
import '../models/pick_session.dart';
import '../models/product.dart';
import '../models/receipt.dart';
import '../models/store_transfer.dart';
import '../sync/dispatch_ledger.dart';
import '../sync/sync_settings.dart';
import '../util/clock.dart';
import '../util/format.dart';
import 'audit_engine.dart';
import 'pick_engine.dart';

enum AppView { dashboard, receiving, orders, picking, transfers, audit, history, users, about }

extension AppViewX on AppView {
  /// Área de permisos; null = siempre accesible.
  Area? get area => switch (this) {
        AppView.dashboard => Area.dashboard,
        AppView.receiving => Area.receiving,
        AppView.orders => Area.orders,
        AppView.picking => Area.picking,
        AppView.transfers => Area.transfers,
        AppView.audit => Area.audit,
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
        AppView.audit => 'Auditoría',
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
    List<Audit>? audits,
    List<PendingItem>? pendingItems,
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
    this.userSeq = 6,
    this.prefillSeq = 1,
    this.storeSeq = 4,
    this.binSeq = 1,
    this.productSeq = 11,
    this.auditSeq = 1,
    this.pendingSeq = 1,
  })  : audits = audits ?? [],
        pendingItems = pendingItems ?? [];

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
        'audits': [for (final x in audits) x.toJson()],
        'pendingItems': [for (final x in pendingItems) x.toJson()],
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
          'audit': auditSeq,
          'pending': pendingSeq,
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
      // Agregados después: un data.json anterior no los trae.
      audits: j['audits'] == null ? [] : [for (final x in jList(j, 'audits')) Audit.fromJson(x)],
      pendingItems:
          j['pendingItems'] == null ? [] : [for (final x in jList(j, 'pendingItems')) PendingItem.fromJson(x)],
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
      auditSeq: jIntOrNull(seq, 'audit') ?? 1,
      pendingSeq: jIntOrNull(seq, 'pending') ?? 1,
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
  final List<Audit> audits;
  final List<PendingItem> pendingItems;
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
  int orderSeq, receiptSeq, lotSeq, tbSeq, tsSeq, movementSeq, invSeq, stepSeq, userSeq, prefillSeq, storeSeq, binSeq, productSeq, auditSeq, pendingSeq;

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
        audits: audits,
        pendingItems: pendingItems,
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
        auditSeq: auditSeq,
        pendingSeq: pendingSeq,
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
    if (v == AppView.audit) return u.can(Area.audit) || u.can(Area.auditManage);
    return u.can(a);
  }

  /// Crea, cierra y revisa auditorías; resuelve PENDIENTES (Supervisor, Administrador).
  bool get canManageAudits {
    final u = simulatedUser ?? currentUser;
    return u == null || u.can(Area.auditManage);
  }

  // ---------- Auditoría y PENDIENTES ----------

  List<Audit> get openAudits => audits.where((a) => a.isOpen).toList();

  /// Auditorías abiertas que el usuario actual puede contar (las asignadas a otro no aparecen,
  /// salvo para quien administra auditorías).
  List<Audit> get auditsToCount {
    final me = currentUser;
    return openAudits
        .where((a) => a.assignedTo == null || me == null || a.assignedTo == me.id || canManageAudits)
        .toList();
  }

  /// Canastas del almacén central bloqueadas por una auditoría (contándose o contadas sin cerrar).
  Set<String> get lockedBins => {
        for (final a in audits)
          if (a.isOpen)
            for (final b in a.bins)
              if (b.locked) b.bin,
      };

  /// Auditoría que bloquea la canasta (null = libre).
  String? lockOf(String bin) {
    for (final a in audits) {
      if (!a.isOpen) continue;
      for (final b in a.bins) {
        if (b.bin == bin && b.locked) return a.id;
      }
    }
    return null;
  }

  /// Auditoría abierta que ya incluye la canasta (por contar, contando o contada).
  String? auditHolding(String bin) {
    for (final a in audits) {
      if (!a.isOpen) continue;
      for (final b in a.bins) {
        if (b.bin == bin &&
            (b.status == AuditBinStatus.pendiente || b.locked)) {
          return a.id;
        }
      }
    }
    return null;
  }

  /// Canastas del almacén central que se pueden auditar (activas, sin las de recepción).
  List<Bin> get auditableBins => bins
      .where((b) => b.storeId == centralStore.id && b.active && !b.special && b.code != centralStore.receiveBin)
      .toList();

  /// Zonas (pasillos) de las canastas auditables.
  List<String> get centralZones =>
      ({for (final b in auditableBins) if (b.zone.trim().isNotEmpty) b.zone.trim()}.toList()..sort());

  List<PendingItem> get openPending => pendingItems.where((p) => p.isOpen).toList();

  int get pendingUnits => openPending.fold(0, (a, p) => a + p.qty);

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

  Movement _mv(String type, String productId, int qty, String doc, String from, String to, {String? note}) =>
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
        note: note,
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
    final lock = _lockError([for (final (bin, _) in valid) bin]);
    if (lock != null) return lock;
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
        lockedBins: state.lockedBins,
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
      lockedBins: state.lockedBins,
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
      _pendingFromPick(res, o.id);
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
      lockedBins: state.lockedBins,
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
    _pendingFromPick(res, s.doc);
    state.pickSessions.remove(kSingleSessionKey);
    _emit();
    return res;
  }

  // ---------- Acciones sobre pasos ----------

  /// Error si el paso está en una canasta bloqueada por auditoría.
  String? _stepLocked(PickSession s, String stepId) {
    final st = s.steps.firstWhereOrNull((x) => x.id == stepId);
    final aud = st == null ? null : state.lockOf(st.bin);
    return aud == null ? null : 'La canasta ${st!.bin} está en auditoría ($aud). Recalcula la ruta.';
  }

  String? stepPicked(String key, String stepId) {
    final s = state.pickSessions[key];
    if (s == null) return null;
    final locked = _stepLocked(s, stepId);
    if (locked != null) return locked;
    markPicked(s, stepId);
    _emit();
    return null;
  }

  String? stepMissingHere(String key, String stepId) {
    final s = state.pickSessions[key];
    if (s == null) return null;
    final locked = _stepLocked(s, stepId);
    if (locked != null) return locked;
    markMissingHere(s, stepId, state.inventory, _stepId, lockedBins: state.lockedBins);
    _emit();
    return null;
  }

  void declareShortfall(String key) {
    final s = state.pickSessions[key];
    if (s == null) return;
    declareShortfallMissing(s, state.inventory, _stepId, lockedBins: state.lockedBins);
    _emit();
  }

  /// «No estaba aquí» del piqueo: lo apartado pasa a PENDIENTES con su lote y fecha.
  void _pendingFromPick(CommitResult res, String doc) {
    for (final o in res.pendingOut) {
      state.pendingItems.insert(
        0,
        PendingItem(
          id: _penId(),
          productId: o.productId,
          qty: o.qty,
          lot: o.lot,
          entryDate: o.entryDate,
          receipt: o.receipt,
          originBin: o.bin,
          sourceDoc: doc,
          reason: kPickMissingReason,
          createdAt: kToday,
          createdBy: state.actor,
        ),
      );
    }
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
    final lock = _lockError([src.bin, destBin]);
    if (lock != null) return lock;
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
    final locked = fromStore == kCentral ? state.lockedBins : const <String>{};
    final rows = fifoSorted(state.rowsOf(productId).where((r) => r.store == fromStore && !locked.contains(r.bin)));
    final avail = rows.fold(0, (a, r) => a + r.qty);
    if (qty < 1 || qty > avail) {
      final why = locked.isEmpty ? '' : ' (sin contar canastas en auditoría)';
      return (error: 'Cantidad inválida: $fromStore tiene $avail unidad(es) de este producto$why.', id: null);
    }
    var remaining = qty;
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

  /// Una canasta del almacén central incluida en una auditoría abierta no se edita.
  String? _binAdminLock(Bin b) {
    if (b.storeId != state.centralStore.id) return null;
    final aud = state.auditHolding(b.code);
    return aud == null ? null : 'La canasta ${b.code} está en la auditoría $aud.';
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
    final lock = _binAdminLock(b);
    if (lock != null && ((code != null && code.trim().toUpperCase() != b.code) || active == false)) return lock;
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
    final lock = _binAdminLock(b);
    if (lock != null) return lock;
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

  // ---------- Bloqueo por auditoría ----------

  /// Error si alguna de las canastas (del almacén central) está bloqueada por una auditoría.
  String? _lockError(Iterable<String> bins) {
    for (final b in bins) {
      final aud = state.lockOf(b);
      if (aud != null) return 'La canasta $b está en auditoría ($aud); espera a que se cierre.';
    }
    return null;
  }

  // ---------- Transferencia de canasta completa ----------

  /// Mueve todo lo que hay en [from] a [to] conservando lote, fecha y recibo de cada fila.
  /// Devuelve error o null.
  String? binTransferAll({required String from, required String to, String obs = ''}) {
    final src = from.trim().toUpperCase();
    final dst = to.trim().toUpperCase();
    final codes = state.centralBinCodes;
    if (!codes.contains(src)) return 'La canasta de origen $src no existe o está inactiva.';
    if (!codes.contains(dst)) return 'La canasta destino $dst no existe o está inactiva.';
    if (src == dst) return 'La canasta destino debe ser diferente a la de origen.';
    final lock = _lockError([src, dst]);
    if (lock != null) return lock;
    final rows = state.inventory.where((r) => r.store == kCentral && r.bin == src && r.qty > 0).toList();
    if (rows.isEmpty) return 'La canasta $src está vacía.';
    final byProduct = <String, int>{};
    for (final r in rows) {
      r.bin = dst;
      byProduct[r.productId] = (byProduct[r.productId] ?? 0) + r.qty;
    }
    final extra = obs.trim();
    final note = 'Canasta completa $src → $dst${extra.isEmpty ? '' : ' · $extra'}';
    for (final e in byProduct.entries) {
      final id = 'TB-${state.tbSeq++}';
      state.binTransfers.insert(
        0,
        BinTransfer(
          id: id,
          productId: e.key,
          qty: e.value,
          from: src,
          to: dst,
          user: state.actor,
          dateTime: kToday,
          obs: note,
        ),
      );
      _log(_mv('transfer-bin', e.key, e.value, id, '$kCentral / $src', '$kCentral / $dst', note: note));
    }
    _emit();
    return null;
  }

  // ---------- Auditoría de canastas ----------

  String _penId() => 'PEN-${state.pendingSeq++}';

  Audit? _findAudit(String id) => state.audits.firstWhereOrNull((a) => a.id == id);

  /// Crea una auditoría de una o varias canastas ([bins]) o de una zona completa ([zone]).
  ({String? error, String? id}) createAudit({List<String> bins = const [], String? zone, String? assignedTo}) {
    final auditable = {for (final b in state.auditableBins) b.code: b};
    final List<String> codes;
    final String scope;
    if (zone != null && zone.trim().isNotEmpty) {
      final z = zone.trim();
      codes = [for (final b in state.auditableBins) if (b.zone.trim() == z) b.code];
      if (codes.isEmpty) return (error: 'La zona $z no tiene canastas activas.', id: null);
      scope = 'Zona: $z';
    } else {
      codes = {for (final b in bins) b.trim().toUpperCase()}.where((b) => b.isNotEmpty).toList();
      if (codes.isEmpty) return (error: 'Elige al menos una canasta o una zona.', id: null);
      for (final c in codes) {
        if (!auditable.containsKey(c)) {
          return (error: 'La canasta $c no existe, está inactiva o es de recepción.', id: null);
        }
      }
      scope = codes.length == 1 ? 'Canasta ${codes.first}' : '${codes.length} canastas';
    }
    for (final c in codes) {
      final aud = state.auditHolding(c);
      if (aud != null) return (error: 'La canasta $c ya está en la auditoría $aud.', id: null);
    }
    if (assignedTo != null && !state.users.any((u) => u.id == assignedTo && u.active)) {
      return (error: 'El auditor elegido no existe o está inactivo.', id: null);
    }
    final id = 'AUD-${state.auditSeq++}';
    state.audits.insert(
      0,
      Audit(
        id: id,
        scopeLabel: scope,
        createdBy: state.actor,
        createdAt: kToday,
        assignedTo: assignedTo,
        bins: [for (final c in codes) AuditBin(bin: c, zone: auditable[c]!.zone)],
      ),
    );
    _emit();
    return (error: null, id: id);
  }

  /// El auditor escanea la canasta: queda bloqueada y se toma la foto de lo que el sistema tiene.
  String? startBinCount(String auditId, String scannedCode) {
    final a = _findAudit(auditId);
    if (a == null || !a.isOpen) return 'La auditoría no está abierta.';
    final me = state.currentUser;
    if (a.assignedTo != null && me != null && a.assignedTo != me.id && !state.canManageAudits) {
      final who = state.users.firstWhereOrNull((u) => u.id == a.assignedTo)?.name ?? 'otro auditor';
      return '${a.id} está asignada a $who.';
    }
    final code = scannedCode.trim().toUpperCase();
    final ab = a.binOf(code);
    if (ab == null) return 'La canasta $code no es parte de ${a.id}.';
    if (ab.status == AuditBinStatus.contando) {
      if (ab.auditor == state.actor) return null; // retoma su conteo
      return 'La canasta $code la está contando ${ab.auditor}.';
    }
    if (ab.status != AuditBinStatus.pendiente) return 'La canasta $code ya fue contada.';
    for (final s in state.pickSessions.values) {
      if (s.steps.any((st) => st.bin == code && st.status == StepStatus.picked)) {
        return 'Hay mercancía recogida de $code sin confirmar en ${s.doc}. Confirma ese piqueo primero.';
      }
    }
    final rows = fifoSorted(state.inventory.where((r) => r.store == kCentral && r.bin == code && r.qty > 0));
    ab.expected = [
      for (final r in rows)
        AuditExpected(
          invId: r.id,
          productId: r.productId,
          qty: r.qty,
          lot: r.lot,
          entryDate: r.entryDate,
          receipt: r.receipt,
        ),
    ];
    ab.status = AuditBinStatus.contando;
    ab.auditor = state.actor;
    ab.startedAt = kToday;
    a.status = AuditStatus.enCurso;
    _rerouteAround(code);
    _emit();
    return null;
  }

  /// Los pasos por recoger en una canasta recién bloqueada se recalculan hacia otras canastas.
  void _rerouteAround(String bin) {
    final locked = state.lockedBins;
    for (final s in state.pickSessions.values) {
      final before = s.steps.length;
      s.steps.removeWhere((st) => st.bin == bin && st.status == StepStatus.pending);
      if (s.steps.length != before) reflowSession(s, state.inventory, _stepId, lockedBins: locked);
    }
  }

  AuditBin? _countingBin(String auditId, String bin) {
    final ab = _findAudit(auditId)?.binOf(bin);
    if (ab == null || ab.status != AuditBinStatus.contando || ab.auditor != state.actor) return null;
    return ab;
  }

  Product? productByCode(String code) {
    final c = code.trim().toLowerCase();
    return state.products.firstWhereOrNull((p) => p.code.toLowerCase() == c);
  }

  /// Suma [qty] unidades del producto escaneado al conteo. Devuelve error o null.
  String? addCount(String auditId, String bin, String productCode, int qty) {
    final ab = _countingBin(auditId, bin);
    if (ab == null) return 'Escanea primero la canasta.';
    if (ab.recountIds != null) return 'El primer conteo ya terminó; completa el reconteo.';
    final p = productByCode(productCode);
    if (p == null) return 'No existe un producto con código «${productCode.trim()}».';
    if (qty < 1) return 'La cantidad debe ser mayor que 0.';
    ab.counts[p.id] = (ab.counts[p.id] ?? 0) + qty;
    _emit();
    return null;
  }

  /// Corrige la cantidad contada (0 = quitar la línea).
  String? setCount(String auditId, String bin, String productId, int qty) {
    final ab = _countingBin(auditId, bin);
    if (ab == null) return 'Escanea primero la canasta.';
    if (ab.recountIds != null) return 'El primer conteo ya terminó; completa el reconteo.';
    if (qty < 0) return 'La cantidad no puede ser negativa.';
    if (qty == 0) {
      ab.counts.remove(productId);
      ab.notes.remove(productId);
    } else {
      ab.counts[productId] = qty;
    }
    _emit();
    return null;
  }

  void setCountNote(String auditId, String bin, String productId, String note) {
    final ab = _countingBin(auditId, bin);
    if (ab == null) return;
    if (note.trim().isEmpty) {
      ab.notes.remove(productId);
    } else {
      ab.notes[productId] = note.trim();
    }
    _emit();
  }

  /// Termina el primer conteo. Devuelve los productos a recontar (vacío = la canasta quedó contada).
  ({String? error, List<String> recount}) finishBinCount(String auditId, String bin) {
    final ab = _countingBin(auditId, bin);
    if (ab == null) return (error: 'Escanea primero la canasta.', recount: const <String>[]);
    if (ab.recountIds != null) return (error: null, recount: ab.recountIds!);
    final diffs = diffProducts(ab);
    if (diffs.isEmpty) {
      _markCounted(ab);
    } else {
      ab.recountIds = diffs;
    }
    _emit();
    return (error: null, recount: diffs);
  }

  /// Reconteo (una sola vez) de las líneas que difieren. [values]: productId → unidades.
  /// Con [skip] se confirma el primer conteo sin recontar.
  String? submitRecount(String auditId, String bin, Map<String, int> values, {bool skip = false}) {
    final ab = _countingBin(auditId, bin);
    if (ab == null || ab.recountIds == null) return 'No hay reconteo pendiente en esta canasta.';
    if (!skip) {
      final r = <String, int>{};
      for (final id in ab.recountIds!) {
        final v = values[id];
        if (v == null || v < 0) return 'Ingresa la cantidad recontada de cada producto (0 si no está).';
        r[id] = v;
      }
      ab.recounts = r;
    }
    _markCounted(ab);
    _emit();
    return null;
  }

  void _markCounted(AuditBin ab) {
    ab.status = AuditBinStatus.contada;
    ab.countedAt = kToday;
    ab.lines = computeLines(ab);
  }

  AuditLine? _line(String auditId, String bin, String productId) {
    final ab = _findAudit(auditId)?.binOf(bin);
    if (ab == null || ab.status != AuditBinStatus.contada) return null;
    return ab.lines.firstWhereOrNull((l) => l.productId == productId);
  }

  void setLineReason(String auditId, String bin, String productId, String? reason, {String? note}) {
    final l = _line(auditId, bin, productId);
    if (l == null || l.isOk) return;
    l.reason = reason;
    final n = note?.trim() ?? '';
    l.reasonNote = n.isEmpty ? null : n;
    _emit();
  }

  /// Identifica un sobrante con un pendiente abierto del mismo producto (null = quitar).
  String? matchSurplusToPending(String auditId, String bin, String productId, String? pendingId) {
    final l = _line(auditId, bin, productId);
    if (l == null) return 'Línea no encontrada.';
    if (l.result != AuditResult.sobrante && l.result != AuditResult.noRegistrado) {
      return 'Solo un sobrante se puede identificar con un pendiente.';
    }
    if (pendingId != null) {
      final p = state.pendingItems.firstWhereOrNull((x) => x.id == pendingId);
      if (p == null || !p.isOpen || p.productId != productId) {
        return 'Ese pendiente no está abierto o es de otro producto.';
      }
    }
    l.matchedPendingId = pendingId;
    _emit();
    return null;
  }

  /// Cierra una canasta contada: aplica faltantes (a PENDIENTES) y sobrantes, y la desbloquea.
  String? closeAuditBin(String auditId, String bin) {
    final a = _findAudit(auditId);
    final ab = a?.binOf(bin);
    if (a == null || ab == null) return 'Canasta no encontrada.';
    final err = _closeBin(a, ab);
    if (err != null) return err;
    _finishAuditIfDone(a);
    _emit();
    return null;
  }

  String? _closeBin(Audit a, AuditBin ab) {
    if (ab.status != AuditBinStatus.contada) return 'La canasta ${ab.bin} todavía no está contada.';
    final ready = linesReadyToClose(ab.lines);
    if (ready != null) return '${ab.bin}: $ready';
    for (final l in ab.lines) {
      if (l.isOk) continue;
      final why = l.reason!;
      final note = [why, if (l.reasonNote != null) l.reasonNote!].join(' · ');
      if (l.diff < 0) {
        final portions = takeOldestFromBin(state.inventory, kCentral, ab.bin, l.productId, -l.diff);
        for (final p in portions) {
          final pen = PendingItem(
            id: _penId(),
            productId: l.productId,
            qty: p.qty,
            lot: p.lot,
            entryDate: p.entryDate,
            receipt: p.receipt,
            originBin: ab.bin,
            sourceDoc: a.id,
            reason: why,
            note: l.reasonNote,
            createdAt: kToday,
            createdBy: state.actor,
          );
          state.pendingItems.insert(0, pen);
          l.pendingIds.add(pen.id);
          _log(_mv('a-pendientes', l.productId, p.qty, a.id, '$kCentral / ${ab.bin}', kPendingArea, note: note));
        }
      } else {
        var extra = l.diff;
        final pen = l.matchedPendingId == null
            ? null
            : state.pendingItems.firstWhereOrNull((x) => x.id == l.matchedPendingId && x.isOpen);
        if (pen != null && pen.productId == l.productId) {
          final take = min(extra, pen.qty);
          _foundPending(pen, ab.bin, take, note: 'Encontrado en auditoría ${a.id}');
          extra -= take;
        }
        if (extra > 0) {
          state.inventory.add(InvRow(
            id: _invId(),
            productId: l.productId,
            store: kCentral,
            bin: ab.bin,
            qty: extra,
            entryDate: kToday,
            receipt: a.id,
            lot: '—',
            user: state.actor,
          ));
          _log(_mv('auditoria-sobrante', l.productId, extra, a.id, a.id, '$kCentral / ${ab.bin}', note: note));
        }
      }
    }
    ab.status = AuditBinStatus.cerrada;
    ab.closedAt = kToday;
    return null;
  }

  void _finishAuditIfDone(Audit a) {
    final done = a.bins.every((b) => b.status == AuditBinStatus.cerrada || b.status == AuditBinStatus.cancelada);
    if (!done) return;
    a.status = a.bins.any((b) => b.status == AuditBinStatus.cerrada) ? AuditStatus.cerrada : AuditStatus.cancelada;
    a.closedAt = kToday;
    a.closedBy = state.actor;
  }

  /// Cierra la auditoría: cierra las canastas contadas y cancela las que no se contaron.
  String? closeAudit(String auditId) {
    final a = _findAudit(auditId);
    if (a == null || !a.isOpen) return 'La auditoría no está abierta.';
    final counting = a.bins.where((b) => b.status == AuditBinStatus.contando).map((b) => b.bin).toList();
    if (counting.isNotEmpty) return 'Todavía se está contando: ${counting.join(', ')}.';
    for (final b in a.bins.where((b) => b.status == AuditBinStatus.contada)) {
      final ready = linesReadyToClose(b.lines);
      if (ready != null) return '${b.bin}: $ready';
    }
    for (final b in a.bins) {
      if (b.status == AuditBinStatus.contada) {
        _closeBin(a, b);
      } else if (b.status == AuditBinStatus.pendiente) {
        b.status = AuditBinStatus.cancelada;
      }
    }
    _finishAuditIfDone(a);
    _emit();
    return null;
  }

  /// Cancela la auditoría sin tocar el inventario (solo si ninguna canasta se cerró).
  String? cancelAudit(String auditId) {
    final a = _findAudit(auditId);
    if (a == null || !a.isOpen) return 'La auditoría no está abierta.';
    if (a.bins.any((b) => b.status == AuditBinStatus.cerrada)) {
      return 'Ya hay canastas cerradas; cierra la auditoría en lugar de cancelarla.';
    }
    for (final b in a.bins) {
      b.status = AuditBinStatus.cancelada;
    }
    a.status = AuditStatus.cancelada;
    a.closedAt = kToday;
    a.closedBy = state.actor;
    _emit();
    return null;
  }

  // ---------- PENDIENTES ----------

  /// Separa [qty] unidades de un pendiente: si es parte, crea un registro nuevo para esa parte.
  PendingItem _splitPending(PendingItem p, int qty) {
    if (qty >= p.qty) return p;
    p.qty -= qty;
    final part = PendingItem(
      id: _penId(),
      productId: p.productId,
      qty: qty,
      lot: p.lot,
      entryDate: p.entryDate,
      receipt: p.receipt,
      originBin: p.originBin,
      sourceDoc: p.sourceDoc,
      reason: p.reason,
      note: p.note,
      createdAt: p.createdAt,
      createdBy: p.createdBy,
    );
    state.pendingItems.insert(state.pendingItems.indexOf(p) + 1, part);
    return part;
  }

  void _foundPending(PendingItem p, String bin, int qty, {String? note}) {
    final part = _splitPending(p, qty);
    part.status = PendingStatus.encontrado;
    part.resolvedAt = kToday;
    part.resolvedBy = state.actor;
    part.foundBin = bin;
    part.resolutionNote = note;
    final same = state.inventory.firstWhereOrNull((r) =>
        r.store == kCentral &&
        r.bin == bin &&
        r.productId == part.productId &&
        r.lot == part.lot &&
        r.receipt == part.receipt &&
        r.entryDate == part.entryDate);
    if (same != null) {
      same.qty += qty;
    } else {
      state.inventory.add(InvRow(
        id: _invId(),
        productId: part.productId,
        store: kCentral,
        bin: bin,
        qty: qty,
        entryDate: part.entryDate,
        receipt: part.receipt,
        lot: part.lot,
        user: state.actor,
      ));
    }
    _log(_mv('pendiente-encontrado', part.productId, qty, part.id, kPendingArea, '$kCentral / $bin', note: note));
  }

  String? _checkPending(PendingItem? p, int qty) {
    if (p == null || !p.isOpen) return 'El pendiente ya no está abierto.';
    if (qty < 1 || qty > p.qty) return 'La cantidad debe estar entre 1 y ${p.qty}.';
    return null;
  }

  /// Encontrado: vuelve a una canasta con su lote y fecha originales.
  String? resolvePendingFound(String id, String bin, int qty) {
    final p = state.pendingItems.firstWhereOrNull((x) => x.id == id);
    final err = _checkPending(p, qty);
    if (err != null) return err;
    final code = bin.trim().toUpperCase();
    if (!state.centralBinCodes.contains(code)) return 'La canasta $code no existe o está inactiva.';
    final lock = _lockError([code]);
    if (lock != null) return lock;
    _foundPending(p!, code, qty);
    _emit();
    return null;
  }

  /// Da de baja un pendiente con su motivo.
  String? writeOffPending(String id, int qty, String reason, {String note = ''}) {
    final p = state.pendingItems.firstWhereOrNull((x) => x.id == id);
    final err = _checkPending(p, qty);
    if (err != null) return err;
    if (reason.trim().isEmpty) return 'Elige el motivo de la baja.';
    final n = note.trim();
    if (reason == kReasonOther && n.isEmpty) return 'El motivo «Otro» necesita una nota.';
    final part = _splitPending(p!, qty);
    part.status = PendingStatus.baja;
    part.resolvedAt = kToday;
    part.resolvedBy = state.actor;
    part.resolutionReason = reason;
    part.resolutionNote = n.isEmpty ? null : n;
    _log(_mv('baja', part.productId, qty, part.id, kPendingArea, 'Baja', note: [reason, if (n.isNotEmpty) n].join(' · ')));
    _emit();
    return null;
  }
}
