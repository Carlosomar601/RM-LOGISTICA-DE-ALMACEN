import 'json_util.dart';

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'receiveBin': receiveBin,
        'isCentral': isCentral,
        'apiUrl': apiUrl,
        'apiKey': apiKey,
        'active': active,
        if (lastCheck != null) 'lastCheck': lastCheck,
      };

  factory Store.fromJson(Map j) => Store(
        id: jStr(j, 'id'),
        name: jStr(j, 'name'),
        code: jStr(j, 'code'),
        receiveBin: jStr(j, 'receiveBin'),
        isCentral: jBool(j, 'isCentral'),
        apiUrl: jStrOrNull(j, 'apiUrl') ?? '',
        apiKey: jStrOrNull(j, 'apiKey') ?? '',
        active: jBool(j, 'active', fallback: true),
        lastCheck: jStrOrNull(j, 'lastCheck'),
      );
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'storeId': storeId,
        'code': code,
        'zone': zone,
        if (capacity != null) 'capacity': capacity,
        'active': active,
        'special': special,
      };

  factory Bin.fromJson(Map j) => Bin(
        id: jStr(j, 'id'),
        storeId: jStr(j, 'storeId'),
        code: jStr(j, 'code'),
        zone: jStrOrNull(j, 'zone') ?? '',
        capacity: jIntOrNull(j, 'capacity'),
        active: jBool(j, 'active', fallback: true),
        special: jBool(j, 'special'),
      );
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

  /// autoLogoutMinutes va en users.json, no en data.json.
  Map<String, dynamic> toJson() => {
        'ageAlertDays': ageAlertDays,
        'staleDays': staleDays,
        'companyName': companyName,
        'warehouseName': warehouseName,
      };

  factory AppSettings.fromJson(Map j) => AppSettings(
        ageAlertDays: jInt(j, 'ageAlertDays'),
        staleDays: jInt(j, 'staleDays'),
        companyName: jStr(j, 'companyName'),
        warehouseName: jStr(j, 'warehouseName'),
      );
}
