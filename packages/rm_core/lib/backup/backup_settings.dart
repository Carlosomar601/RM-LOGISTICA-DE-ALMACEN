import 'dart:convert';
import 'dart:io';

import '../util/format.dart';

enum BackupFrequency { manual, daily, twiceWeekly, weekly, monthly }

extension BackupFrequencyX on BackupFrequency {
  String get label => switch (this) {
        BackupFrequency.manual => 'Solo manual (botón)',
        BackupFrequency.daily => 'Todos los días',
        BackupFrequency.twiceWeekly => 'Dos veces por semana',
        BackupFrequency.weekly => 'Una vez por semana',
        BackupFrequency.monthly => 'Una vez al mes',
      };

  /// Días de la semana que hay que elegir (0 = no aplica).
  int get weekdayCount => switch (this) {
        BackupFrequency.twiceWeekly => 2,
        BackupFrequency.weekly => 1,
        _ => 0,
      };
}

/// Nombres cortos de los días (DateTime.monday = 1 … DateTime.sunday = 7).
const kWeekdayShort = {1: 'L', 2: 'M', 3: 'X', 4: 'J', 5: 'V', 6: 'S', 7: 'D'};
const kWeekdayNames = {
  1: 'lunes',
  2: 'martes',
  3: 'miércoles',
  4: 'jueves',
  5: 'viernes',
  6: 'sábado',
  7: 'domingo',
};

/// Tras un respaldo fallido (p. ej. carpeta de red caída) se reintenta cada media hora.
const kBackupRetry = Duration(minutes: 30);

/// Programación de respaldos del PC: `%ProgramData%\RetailManager\PiqueoFIFO\backup.json`.
class BackupSettings {
  BackupSettings({
    this.frequency = BackupFrequency.daily,
    this.hour = 23,
    this.minute = 0,
    List<int>? weekdays,
    this.dayOfMonth = 1,
    this.folder = '',
    this.keep = 30,
    this.lastBackup,
    this.lastFile,
    this.lastError,
    this.lastAttempt,
  }) : weekdays = weekdays ?? [DateTime.monday, DateTime.thursday];

  BackupFrequency frequency;
  int hour;
  int minute;

  /// Semanal: el primero; dos veces por semana: los dos.
  List<int> weekdays;

  /// 1–28, para que exista en todos los meses.
  int dayOfMonth;

  /// Carpeta de respaldos ('' = la predeterminada, `…\PiqueoFIFO\backups`).
  String folder;

  /// Respaldos que se conservan; los más viejos se borran.
  int keep;

  /// Último respaldo correcto (manual o programado).
  DateTime? lastBackup;
  String? lastFile;

  /// Error del último intento (null = el último salió bien).
  String? lastError;
  DateTime? lastAttempt;

  /// Días efectivos según la frecuencia (ordenados, sin repetidos).
  List<int> get activeWeekdays {
    final n = frequency.weekdayCount;
    final days = {...weekdays.where((d) => d >= 1 && d <= 7)}.toList()..sort();
    if (n == 0) return const [];
    if (days.length >= n) return days.take(n).toList();
    return n == 1 ? [DateTime.sunday] : [DateTime.monday, DateTime.thursday];
  }

  DateTime _at(DateTime day) => DateTime(day.year, day.month, day.day, hour, minute);

  /// Último momento programado ≤ [now] (null = solo manual).
  DateTime? lastScheduled(DateTime now) {
    switch (frequency) {
      case BackupFrequency.manual:
        return null;
      case BackupFrequency.daily:
        final today = _at(now);
        return today.isAfter(now) ? _at(DateTime(now.year, now.month, now.day - 1)) : today;
      case BackupFrequency.weekly:
      case BackupFrequency.twiceWeekly:
        final days = activeWeekdays;
        for (var back = 0; back <= 7; back++) {
          final c = _at(DateTime(now.year, now.month, now.day - back));
          if (days.contains(c.weekday) && !c.isAfter(now)) return c;
        }
        return null;
      case BackupFrequency.monthly:
        final d = dayOfMonth.clamp(1, 28);
        final thisMonth = DateTime(now.year, now.month, d, hour, minute);
        return thisMonth.isAfter(now) ? DateTime(now.year, now.month - 1, d, hour, minute) : thisMonth;
    }
  }

