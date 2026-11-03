import 'dart:async';

import 'package:riverpod/riverpod.dart';

import '../api/rm_api.dart';
import '../models/app_user.dart';
import '../notify/toast_state.dart';
import '../state/app_state.dart';
import '../state/pick_engine.dart';
import '../util/clock.dart';
import 'commands.dart';
import 'protocol.dart';
import 'remote_link.dart';
import 'wire_state.dart';

/// Conexión con el servidor (null = la app trabaja sola con sus archivos locales).
final remoteLinkProvider = Provider<RemoteLink?>((ref) => null);

/// Estado de la conexión con el servidor, para la pantalla de conexión y el aviso de "sin conexión".
class ConnectionInfo {
  const ConnectionInfo({required this.status, this.serverName, this.hasData = false, this.error});
  final LinkStatus status;
  final String? serverName;

  /// Ya llegó al menos una vez el estado del servidor (o los datos públicos de la pantalla de PIN).
  final bool hasData;
  final String? error;

  bool get online => status == LinkStatus.online;
}

final connectionProvider = NotifierProvider<ConnectionNotifier, ConnectionInfo>(ConnectionNotifier.new);

class ConnectionNotifier extends Notifier<ConnectionInfo> {
  @override
  ConnectionInfo build() {
    final link = ref.watch(remoteLinkProvider);
    if (link == null) return const ConnectionInfo(status: LinkStatus.online, hasData: true);
    final sub = link.statusChanges.listen(
      (s) => state = ConnectionInfo(
        status: s,
        serverName: state.serverName,
        hasData: state.hasData,
        error: link.lastError,
      ),
    );
    final msgs = link.messages.listen((m) {
      if (m['t'] == Msg.hello) {
        state = ConnectionInfo(status: link.status, serverName: '${m['server'] ?? ''}', hasData: state.hasData);
      } else if (m['t'] == Msg.public || m['t'] == Msg.snapshot) {
        if (!state.hasData) {
          state = ConnectionInfo(status: link.status, serverName: state.serverName, hasData: true);
        }
      }
    });
    ref.onDispose(() {
      sub.cancel();
      msgs.cancel();
    });
    return ConnectionInfo(status: link.status, error: link.lastError);
  }
}

class _Pending {
  _Pending(this.id, this.name, this.args);
  final String id;
  final String name;
  final CmdArgs args;
  Completer<String?>? done;
}

/// [AppNotifier] de un dispositivo conectado al servidor.
///
/// Cada acción se aplica en seguida sobre la copia local (la pantalla responde al instante)
/// y se manda al servidor, que es el único que guarda. Cuando el servidor responde, la copia
/// local se reemplaza por su estado y se vuelven a aplicar encima las acciones que aún no
/// confirmó. Si el servidor rechaza una acción (por ejemplo, otro piqueador tomó ese lote),
/// el cambio local se deshace y se avisa con un mensaje.
class RemoteAppNotifier extends AppNotifier {
  RemoteLink get _link => ref.read(remoteLinkProvider)!;

  /// Último estado recibido del servidor, por colección.
  final Map<String, dynamic> _wire = {};
  int _version = -1;
  bool _hasSnapshot = false;
  String? _token;
  final List<_Pending> _pending = [];
  bool _replaying = false;
  DateTime? _lockedUntil;
  final List<StreamSubscription> _subs = [];

  /// Acciones enviadas que el servidor aún no confirmó (para pruebas y el aviso de "guardando").
  int get pendingCount => _pending.length;

  /// Versión del estado del servidor aplicada en este dispositivo.
  int get serverVersion => _version;

