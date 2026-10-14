import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

enum Area { dashboard, receiving, orders, picking, transfers, history, users }

const kAreaLabels = <Area, String>{
  Area.dashboard: 'Dashboard',
  Area.receiving: 'Recibido sin ubicar',
  Area.orders: 'Órdenes entrantes',
  Area.picking: 'Piqueo FIFO',
  Area.transfers: 'Transferencias',
  Area.history: 'Historial',
  Area.users: 'Administración',
};

const kRoles = <String>[
  'Administrador',
  'Supervisor de almacén',
  'Piqueador',
  'Recibidor',
];

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
  });

  final String id;
  String name;
  String email;
  String role;
  bool active;
  Map<Area, bool> perms;

  /// PIN de acceso: solo se guarda el hash con sal, nunca el PIN.
  String? pinSalt;
  String? pinHash;

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
        if (hasPin) 'pinSalt': pinSalt,
        if (hasPin) 'pinHash': pinHash,
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
      perms: permList is List ? {for (final a in Area.values) a: permList.contains(a.name)} : rolePreset(role),
      pinSalt: j['pinSalt'] as String?,
      pinHash: j['pinHash'] as String?,
    );
  }
}