  /// Próximo momento programado > [now] (null = solo manual).
  DateTime? nextScheduled(DateTime now) {
    switch (frequency) {
      case BackupFrequency.manual:
        return null;
      case BackupFrequency.daily:
        final today = _at(now);
        return today.isAfter(now) ? today : _at(DateTime(now.year, now.month, now.day + 1));
      case BackupFrequency.weekly:
      case BackupFrequency.twiceWeekly:
        final days = activeWeekdays;
        for (var ahead = 0; ahead <= 7; ahead++) {
          final c = _at(DateTime(now.year, now.month, now.day + ahead));
          if (days.contains(c.weekday) && c.isAfter(now)) return c;
        }
        return null;
      case BackupFrequency.monthly:
        final d = dayOfMonth.clamp(1, 28);
        final thisMonth = DateTime(now.year, now.month, d, hour, minute);
        return thisMonth.isAfter(now) ? thisMonth : DateTime(now.year, now.month + 1, d, hour, minute);
    }
  }

  /// Toca respaldar: pasó un momento programado desde el último respaldo correcto
  /// (también si la app estaba cerrada a esa hora) y no hubo un fallo hace menos de 30 min.
  bool isDue(DateTime now) {
    final due = lastScheduled(now);
    if (due == null) return false;
    final last = lastBackup;
    if (last != null && !last.isBefore(due)) return false;
    final failed = lastAttempt;
    if (lastError != null && failed != null && now.difference(failed) < kBackupRetry) return false;
    return true;
  }

  /// "Todos los días a las 11:00 p. m." / "Lunes y jueves a las …" / "El día 1 de cada mes a las …".
  String describe() {
    final time = fmtTime(hour, minute);
    return switch (frequency) {
      BackupFrequency.manual => 'Solo cuando se pulse «Respaldar ahora»',
      BackupFrequency.daily => 'Todos los días a las $time',
      BackupFrequency.weekly => 'Cada ${kWeekdayNames[activeWeekdays.first]} a las $time',
      BackupFrequency.twiceWeekly =>
        'Cada ${kWeekdayNames[activeWeekdays[0]]} y ${kWeekdayNames[activeWeekdays[1]]} a las $time',
      BackupFrequency.monthly => 'El día $dayOfMonth de cada mes a las $time',
    };
  }

  Map<String, dynamic> toJson() => {
        'frequency': frequency.name,
        'hour': hour,
        'minute': minute,
        'weekdays': weekdays,
        'dayOfMonth': dayOfMonth,
        'folder': folder,
        'keep': keep,
        if (lastBackup != null) 'lastBackup': lastBackup!.toIso8601String(),
        if (lastFile != null) 'lastFile': lastFile,
        if (lastError != null) 'lastError': lastError,
        if (lastAttempt != null) 'lastAttempt': lastAttempt!.toIso8601String(),
      };

  static BackupSettings fromJson(Map j) => BackupSettings(
        frequency:
            BackupFrequency.values.firstWhere((v) => v.name == j['frequency'], orElse: () => BackupFrequency.daily),
        hour: ((j['hour'] as num?)?.toInt() ?? 23).clamp(0, 23),
        minute: ((j['minute'] as num?)?.toInt() ?? 0).clamp(0, 59),
        weekdays: j['weekdays'] is List
            ? [for (final v in j['weekdays'] as List) if (v is num && v >= 1 && v <= 7) v.toInt()]
            : null,
        dayOfMonth: ((j['dayOfMonth'] as num?)?.toInt() ?? 1).clamp(1, 28),
        folder: j['folder'] is String ? j['folder'] as String : '',
        keep: ((j['keep'] as num?)?.toInt() ?? 30).clamp(1, 365),
        lastBackup: DateTime.tryParse('${j['lastBackup'] ?? ''}'),
        lastFile: j['lastFile'] as String?,
        lastError: j['lastError'] as String?,
        lastAttempt: DateTime.tryParse('${j['lastAttempt'] ?? ''}'),
      );

  static BackupSettings load(File? file) {
    if (file == null) return BackupSettings();
    try {
      if (!file.existsSync()) return BackupSettings();
      final j = jsonDecode(file.readAsStringSync());
      return j is Map ? fromJson(j) : BackupSettings();
    } catch (_) {
      return BackupSettings();
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
