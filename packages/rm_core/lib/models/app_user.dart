import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

enum Area { dashboard, receiving, orders, picking, transfers, audit, auditManage, history, users }

const kAreaLabels = <Area, String>{
  Area.dashboard: 'Dashboard',
  Area.receiving: 'Recibido sin ubicar',
  Area.orders: 'Órdenes entrantes',
  Area.picking: 'Piqueo FIFO',
  Area.transfers: 'Transferencias',
  Area.audit: 'Auditoría: contar',
  Area.auditManage: 'Auditoría: crear, cerrar, pendientes y reporte',
  Area.history: 'Historial',
  Area.users: 'Administración',
};

const kRoles = <String>[
  'Administrador',
  'Supervisor de almacén',
  'Piqueador',
  'Recibidor',
  'Auditor',
];

/// Áreas agregadas después de la primera versión de users.json: un archivo sin
/// `permsVersion` las recibe del preset del rol (para que admin y supervisor no las pierdan).
const kPermsVersion = 2;
const kAreasSincePermsV2 = <Area>{Area.audit, Area.auditManage};

Map<Area, bool> rolePreset(String role) {
  Set<Area> on;
  switch (role) {
    case 'Administrador':
      on = Area.values.toSet();
    case 'Supervisor de almacén':
      on = Area.values.where((a) => a != Area.users).toSet();
    case 'Piqueador':
      on = {Area.dashboard, Area.orders, Area.picking};
    case 'Recibidor':
      on = {Area.dashboard, Area.receiving};
    case 'Auditor':
      on = {Area.dashboard, Area.audit};
    default:
      on = {Area.dashboard};
  }
  return {for (final a in Area.values) a: on.contains(a)};
}

/// SHA-256 de `salt + pin` en hex. El instalador (Inno Setup, `GetSHA256OfString`)
/// usa el mismo formato para crear al primer administrador.
String hashPin(String salt, String pin) => sha256.convert(utf8.encode('$salt$pin')).toString();

String newSalt([Random? rng]) {
  final r = rng ?? Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

bool isValidPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

/// Completa las áreas nuevas desde el preset del rol cuando los permisos vienen de una versión anterior.
Map<Area, bool> migratePerms(Map<Area, bool> perms, String role, Object? version) {
  if (version is num && version >= kPermsVersion) return perms;
  final preset = rolePreset(role);
  return {...perms, for (final a in kAreasSincePermsV2) a: preset[a] ?? false};
}

class AppUser {
  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.active,
    required this.perms,
    this.pinSalt,
    this.pinHash,
    List<String>? orderCategories,
    List<String>? orderPriceLevels,
  })  : orderCategories = orderCategories ?? [],
        orderPriceLevels = orderPriceLevels ?? [];

  final String id;
  String name;
  String email;
  String role;
  bool active;
  Map<Area, bool> perms;

  /// PIN de acceso: solo se guarda el hash con sal, nunca el PIN.
  String? pinSalt;
  String? pinHash;

  /// Categorías de cliente elegidas en «Órdenes entrantes», por nombre (vacío = todas).
  /// Se recuerda por usuario.
  List<String> orderCategories;

  /// Niveles de precio elegidos en «Órdenes entrantes», por nombre (vacío = todos).
  List<String> orderPriceLevels;

  bool can(Area a) => perms[a] ?? false;

  bool get hasPin => pinSalt != null && pinHash != null;

  bool checkPin(String pin) => hasPin && hashPin(pinSalt!, pin).toLowerCase() == pinHash!.toLowerCase();

  void setPin(String pin, {Random? rng}) {
    pinSalt = newSalt(rng);
    pinHash = hashPin(pinSalt!, pin);
  }

  void clearPin() {
    pinSalt = null;
    pinHash = null;
  }

  /// Nombre corto para los registros: "Carlos Omar" → "C. Omar".
  String get shortName {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '—';
    if (parts.length == 1) return parts.first;
    return '${parts.first[0].toUpperCase()}. ${parts.sublist(1).join(' ')}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role,
        'active': active,
        'perms': [for (final a in Area.values) if (can(a)) a.name],
        'permsVersion': kPermsVersion,
        if (hasPin) 'pinSalt': pinSalt,
        if (hasPin) 'pinHash': pinHash,
        if (orderCategories.isNotEmpty) 'orderCategories': orderCategories,
        if (orderPriceLevels.isNotEmpty) 'orderPriceLevels': orderPriceLevels,
      };

  factory AppUser.fromJson(Map<String, dynamic> j) {
    final role = '${j['role'] ?? 'Piqueador'}';
    final permList = j['perms'];
    return AppUser(
      id: '${j['id']}',
      name: '${j['name'] ?? ''}',
      email: '${j['email'] ?? ''}',
      role: role,
      active: j['active'] != false,
      perms: permList is List
          ? migratePerms({for (final a in Area.values) a: permList.contains(a.name)}, role, j['permsVersion'])
          : rolePreset(role),
      pinSalt: j['pinSalt'] as String?,
      pinHash: j['pinHash'] as String?,
      orderCategories: [
        for (final e in (j['orderCategories'] is List ? j['orderCategories'] as List : const []))
          // Solo nombres; un filtro viejo guardado por ID se descarta (vuelve a «Todas»).
          if (e is String && e.trim().isNotEmpty) e,
      ],
      orderPriceLevels: [
        for (final e in (j['orderPriceLevels'] is List ? j['orderPriceLevels'] as List : const []))
          if (e is String && e.trim().isNotEmpty) e,
      ],
    );
  }
}
