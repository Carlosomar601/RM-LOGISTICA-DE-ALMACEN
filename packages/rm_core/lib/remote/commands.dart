import '../api/rm_api.dart';
import '../models/app_user.dart';
import '../state/app_state.dart';

typedef CmdArgs = Map<String, dynamic>;

/// Una acción que cambia datos compartidos. El servidor la ejecuta con el usuario del
/// dispositivo; el cliente la vuelve a aplicar localmente mientras espera la respuesta.
class RemoteCommand {
  const RemoteCommand(this.run, {this.can = _anyUser, this.errorOf = _noError, this.createsId = false});

  /// Ejecuta la acción sobre el notifier con los argumentos decodificados.
  final Object? Function(AppNotifier n, CmdArgs a) run;

  /// Permiso: el servidor rechaza la acción si el usuario no lo tiene.
  final bool Function(AppUser user, CmdArgs a) can;

  /// Error de negocio en el resultado (null = se aplicó).
  final String? Function(Object? result) errorOf;

  /// Devuelve un ID nuevo que la pantalla usa enseguida: si otro dispositivo cambió los datos
  /// entre medio, el servidor la rechaza en vez de asignar un ID distinto al previsto.
  final bool createsId;
}

bool _anyUser(AppUser u, CmdArgs a) => true;
bool Function(AppUser, CmdArgs) _area(Area x) =>
    (u, a) => u.can(x);
bool Function(AppUser, CmdArgs) _anyOf(List<Area> xs) =>
    (u, a) => xs.any(u.can);

String? _noError(Object? r) => null;
String? _str(Object? r) => r as String?;
String? Function(Object?) _nullMeans(String msg) =>
    (r) => r == null ? msg : null;

String _s(CmdArgs a, String k) => '${a[k]}';
String? _sn(CmdArgs a, String k) => a[k] as String?;
int _i(CmdArgs a, String k) => (a[k] as num).toInt();
int? _in(CmdArgs a, String k) => (a[k] as num?)?.toInt();
bool? _bn(CmdArgs a, String k) => a[k] as bool?;
List<String> _ls(CmdArgs a, String k) => [for (final x in (a[k] as List? ?? const [])) '$x'];
Area _area_(CmdArgs a, String k) => Area.values.byName(_s(a, k));

const _users = Area.users;
final _picking = _anyOf([Area.orders, Area.picking]);
final _counting = _anyOf([Area.audit, Area.auditManage]);

