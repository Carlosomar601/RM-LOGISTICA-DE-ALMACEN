/// Tienda o almacén parametrizable (Administración → Tiendas).
class Store {
  Store({
    required this.id,
    required this.name,
    required this.code,
    required this.receiveBin,
    this.isCentral = false,
    this.apiUrl = '',
    this.apiKey = '',
    this.active = true,
    this.lastCheck,
  });

  final String id;
  String name;
  String code;
  String receiveBin;
  final bool isCentral;
  String apiUrl;
  String apiKey;
  bool active;

  /// Resultado de la última prueba de conexión (null = nunca probada).
  String? lastCheck;
}

/// Canasta / localización de un almacén (Administración → Canastas).
class Bin {
  Bin({
    required this.id,
    required this.storeId,
    required this.code,
    this.zone = '',
    this.capacity,
    this.active = true,
    this.special = false,
  });

  final String id;
  final String storeId;
  String code;
  String zone;
  int? capacity;
  bool active;

  /// RECIBO y bins de recepción: no se pueden eliminar.
  final bool special;
}

/// Parámetros generales (Administración → Parámetros).
class AppSettings {
  AppSettings({
    this.ageAlertDays = 45,
    this.staleDays = 180,
    this.companyName = 'Centeno Tire',
    this.warehouseName = 'Almacén Central',
    this.autoLogoutMinutes = 10,
  });

  int ageAlertDays;
  int staleDays;
  String companyName;
  String warehouseName;

  /// Cierre de sesión por inactividad (0 = nunca). Se guarda en users.json.
  int autoLogoutMinutes;

  AppSettings copy() => AppSettings(
        ageAlertDays: ageAlertDays,
        staleDays: staleDays,
        companyName: companyName,
        warehouseName: warehouseName,
        autoLogoutMinutes: autoLogoutMinutes,
      );
}
