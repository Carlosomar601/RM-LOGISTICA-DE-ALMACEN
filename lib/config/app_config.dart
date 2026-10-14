import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Configuración de la instalación, escrita por el instalador en
/// `%ProgramData%\RetailManager\PiqueoFIFO\config.json`.
class AppConfig {
  const AppConfig({this.apiUrl = '', this.source});

  /// URL base de RMApiV2 del almacén central ('' = sin configurar).
  final String apiUrl;

  /// Archivo del que se leyó (null = no existe o no se pudo leer).
  final String? source;

  static const empty = AppConfig();

  /// Carpeta de configuración y registros de la instalación.
  static Directory configDir() {
    final base = Platform.environment['ProgramData'] ?? r'C:\ProgramData';
    return Directory('$base\\RetailManager\\PiqueoFIFO');
  }

  static File defaultFile() => File('${configDir().path}\\config.json');

  /// Lee el archivo; si falta o está dañado devuelve una configuración vacía.
  static AppConfig load([File? file]) {
    final f = file ?? defaultFile();
    try {
      if (!f.existsSync()) return AppConfig.empty;
      final j = jsonDecode(f.readAsStringSync());
      if (j is! Map) return AppConfig.empty;
      return AppConfig(apiUrl: (j['apiUrl'] ?? '').toString().trim(), source: f.path);
    } catch (_) {
      return AppConfig.empty;
    }
  }
}

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.empty);
