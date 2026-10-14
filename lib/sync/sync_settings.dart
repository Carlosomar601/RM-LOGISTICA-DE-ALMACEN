import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SyncInterval { manual, hourly, every2h, daily, every2d }

extension SyncIntervalX on SyncInterval {
  String get label => switch (this) {
        SyncInterval.manual => 'Solo manual (botón)',
        SyncInterval.hourly => 'Cada hora',
        SyncInterval.every2h => 'Cada 2 horas',
        SyncInterval.daily => 'Una vez al día',
        SyncInterval.every2d => 'Cada 2 días',
      };

  /// null = nunca automático.
  Duration? get period => switch (this) {
        SyncInterval.manual => null,
        SyncInterval.hourly => const Duration(hours: 1),
        SyncInterval.every2h => const Duration(hours: 2),
        SyncInterval.daily => const Duration(days: 1),
        SyncInterval.every2d => const Duration(days: 2),
      };
}

/// Configuración de sincronización, por usuario de Windows.
/// Ventas en caja por defecto (registradora): no se despachan del almacén.
const kDefaultSkipTransactions = <int>{10, 11, 12, 19};

class SyncSettings {
  SyncSettings({
    this.interval = SyncInterval.manual,
    this.lookbackDays = 2,
    this.lastSync,
    Set<int>? skipTransactions,
  }) : skipTransactions = skipTransactions ?? {...kDefaultSkipTransactions};

  SyncInterval interval;

  /// Días que se recuperan al iniciar la app (el estado se reinicia en cada arranque).
  int lookbackDays;
  DateTime? lastSync;

  /// Tipos de transacción de factura que no generan despacho (ventas en caja).
  Set<int> skipTransactions;

  Map<String, dynamic> toJson() => {
        'interval': interval.name,
        'lookbackDays': lookbackDays,
        if (lastSync != null) 'lastSync': lastSync!.toIso8601String(),
        'skipTransactions': (skipTransactions.toList()..sort()),
      };

  static SyncSettings fromJson(Map j) => SyncSettings(
        interval: SyncInterval.values.firstWhere((v) => v.name == j['interval'], orElse: () => SyncInterval.manual),
        lookbackDays: ((j['lookbackDays'] as num?)?.toInt() ?? 2).clamp(1, 366),
        lastSync: DateTime.tryParse('${j['lastSync'] ?? ''}'),
        skipTransactions: j['skipTransactions'] is List
            ? {for (final v in j['skipTransactions'] as List) if (v is num) v.toInt()}
            : null,
      );

  /// "10, 11 12;19" → {10, 11, 12, 19}. Devuelve null si hay algo que no es número.
  static Set<int>? parseTransactions(String text) {
    final parts = text.split(RegExp(r'[\s,;]+')).where((p) => p.isNotEmpty);
    final out = <int>{};
    for (final p in parts) {
      final v = int.tryParse(p);
      if (v == null) return null;
      out.add(v);
    }
    return out;
  }

  static SyncSettings load(File? file) {
    if (file == null) return SyncSettings();
    try {
      if (!file.existsSync()) return SyncSettings();
      final j = jsonDecode(file.readAsStringSync());
      return j is Map ? fromJson(j) : SyncSettings();
    } catch (_) {
      return SyncSettings();
    }
  }

  void save(File? file) {
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(toJson()));
    } catch (_) {}
  }
}

/// Carpeta de datos del usuario (`%APPDATA%\RetailManager\PiqueoFIFO`); null = sin archivos.
final userDataDirProvider = Provider<Directory?>((ref) => null);

Directory? defaultUserDataDir() {
  final appData = Platform.environment['APPDATA'];
  return appData == null ? null : Directory('$appData\\RetailManager\\PiqueoFIFO');
}
