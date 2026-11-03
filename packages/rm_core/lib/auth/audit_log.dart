import 'dart:io';

import 'package:riverpod/riverpod.dart';

class AuditEvent {
  const AuditEvent(this.at, this.event, this.user);
  final DateTime at;

  /// inicio | cierre | cierre por inactividad | PIN incorrecto | bloqueo
  final String event;
  final String user;
}

/// Registro de sesiones: memoria (últimos 50) + `audit.log` en la carpeta compartida.
class AuditLog {
  AuditLog({this.file});

  final File? file;
  final List<AuditEvent> recent = [];

  static String get _machine => Platform.environment['COMPUTERNAME'] ?? Platform.localHostname;

  void add(AuditEvent e) {
    recent.insert(0, e);
    if (recent.length > 50) recent.removeLast();
    final f = file;
    if (f == null) return;
    try {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('${e.at.toIso8601String()}\t${e.event}\t${e.user}\t$_machine\r\n',
          mode: FileMode.append, flush: true);
    } catch (_) {
      // Sin permiso o disco lleno: la sesión no se detiene por el registro.
    }
  }

  /// Carga las últimas entradas del archivo al iniciar.
  static AuditLog load(File? file) {
    final log = AuditLog(file: file);
    if (file == null || !file.existsSync()) return log;
    try {
      final lines = file.readAsLinesSync();
      for (final l in lines.reversed.take(50)) {
        final p = l.split('\t');
        final at = DateTime.tryParse(p.first);
        if (at != null && p.length >= 3) log.recent.add(AuditEvent(at, p[1], p[2]));
      }
    } catch (_) {}
    return log;
  }
}

final auditProvider = Provider<AuditLog>((ref) => AuditLog());
