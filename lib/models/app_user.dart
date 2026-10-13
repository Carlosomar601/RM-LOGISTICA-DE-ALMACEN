enum Area { dashboard, receiving, orders, picking, transfers, history, users }

const kAreaLabels = <Area, String>{
  Area.dashboard: 'Dashboard',
  Area.receiving: 'Recibido sin ubicar',
  Area.orders: 'Órdenes entrantes',
  Area.picking: 'Piqueo FIFO',
  Area.transfers: 'Transferencias',
  Area.history: 'Historial',
  Area.users: 'Usuarios y permisos',
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

class AppUser {
  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.active,
    required this.perms,
  });

  final String id;
  String name;
  String email;
  String role;
  bool active;
  Map<Area, bool> perms;

  bool can(Area a) => perms[a] ?? false;
}