/// Todas las acciones remotas por nombre. El nombre coincide con el método de [AppNotifier].
final Map<String, RemoteCommand> kRemoteCommands = {
  // ---------- Recibido sin ubicar ----------
  'simulateReceipt': RemoteCommand((n, a) => n.simulateReceipt(), can: _area(Area.receiving), createsId: true),
  'allocateReceiptItem': RemoteCommand(
    (n, a) => n.allocateReceiptItem(_s(a, 'receiptId'), _s(a, 'productId'), [
      for (final r in a['rows'] as List) ('${(r as List)[0]}', (r[1] as num).toInt()),
    ]),
    can: _area(Area.receiving),
    errorOf: _str,
  ),
  'importReceiptLines': RemoteCommand(
    (n, a) => n.importReceiptLines(_s(a, 'storeId'), [
      for (final l in a['lines'] as List) RmReceiptLine.fromJson(Map<String, dynamic>.from(l as Map)),
    ]),
    can: _area(Area.receiving),
  ),

  // ---------- Órdenes entrantes ----------
  'simulateOrder': RemoteCommand((n, a) => n.simulateOrder(), can: _area(Area.orders), createsId: true),
  'setOrderCategoryFilter': RemoteCommand((n, a) => n.setOrderCategoryFilter(_ls(a, 'labels').toSet())),
  'setOrderPriceLevelFilter': RemoteCommand((n, a) => n.setOrderPriceLevelFilter(_ls(a, 'labels').toSet())),
  'calcOrderRoute': RemoteCommand((n, a) => n.calcOrderRoute(_s(a, 'orderId')), can: _picking),
  'recalcSession': RemoteCommand((n, a) => n.recalcSession(_s(a, 'key')), can: _picking),
  'confirmOrder': RemoteCommand(
    (n, a) => n.confirmOrder(_s(a, 'orderId')),
    can: _picking,
    errorOf: _nullMeans('La orden ya no se puede confirmar: otro dispositivo cambió el inventario.'),
  ),

  // ---------- Piqueo FIFO ----------
  'suggestSingle': RemoteCommand(
    (n, a) => n.suggestSingle(_s(a, 'productId'), _i(a, 'qty'), _s(a, 'doc')),
    can: _picking,
  ),
  'cancelSingle': RemoteCommand((n, a) => n.cancelSingle(), can: _picking),
  'confirmSingle': RemoteCommand(
    (n, a) => n.confirmSingle(),
    can: _picking,
    errorOf: _nullMeans('El piqueo ya no se puede confirmar: otro dispositivo cambió el inventario.'),
  ),
  'stepPicked': RemoteCommand((n, a) => n.stepPicked(_s(a, 'key'), _s(a, 'stepId')), can: _picking, errorOf: _str),
  'stepMissingHere': RemoteCommand(
    (n, a) => n.stepMissingHere(_s(a, 'key'), _s(a, 'stepId')),
    can: _picking,
    errorOf: _str,
  ),
  'declareShortfall': RemoteCommand((n, a) => n.declareShortfall(_s(a, 'key')), can: _picking),

  // ---------- Transferencias ----------
  'binTransfer': RemoteCommand(
    (n, a) => n.binTransfer(
      productId: _s(a, 'productId'),
      srcRowId: _sn(a, 'srcRowId'),
      destBin: _s(a, 'destBin'),
      qty: _i(a, 'qty'),
      obs: _sn(a, 'obs') ?? '',
    ),
    can: _area(Area.transfers),
    errorOf: _str,
  ),
  'binTransferAll': RemoteCommand(
    (n, a) => n.binTransferAll(from: _s(a, 'from'), to: _s(a, 'to'), obs: _sn(a, 'obs') ?? ''),
    can: _area(Area.transfers),
    errorOf: _str,
  ),
  'storeTransferSend': RemoteCommand(
    (n, a) => n.storeTransferSend(
      productId: _s(a, 'productId'),
      fromStore: _s(a, 'fromStore'),
      toStore: _s(a, 'toStore'),
      qty: _i(a, 'qty'),
    ),
    can: _area(Area.transfers),
    errorOf: (r) => (r as ({String? error, String? id})).error,
    createsId: true,
  ),
  'storeTransferConfirm': RemoteCommand((n, a) => n.storeTransferConfirm(_s(a, 'id')), can: _area(Area.transfers)),

  // ---------- Usuarios y PIN ----------
  'setPin': RemoteCommand(
    (n, a) => n.setPin(_s(a, 'userId'), _s(a, 'pin')),
    can: (u, a) => u.id == a['userId'] || u.can(_users),
    errorOf: _str,
  ),
  'clearPin': RemoteCommand((n, a) => n.clearPin(_s(a, 'userId')), can: _area(_users), errorOf: _str),
  'setAutoLogoutMinutes': RemoteCommand((n, a) => n.setAutoLogoutMinutes(_i(a, 'minutes')), can: _area(_users)),
  'addUser': RemoteCommand((n, a) => n.addUser(), can: _area(_users), createsId: true),
  'updateUser': RemoteCommand(
    (n, a) => n.updateUser(
      _s(a, 'id'),
      name: _sn(a, 'name'),
      email: _sn(a, 'email'),
      role: _sn(a, 'role'),
      active: _bn(a, 'active'),
    ),
    can: _area(_users),
  ),
  'applyRolePreset': RemoteCommand((n, a) => n.applyRolePreset(_s(a, 'id')), can: _area(_users)),
  'setPerm': RemoteCommand((n, a) => n.setPerm(_s(a, 'id'), _area_(a, 'area'), a['value'] == true), can: _area(_users)),
  'deleteUser': RemoteCommand((n, a) => n.deleteUser(_s(a, 'id')), can: _area(_users)),

  // ---------- Administración: tiendas, canastas, roles, parámetros ----------
  'addStore': RemoteCommand((n, a) => n.addStore(), can: _area(_users), createsId: true),
  'updateStore': RemoteCommand(
    (n, a) => n.updateStore(
      _s(a, 'id'),
      name: _sn(a, 'name'),
      code: _sn(a, 'code'),
      apiUrl: _sn(a, 'apiUrl'),
      apiKey: _sn(a, 'apiKey'),
      active: _bn(a, 'active'),
    ),
    can: _area(_users),
    errorOf: _str,
  ),
  'deleteStore': RemoteCommand((n, a) => n.deleteStore(_s(a, 'id')), can: _area(_users), errorOf: _str),
  'addBin': RemoteCommand(
    (n, a) => n.addBin(_s(a, 'storeId'), _s(a, 'code'), zone: _sn(a, 'zone') ?? '', capacity: _in(a, 'capacity')),
    can: _area(_users),
    errorOf: _str,
  ),
  'updateBin': RemoteCommand(
    (n, a) => n.updateBin(
      _s(a, 'id'),
      code: _sn(a, 'code'),
      zone: _sn(a, 'zone'),
      capacity: _in(a, 'capacity'),
      clearCapacity: a['clearCapacity'] == true,
      active: _bn(a, 'active'),
    ),
    can: _area(_users),
    errorOf: _str,
  ),
  'deleteBin': RemoteCommand((n, a) => n.deleteBin(_s(a, 'id')), can: _area(_users), errorOf: _str),
  'setRolePerm': RemoteCommand(
    (n, a) => n.setRolePerm(_s(a, 'role'), _area_(a, 'area'), a['value'] == true),
    can: _area(_users),
  ),
  'resetRolePreset': RemoteCommand((n, a) => n.resetRolePreset(_s(a, 'role')), can: _area(_users)),
  'updateSettings': RemoteCommand(
    (n, a) => n.updateSettings(
      ageAlertDays: _in(a, 'ageAlertDays'),
      staleDays: _in(a, 'staleDays'),
      companyName: _sn(a, 'companyName'),
      warehouseName: _sn(a, 'warehouseName'),
    ),
    can: _area(_users),
    errorOf: _str,
  ),
  'startFresh': RemoteCommand((n, a) => n.startFresh(), can: _area(_users)),

  // ---------- Auditoría: contar ----------
  'startBinCount': RemoteCommand(
    (n, a) => n.startBinCount(_s(a, 'auditId'), _s(a, 'scannedCode')),
    can: _counting,
    errorOf: _str,
  ),
  'addCount': RemoteCommand(
    (n, a) => n.addCount(_s(a, 'auditId'), _s(a, 'bin'), _s(a, 'productCode'), _i(a, 'qty')),
    can: _counting,
    errorOf: _str,
  ),
  'setCount': RemoteCommand(
    (n, a) => n.setCount(_s(a, 'auditId'), _s(a, 'bin'), _s(a, 'productId'), _i(a, 'qty')),
    can: _counting,
    errorOf: _str,
  ),
  'setCountNote': RemoteCommand(
    (n, a) => n.setCountNote(_s(a, 'auditId'), _s(a, 'bin'), _s(a, 'productId'), _s(a, 'note')),
    can: _counting,
  ),
  'finishBinCount': RemoteCommand(
    (n, a) => n.finishBinCount(_s(a, 'auditId'), _s(a, 'bin')),
    can: _counting,
    errorOf: (r) => (r as ({String? error, List<String> recount})).error,
  ),
  'submitRecount': RemoteCommand(
    (n, a) => n.submitRecount(_s(a, 'auditId'), _s(a, 'bin'), {
      for (final e in (a['values'] as Map).entries) '${e.key}': (e.value as num).toInt(),
    }, skip: a['skip'] == true),
    can: _counting,
    errorOf: _str,
  ),

  // ---------- Auditoría: crear, cerrar, pendientes ----------
  'createAudit': RemoteCommand(
    (n, a) => n.createAudit(bins: _ls(a, 'bins'), zone: _sn(a, 'zone'), assignedTo: _sn(a, 'assignedTo')),
    can: _area(Area.auditManage),
    errorOf: (r) => (r as ({String? error, String? id})).error,
    createsId: true,
  ),
  'setLineReason': RemoteCommand(
    (n, a) =>
        n.setLineReason(_s(a, 'auditId'), _s(a, 'bin'), _s(a, 'productId'), _sn(a, 'reason'), note: _sn(a, 'note')),
    can: _area(Area.auditManage),
  ),
  'matchSurplusToPending': RemoteCommand(
    (n, a) => n.matchSurplusToPending(_s(a, 'auditId'), _s(a, 'bin'), _s(a, 'productId'), _sn(a, 'pendingId')),
    can: _area(Area.auditManage),
    errorOf: _str,
  ),
  'closeAuditBin': RemoteCommand(
    (n, a) => n.closeAuditBin(_s(a, 'auditId'), _s(a, 'bin')),
    can: _area(Area.auditManage),
    errorOf: _str,
  ),
  'closeAudit': RemoteCommand((n, a) => n.closeAudit(_s(a, 'auditId')), can: _area(Area.auditManage), errorOf: _str),
  'cancelAudit': RemoteCommand((n, a) => n.cancelAudit(_s(a, 'auditId')), can: _area(Area.auditManage), errorOf: _str),
  'resolvePendingFound': RemoteCommand(
    (n, a) => n.resolvePendingFound(_s(a, 'id'), _s(a, 'bin'), _i(a, 'qty')),
    can: _area(Area.auditManage),
    errorOf: _str,
  ),
  'writeOffPending': RemoteCommand(
    (n, a) => n.writeOffPending(_s(a, 'id'), _i(a, 'qty'), _s(a, 'reason'), note: _sn(a, 'note') ?? ''),
    can: _area(Area.auditManage),
    errorOf: _str,
  ),
};
