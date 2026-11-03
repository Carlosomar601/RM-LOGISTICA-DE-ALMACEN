import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DataStoreStatus {
  /// data.json leído correctamente.
  ok,

  /// No existe: primer arranque (PC instalado → vacío; desarrollo → datos de demostración).
  missing,

  /// Existe pero no se pudo leer: la app no guarda encima hasta restaurar o empezar vacío.
  broken,
}

/// Resultado de leer data.json al abrir la app.
class DataLoad {
  const DataLoad(this.status, {this.json, this.error});
  const DataLoad.missing() : this(DataStoreStatus.missing);

  final DataStoreStatus status;
  final Map<String, dynamic>? json;
  final String? error;
}

/// Inventario, recibos, órdenes, transferencias, historial, tiendas, canastas y parámetros:
/// `%ProgramData%\RetailManager\PiqueoFIFO\data.json` (compartido por todas las cuentas del PC).
abstract final class DataStore {
  /// Lee el archivo. El contenido se valida al construir el estado (AppState.fromDataJson).
  static DataLoad load(File? file) {
    if (file == null || !file.existsSync()) return const DataLoad.missing();
    try {
      final j = jsonDecode(file.readAsStringSync());
      if (j is! Map) throw const FormatException('no es un objeto JSON');
      return DataLoad(DataStoreStatus.ok, json: Map<String, dynamic>.from(j));
    } catch (e) {
      return DataLoad(DataStoreStatus.broken, error: 'No se pudo leer ${file.path}: $e');
    }
  }

  /// Escritura atómica: archivo temporal y luego renombrar (un corte de luz no deja medio archivo).
  static void write(File file, Map<String, dynamic> json) => writeText(file, jsonEncode(json));

  static void writeText(File file, String text) {
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp')..writeAsStringSync(text, flush: true);
    if (file.existsSync()) file.deleteSync();
    tmp.renameSync(file.path);
  }

  /// Aparta un data.json dañado (`data.danado-AAAAMMDD-HHMMSS.json`) para empezar vacío sin perderlo.
  static File? setAsideBroken(File file, DateTime now) {
    if (!file.existsSync()) return null;
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return file.renameSync('${file.parent.path}${Platform.pathSeparator}data.danado-$stamp.json');
  }
}

/// Carpeta compartida del PC (`%ProgramData%\RetailManager\PiqueoFIFO`); null = sin archivos (pruebas, web).
final sharedDirProvider = Provider<Directory?>((ref) => null);

/// data.json (null = no se guarda: pruebas y web).
final dataFileProvider = Provider<File?>((ref) {
  final dir = ref.watch(sharedDirProvider);
  return dir == null ? null : File('${dir.path}${Platform.pathSeparator}data.json');
});

/// Lo que se leyó de data.json al abrir.
final dataLoadProvider = Provider<DataLoad>((ref) => const DataLoad.missing());

Directory? defaultSharedDir() {
  final base = Platform.environment['ProgramData'];
  return base == null ? null : Directory('$base\\RetailManager\\PiqueoFIFO');
}