  @override
  AppState build() {
    final link = _link;
    _subs
      ..add(link.messages.listen(_onMessage))
      ..add(
        link.statusChanges.listen((s) {
          if (s == LinkStatus.online) _onOnline();
        }),
      );
    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
    });
    return AppState.empty();
  }

  // ---------- Mensajes del servidor ----------

  void _onMessage(Map<String, dynamic> m) {
    switch (m['t']) {
      case Msg.hello:
        demoMode = m['demo'] == true;
      case Msg.public:
        if (!_hasSnapshot) {
          final s = decodePublicState(Map<String, dynamic>.from(m['data'] as Map));
          copySessionFields(state, s);
          state = s;
        }
      case Msg.snapshot:
        _wire
          ..clear()
          ..addAll(Map<String, dynamic>.from(m['data'] as Map));
        _version = (m['v'] as num).toInt();
        _hasSnapshot = true;
        _rebuild();
      case Msg.patch:
        if (!_hasSnapshot) return;
        _wire.addAll(Map<String, dynamic>.from(m['data'] as Map));
        _version = (m['v'] as num).toInt();
        final ack = m['ack'];
        if (ack != null) _pending.removeWhere((p) => p.id == ack);
        _rebuild();
      case Msg.result:
        final id = m['id'];
        final error = m['error'] as String?;
        final i = _pending.indexWhere((p) => p.id == id);
        _Pending? p;
        if (i >= 0) p = _pending.removeAt(i);
        p?.done?.complete(error);
        if (error != null && p?.done == null) ref.read(toastProvider.notifier).show('No se aplicó: $error');
        if (p != null || error != null) _rebuild();
      case Msg.kicked:
        _endSession('${m['reason'] ?? 'El servidor cerró la sesión.'}');
      case Msg.toast:
        ref.read(toastProvider.notifier).show('${m['text']}');
    }
  }

  /// Al (re)conectar: si había sesión, se retoma sin pedir el PIN y se reenvía lo pendiente.
  Future<void> _onOnline() async {
    final token = _token;
    if (token == null) return;
    try {
      final r = await _link.request({'t': Msg.resume, 'token': token});
      if (r['ok'] == true) {
        for (final p in List.of(_pending)) {
          _link.send({'t': Msg.cmd, 'id': p.id, 'name': p.name, 'args': p.args, 'base': _version});
        }
      } else {
        _endSession('El servidor cerró la sesión. Entra con tu PIN.');
      }
    } on RemoteOfflineException {
      // Se volverá a intentar al reconectar.
    }
  }

  void _endSession(String reason) {
    _token = null;
    for (final p in _pending) {
      p.done?.complete('Sin conexión con el servidor.');
    }
    _pending.clear();
    _hasSnapshot = false;
    _wire.clear();
    final s = AppState.empty()
      ..settings.companyName = state.settings.companyName
      ..settings.warehouseName = state.settings.warehouseName
      ..logoutReason = reason;
    state = s;
  }

  /// Copia local = estado del servidor + acciones aún sin confirmar.
  void _rebuild() {
    if (!_hasSnapshot) return;
    final AppState s;
    try {
      s = decodeWireState(_wire);
    } catch (e) {
      ref.read(toastProvider.notifier).show('Datos del servidor ilegibles: $e');
      return;
    }
    copySessionFields(state, s);
    if (s.currentUserId != null && s.currentUser == null) {
      // El usuario fue borrado en otro dispositivo.
      s
        ..currentUserId = null
        ..logoutReason = 'Tu usuario ya no existe. Avisa al administrador.';
    }
    state = s;
    if (_pending.isNotEmpty) {
      _replaying = true;
      try {
        for (final p in _pending) {
          try {
            kRemoteCommands[p.name]!.run(this, p.args);
          } catch (_) {}
        }
      } finally {
        _replaying = false;
      }
    }
    ensureViewAllowed();
    state = state.clone();
  }

  // ---------- Acciones ----------

  /// Aplica [local] ya y, si no dio error, manda la acción al servidor.
  T _cmd<T>(String name, CmdArgs args, T Function() local, {Completer<String?>? done}) {
    if (_replaying) return local();
    final r = local();
    final err = kRemoteCommands[name]!.errorOf(r);
    if (err != null) {
      done?.complete(err);
      return r;
    }
    final p = _Pending(_link.nextId(), name, args)..done = done;
    _pending.add(p);
    _link.send({'t': Msg.cmd, 'id': p.id, 'name': name, 'args': args, 'base': _version});
    return r;
  }

  Future<Object?> _rpc(String name, CmdArgs args) async {
    final r = await _link.request({'t': Msg.rpc, 'name': name, 'args': args});
    final error = r['error'];
    if (error != null) throw RmApiException('$error', notAvailable: r['notAvailable'] == true);
    return r['result'];
  }

  // ---------- Sesión ----------

  @override
  Future<String?> loginAsync(String pin) async {
    if (!_link.online) return 'Sin conexión con el servidor.';
    final Map<String, dynamic> r;
    try {
      r = await _link.request({'t': Msg.login, 'pin': pin, 'device': _link.device});
    } on RemoteOfflineException catch (e) {
      return e.message;
    }
    if (r['ok'] != true) {
      final secs = (r['lockSeconds'] as num?)?.toInt() ?? 0;
      _lockedUntil = secs > 0 ? DateTime.now().add(Duration(seconds: secs)) : null;
      return '${r['error'] ?? 'No se pudo iniciar sesión.'}';
    }
    _lockedUntil = null;
    _token = r['token'] as String?;
    state
      ..currentUserId = r['userId'] as String?
      ..simulatedUserId = null
      ..logoutReason = null;
    _rebuild();
    return null;
  }

  @override
  String? login(String pin, {PinThrottle? throttle}) => 'Inicia sesión con el servidor (loginAsync).';

  @override
  int lockSecondsLeft({PinThrottle? throttle}) {
    final until = _lockedUntil;
    if (until == null) return 0;
    final left = until.difference(DateTime.now()).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }

  @override
  void logout({String? reason}) {
    if (state.currentUser == null) return;
    _link.send({'t': Msg.logout, 'reason': reason});
    _endSession(reason == null ? '' : 'Sesión cerrada por $reason.');
    if (reason == null) state.logoutReason = null;
    state = state.clone();
  }

  @override
  Future<bool> confirmPin(String pin) async {
    try {
      return await _rpc('confirmPin', {'pin': pin}) == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> setPinAsync(String userId, String pin) {
    final done = Completer<String?>();
    _cmd('setPin', {'userId': userId, 'pin': pin}, () => super.setPin(userId, pin), done: done);
    return done.future;
  }

  // ---------- Consultas al servidor ----------

  @override
  Future<List<RmReceiptLine>> fetchReceiptLines(String storeId, DateTime from, DateTime to) async {
    final r = await _rpc('fetchReceiptLines', {
      'storeId': storeId,
      'from': from.toIso8601String(),
      'to': to.toIso8601String(),
    });
    return [for (final l in r as List) RmReceiptLine.fromJson(Map<String, dynamic>.from(l as Map))];
  }

  @override
  Future<String> testStoreConnection(String id) async {
    try {
      return '${await _rpc('testStoreConnection', {'id': id})}';
    } on RemoteOfflineException catch (e) {
      return e.message;
    }
  }

  // ---------- Recibido sin ubicar ----------

  @override
  String simulateReceipt() => _cmd('simulateReceipt', {}, super.simulateReceipt);

  @override
  String? allocateReceiptItem(String receiptId, String productId, List<(String, int)> rows) =>
      _cmd('allocateReceiptItem', {
        'receiptId': receiptId,
        'productId': productId,
        'rows': [
          for (final (bin, qty) in rows) [bin, qty],
        ],
      }, () => super.allocateReceiptItem(receiptId, productId, rows));

  @override
  ImportResult importReceiptLines(String storeId, List<RmReceiptLine> lines) => _cmd('importReceiptLines', {
    'storeId': storeId,
    'lines': [for (final l in lines) l.toJson()],
  }, () => super.importReceiptLines(storeId, lines));

  // ---------- Órdenes ----------

  @override
  String simulateOrder() => _cmd('simulateOrder', {}, super.simulateOrder);

  @override
  void setOrderCategoryFilter(Set<String> labels) =>
      _cmd('setOrderCategoryFilter', {'labels': labels.toList()}, () => super.setOrderCategoryFilter(labels));

  @override
  void setOrderPriceLevelFilter(Set<String> labels) =>
      _cmd('setOrderPriceLevelFilter', {'labels': labels.toList()}, () => super.setOrderPriceLevelFilter(labels));

  @override
  void calcOrderRoute(String orderId) =>
      _cmd('calcOrderRoute', {'orderId': orderId}, () => super.calcOrderRoute(orderId));

  @override
  void recalcSession(String key) => _cmd('recalcSession', {'key': key}, () => super.recalcSession(key));

  @override
  bool? confirmOrder(String orderId) => _cmd('confirmOrder', {'orderId': orderId}, () => super.confirmOrder(orderId));

  // ---------- Piqueo ----------

  @override
  void suggestSingle(String productId, int qty, String doc) => _cmd('suggestSingle', {
    'productId': productId,
    'qty': qty,
    'doc': doc,
  }, () => super.suggestSingle(productId, qty, doc));

  @override
  void cancelSingle() => _cmd('cancelSingle', {}, super.cancelSingle);

  @override
  CommitResult? confirmSingle() => _cmd('confirmSingle', {}, super.confirmSingle);

  @override
  String? stepPicked(String key, String stepId) =>
      _cmd('stepPicked', {'key': key, 'stepId': stepId}, () => super.stepPicked(key, stepId));

  @override
  String? stepMissingHere(String key, String stepId) =>
      _cmd('stepMissingHere', {'key': key, 'stepId': stepId}, () => super.stepMissingHere(key, stepId));

  @override
  void declareShortfall(String key) => _cmd('declareShortfall', {'key': key}, () => super.declareShortfall(key));

  // ---------- Transferencias ----------

  @override
  String? binTransfer({
    required String productId,
    required String? srcRowId,
    required String destBin,
    required int qty,
    String obs = '',
  }) => _cmd('binTransfer', {
    'productId': productId,
    'srcRowId': srcRowId,
    'destBin': destBin,
    'qty': qty,
    'obs': obs,
  }, () => super.binTransfer(productId: productId, srcRowId: srcRowId, destBin: destBin, qty: qty, obs: obs));

  @override
  String? binTransferAll({required String from, required String to, String obs = ''}) => _cmd('binTransferAll', {
    'from': from,
    'to': to,
    'obs': obs,
  }, () => super.binTransferAll(from: from, to: to, obs: obs));

  @override
  ({String? error, String? id}) storeTransferSend({
    required String productId,
    required String fromStore,
    required String toStore,
    required int qty,
  }) => _cmd('storeTransferSend', {
    'productId': productId,
    'fromStore': fromStore,
    'toStore': toStore,
    'qty': qty,
  }, () => super.storeTransferSend(productId: productId, fromStore: fromStore, toStore: toStore, qty: qty));

  @override
  void storeTransferConfirm(String id) =>
      _cmd('storeTransferConfirm', {'id': id}, () => super.storeTransferConfirm(id));

  // ---------- Usuarios ----------

  @override
  String? setPin(String userId, String pin) =>
      _cmd('setPin', {'userId': userId, 'pin': pin}, () => super.setPin(userId, pin));

  @override
  String? clearPin(String userId) => _cmd('clearPin', {'userId': userId}, () => super.clearPin(userId));

  @override
  void setAutoLogoutMinutes(int minutes) =>
      _cmd('setAutoLogoutMinutes', {'minutes': minutes}, () => super.setAutoLogoutMinutes(minutes));

  @override
  String addUser() => _cmd('addUser', {}, super.addUser);

  @override
  void updateUser(String id, {String? name, String? email, String? role, bool? active}) => _cmd('updateUser', {
    'id': id,
    'name': name,
    'email': email,
    'role': role,
    'active': active,
  }, () => super.updateUser(id, name: name, email: email, role: role, active: active));

  @override
  void applyRolePreset(String id) => _cmd('applyRolePreset', {'id': id}, () => super.applyRolePreset(id));

  @override
  void setPerm(String id, Area area, bool value) =>
      _cmd('setPerm', {'id': id, 'area': area.name, 'value': value}, () => super.setPerm(id, area, value));

  @override
  void deleteUser(String id) => _cmd('deleteUser', {'id': id}, () => super.deleteUser(id));

  // ---------- Administración ----------

  @override
  String addStore() => _cmd('addStore', {}, super.addStore);

  @override
  String? updateStore(String id, {String? name, String? code, String? apiUrl, String? apiKey, bool? active}) => _cmd(
    'updateStore',
    {'id': id, 'name': name, 'code': code, 'apiUrl': apiUrl, 'apiKey': apiKey, 'active': active},
    () => super.updateStore(id, name: name, code: code, apiUrl: apiUrl, apiKey: apiKey, active: active),
  );

  @override
  String? deleteStore(String id) => _cmd('deleteStore', {'id': id}, () => super.deleteStore(id));

  @override
  String? addBin(String storeId, String code, {String zone = '', int? capacity}) => _cmd('addBin', {
    'storeId': storeId,
    'code': code,
    'zone': zone,
    'capacity': capacity,
  }, () => super.addBin(storeId, code, zone: zone, capacity: capacity));

  @override
  String? updateBin(String id, {String? code, String? zone, int? capacity, bool clearCapacity = false, bool? active}) =>
      _cmd(
        'updateBin',
        {'id': id, 'code': code, 'zone': zone, 'capacity': capacity, 'clearCapacity': clearCapacity, 'active': active},
        () => super.updateBin(
          id,
          code: code,
          zone: zone,
          capacity: capacity,
          clearCapacity: clearCapacity,
          active: active,
        ),
      );

  @override
  String? deleteBin(String id) => _cmd('deleteBin', {'id': id}, () => super.deleteBin(id));

  @override
  void setRolePerm(String role, Area area, bool value) => _cmd('setRolePerm', {
    'role': role,
    'area': area.name,
    'value': value,
  }, () => super.setRolePerm(role, area, value));

  @override
  void resetRolePreset(String role) => _cmd('resetRolePreset', {'role': role}, () => super.resetRolePreset(role));

  @override
  String? updateSettings({int? ageAlertDays, int? staleDays, String? companyName, String? warehouseName}) => _cmd(
    'updateSettings',
    {'ageAlertDays': ageAlertDays, 'staleDays': staleDays, 'companyName': companyName, 'warehouseName': warehouseName},
    () => super.updateSettings(
      ageAlertDays: ageAlertDays,
      staleDays: staleDays,
      companyName: companyName,
      warehouseName: warehouseName,
    ),
  );

  @override
  void startFresh() => _cmd('startFresh', {}, super.startFresh);

  // ---------- Auditoría: contar ----------

  @override
  String? startBinCount(String auditId, String scannedCode) => _cmd('startBinCount', {
    'auditId': auditId,
    'scannedCode': scannedCode,
  }, () => super.startBinCount(auditId, scannedCode));

  @override
  String? addCount(String auditId, String bin, String productCode, int qty) => _cmd('addCount', {
    'auditId': auditId,
    'bin': bin,
    'productCode': productCode,
    'qty': qty,
  }, () => super.addCount(auditId, bin, productCode, qty));

  @override
  String? setCount(String auditId, String bin, String productId, int qty) => _cmd('setCount', {
    'auditId': auditId,
    'bin': bin,
    'productId': productId,
    'qty': qty,
  }, () => super.setCount(auditId, bin, productId, qty));

  @override
  void setCountNote(String auditId, String bin, String productId, String note) => _cmd('setCountNote', {
    'auditId': auditId,
    'bin': bin,
    'productId': productId,
    'note': note,
  }, () => super.setCountNote(auditId, bin, productId, note));

  @override
  ({String? error, List<String> recount}) finishBinCount(String auditId, String bin) =>
      _cmd('finishBinCount', {'auditId': auditId, 'bin': bin}, () => super.finishBinCount(auditId, bin));

  @override
  String? submitRecount(String auditId, String bin, Map<String, int> values, {bool skip = false}) => _cmd(
    'submitRecount',
    {'auditId': auditId, 'bin': bin, 'values': values, 'skip': skip},
    () => super.submitRecount(auditId, bin, values, skip: skip),
  );

  // ---------- Auditoría: gestionar ----------

  @override
  ({String? error, String? id}) createAudit({List<String> bins = const [], String? zone, String? assignedTo}) => _cmd(
    'createAudit',
    {'bins': bins, 'zone': zone, 'assignedTo': assignedTo},
    () => super.createAudit(bins: bins, zone: zone, assignedTo: assignedTo),
  );

  @override
  void setLineReason(String auditId, String bin, String productId, String? reason, {String? note}) => _cmd(
    'setLineReason',
    {'auditId': auditId, 'bin': bin, 'productId': productId, 'reason': reason, 'note': note},
    () => super.setLineReason(auditId, bin, productId, reason, note: note),
  );

  @override
  String? matchSurplusToPending(String auditId, String bin, String productId, String? pendingId) => _cmd(
    'matchSurplusToPending',
    {'auditId': auditId, 'bin': bin, 'productId': productId, 'pendingId': pendingId},
    () => super.matchSurplusToPending(auditId, bin, productId, pendingId),
  );

  @override
  String? closeAuditBin(String auditId, String bin) =>
      _cmd('closeAuditBin', {'auditId': auditId, 'bin': bin}, () => super.closeAuditBin(auditId, bin));

  @override
  String? closeAudit(String auditId) => _cmd('closeAudit', {'auditId': auditId}, () => super.closeAudit(auditId));

  @override
  String? cancelAudit(String auditId) => _cmd('cancelAudit', {'auditId': auditId}, () => super.cancelAudit(auditId));

  @override
  String? resolvePendingFound(String id, String bin, int qty) =>
      _cmd('resolvePendingFound', {'id': id, 'bin': bin, 'qty': qty}, () => super.resolvePendingFound(id, bin, qty));

  @override
  String? writeOffPending(String id, int qty, String reason, {String note = ''}) => _cmd('writeOffPending', {
    'id': id,
    'qty': qty,
    'reason': reason,
    'note': note,
  }, () => super.writeOffPending(id, qty, reason, note: note));
}
