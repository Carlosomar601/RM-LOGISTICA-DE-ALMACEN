import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/seed.dart';
import '../models/app_user.dart';

enum UserStoreStatus {
  /// Archivo leído correctamente.
  ok,

  /// No existe (desarrollo/pruebas): usuarios de demostración con PIN de demostración.
  demo,

  /// Existe pero está dañado: no se puede entrar (nunca se abre con usuarios demo).
  broken,
}

/// PIN de demostración por usuario semilla (solo cuando no hay users.json).
const kDemoPins = {'u1': '1111', 'u2': '2222', 'u3': '3333', 'u4': '4444'};

/// Usuarios, PIN (hash), roles y seguridad, guardados en
/// `%ProgramData%\RetailManager\PiqueoFIFO\users.json` (compartido por todas las cuentas del PC).
class UserStoreData {
  UserStoreData({
    required this.status,
    required this.users,
    required this.rolePresets,
    this.autoLogoutMinutes = 10,
    this.error,
  });

  final UserStoreStatus status;
  final List<AppUser> users;
  final Map<String, Map<Area, bool>> rolePresets;
  final int autoLogoutMinutes;
  final String? error;

  static UserStoreData demo() => UserStoreData(
        status: UserStoreStatus.demo,
        users: [
          for (final u in seedUsers())
            u..setPin(kDemoPins[u.id] ?? '0000'),
        ],
        rolePresets: {for (final r in kRoles) r: rolePreset(r)},
      );

  /// [installed]: la app fue instalada (hay config.json). Entonces un users.json ausente es un
  /// error, nunca el modo demostración: borrar el archivo no puede abrir la puerta con PIN 1111.
  static UserStoreData load(File? file, {bool installed = false}) {
    if (file != null && !file.existsSync() && installed) {
      return UserStoreData(
        status: UserStoreStatus.broken,
        users: [],
        rolePresets: {for (final r in kRoles) r: rolePreset(r)},
        error: 'Falta ${file.path}. Vuelve a ejecutar el instalador para crear el administrador.',
      );
    }
    if (file == null || !file.existsSync()) return demo();
    try {
      return parse(file.readAsStringSync(), source: file.path);
    } catch (e) {
      return UserStoreData(
        status: UserStoreStatus.broken,
        users: [],
        rolePresets: {for (final r in kRoles) r: rolePreset(r)},
        error: 'No se pudo leer ${file.path}: $e',
      );
    }
  }

  /// Contenido de un users.json (también el de un respaldo). [status] queda broken si no se lee.
  static UserStoreData parse(String text, {String source = 'users.json'}) {
    try {
      final j = jsonDecode(text);
      if (j is! Map || j['users'] is! List) throw const FormatException('falta la lista "users"');
      final users = [
        for (final u in j['users'] as List) AppUser.fromJson(Map<String, dynamic>.from(u as Map)),
      ];
      final presets = <String, Map<Area, bool>>{for (final r in kRoles) r: rolePreset(r)};
      final rp = j['rolePresets'];
      if (rp is Map) {
        for (final e in rp.entries) {
          if (e.value is List) {
            presets['${e.key}'] = {for (final a in Area.values) a: (e.value as List).contains(a.name)};
          }
        }
      }
      return UserStoreData(
        status: UserStoreStatus.ok,
        users: users,
        rolePresets: presets,
        autoLogoutMinutes: ((j['autoLogoutMinutes'] as num?)?.toInt() ?? 10).clamp(0, 600),
      );
    } catch (e) {
      return UserStoreData(
        status: UserStoreStatus.broken,
        users: [],
        rolePresets: {for (final r in kRoles) r: rolePreset(r)},
        error: 'No se pudo leer $source: $e',
      );
    }
  }

  /// Al menos un administrador activo con PIN: si no, nadie podría entrar.
  bool get hasLoginAdmin => users.any((u) => u.active && u.can(Area.users) && u.hasPin);

  static String encode({
    required List<AppUser> users,
    required Map<String, Map<Area, bool>> rolePresets,
    required int autoLogoutMinutes,
  }) =>
      const JsonEncoder.withIndent(' ').convert({
        'version': 1,
        'users': [for (final u in users) u.toJson()],
        'rolePresets': {
          for (final e in rolePresets.entries) e.key: [for (final a in Area.values) if (e.value[a] == true) a.name],
        },
        'autoLogoutMinutes': autoLogoutMinutes,
      });

  static void save(
    File? file, {
    required List<AppUser> users,
    required Map<String, Map<Area, bool>> rolePresets,
    required int autoLogoutMinutes,
  }) {
    if (file == null) return;
    final json = encode(users: users, rolePresets: rolePresets, autoLogoutMinutes: autoLogoutMinutes);
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp')..writeAsStringSync(json);
    if (file.existsSync()) file.deleteSync();
    tmp.renameSync(file.path);
  }
}

/// Archivo de usuarios (null = no se guarda: pruebas y web).
final userStoreFileProvider = Provider<File?>((ref) => null);

/// Datos leídos al iniciar la app.
final userStoreProvider = Provider<UserStoreData>((ref) => UserStoreData.demo());

File? defaultUserStoreFile() {
  final base = Platform.environment['ProgramData'];
  return base == null ? null : File('$base\\RetailManager\\PiqueoFIFO\\users.json');
}
