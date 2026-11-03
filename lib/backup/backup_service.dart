import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/audit_log.dart';
import '../auth/user_store.dart';
import '../config/app_config.dart';
import '../data/data_store.dart';
import '../state/app_state.dart';
import '../sync/dispatch_ledger.dart';
import '../sync/sync_service.dart';
import '../widgets/toast.dart';
import 'backup_settings.dart';

const kBackupPrefix = 'RMLogistics-respaldo-';
const kSafetySuffix = 'antes-de-restaurar';
const kAppName = 'Retail Manager Logistics & Warehouse';

/// Formato del zip de respaldo.
const kBackupFormat = 1;

final _backupName = RegExp(r'^RMLogistics-respaldo-(\d{4})-(\d{2})-(\d{2})_(\d{2})(\d{2}).*\.zip$');

/// Un respaldo en la carpeta.
class BackupInfo {
  const BackupInfo(this.file, this.createdAt, this.size);
  final File file;
  final DateTime createdAt;
  final int size;

  String get name => file.uri.pathSegments.last;
  bool get isSafety => name.contains(kSafetySuffix);
}

/// Contenido validado de un respaldo, listo para restaurar.
class BackupContents {
  BackupContents({
    required this.manifest,
    required this.data,
    required this.users,
    this.ledgerJson,
    this.syncSettingsJson,
  });

  final Map<String, dynamic> manifest;
  final AppState data;
  final UserStoreData users;
  final String? ledgerJson;
  final String? syncSettingsJson;

  DateTime? get createdAt => DateTime.tryParse('${manifest['createdAt'] ?? ''}');
  String get createdBy => '${manifest['createdBy'] ?? '—'}';
  String get machine => '${manifest['machine'] ?? '—'}';
  Map get counts => manifest['counts'] is Map ? manifest['counts'] as Map : const {};
}

class BackupResult {
  const BackupResult.ok(this.file) : error = null;
  const BackupResult.failed(this.error) : file = null;
  final File? file;
  final String? error;
  bool get ok => error == null;
}

class BackupState {
  const BackupState({required this.settings, this.running = false});
  final BackupSettings settings;
  final bool running;
}

/// Respaldos del almacén: a mano o según la programación de Administración → Respaldos.
/// Solo corre con la app abierta (arranca con Windows); si a la hora programada estaba cerrada,
/// respalda al abrir. Revisa cada minuto si toca.
class BackupService extends Notifier<BackupState> {
  Timer? _ticker;

  Directory? get _sharedDir => ref.read(sharedDirProvider);

  File? get _settingsFile {
    final d = _sharedDir;
    return d == null ? null : File('${d.path}${Platform.pathSeparator}backup.json');
  }

  @override
  BackupState build() {
    ref.onDispose(() => _ticker?.cancel());
    return BackupState(settings: BackupSettings.load(_settingsFile));
  }

  /// Carpeta efectiva (null = no hay carpeta configurada ni predeterminada).
  Directory? get folder {
    final custom = state.settings.folder.trim();
    if (custom.isNotEmpty) return Directory(custom);
    final d = _sharedDir;
    return d == null ? null : Directory('${d.path}${Platform.pathSeparator}backups');
  }

  void start() {
    _ticker ??= ref.read(tickerFactoryProvider)(const Duration(minutes: 1), (_) => tick());
    tick();
  }

  DateTime _now() => ref.read(clockProvider)();

  bool isDue(DateTime now) => ref.read(appProvider).dataStoreError == null && state.settings.isDue(now);

  Future<void> tick() async {
    if (!state.running && isDue(_now())) await backupNow(auto: true);
  }

  void update(void Function(BackupSettings s) change) {
    change(state.settings);
    state.settings.save(_settingsFile);
    state = BackupState(settings: state.settings, running: state.running);
  }

  /// Escribe y borra un archivo de prueba en la carpeta. Devuelve el error o null.
  String? testFolder(String path) {
    final dir = Directory(path.trim().isEmpty ? (folder?.path ?? '') : path.trim());
    if (dir.path.isEmpty) return 'No hay carpeta configurada.';
    try {
      dir.createSync(recursive: true);
      final f = File('${dir.path}${Platform.pathSeparator}.prueba-escritura')..writeAsStringSync('ok');
      f.deleteSync();
      return null;
    } catch (e) {
      return 'No se puede escribir en ${dir.path}: ${_short(e)}';
    }
  }

  /// Respaldos de la carpeta, del más reciente al más viejo. Solo los archivos con nuestro nombre.
  List<BackupInfo> list() {
    final dir = folder;
    if (dir == null || !dir.existsSync()) return [];
    final out = <BackupInfo>[];
    try {
      for (final f in dir.listSync().whereType<File>()) {
        final m = _backupName.firstMatch(f.uri.pathSegments.last);
        if (m == null) continue;
        final g = [for (var i = 1; i <= 5; i++) int.parse(m.group(i)!)];
        out.add(BackupInfo(f, DateTime(g[0], g[1], g[2], g[3], g[4]), f.lengthSync()));
      }
    } catch (_) {}
    out.sort((a, b) => b.name.compareTo(a.name));
    return out;
  }

  /// Hace un respaldo ahora. [suffix] distingue el respaldo de seguridad antes de restaurar.
  Future<BackupResult> backupNow({bool auto = false, String? suffix}) async {
    if (state.running) return const BackupResult.failed('Ya hay un respaldo en curso.');
    state = BackupState(settings: state.settings, running: true);
    final now = _now();
    final app = ref.read(appProvider.notifier);
    final who = ref.read(appProvider).currentUser?.name ?? 'Sistema';
    try {
      await Future<void>.delayed(Duration.zero); // deja pintar el indicador de progreso
      if (ref.read(appProvider).dataStoreError != null) {
        throw const _BackupError('Los datos del almacén están dañados: restaura un respaldo antes de respaldar.');
      }
      final dir = folder;
      if (dir == null) throw const _BackupError('No hay carpeta de respaldos configurada.');
      app.flush();
      final bytes = _buildZip(now, who, auto: auto);
      dir.createSync(recursive: true);
      final file = _freeName(dir, now, suffix);
      final tmp = File('${file.path}.tmp')..writeAsBytesSync(bytes, flush: true);
      tmp.renameSync(file.path);
      _prune();
      update((s) => s
        ..lastBackup = now
        ..lastFile = file.path
        ..lastError = null
        ..lastAttempt = now);
      _audit(auto ? 'respaldo automático' : 'respaldo', who, file);
      return BackupResult.ok(file);
    } catch (e) {
      final msg = e is _BackupError ? e.message : 'No se pudo crear el respaldo: ${_short(e)}';
      update((s) => s
        ..lastError = msg
        ..lastAttempt = now);
      ref.read(auditProvider).add(AuditEvent(now, 'respaldo falló: $msg', who));
      if (auto) ref.read(toastProvider.notifier).show('Respaldo automático falló: $msg');
      return BackupResult.failed(msg);
    } finally {
      state = BackupState(settings: state.settings, running: false);
    }
  }

  void _audit(String event, String who, File f) =>
      ref.read(auditProvider).add(AuditEvent(_now(), '$event ${f.uri.pathSegments.last}', who));

  File _freeName(Directory dir, DateTime t, String? suffix) {
    String two(int v) => v.toString().padLeft(2, '0');
    final base = '$kBackupPrefix${t.year}-${two(t.month)}-${two(t.day)}_${two(t.hour)}${two(t.minute)}'
        '${suffix == null ? '' : '-$suffix'}';
    var f = File('${dir.path}${Platform.pathSeparator}$base.zip');
    for (var n = 2; f.existsSync(); n++) {
      f = File('${dir.path}${Platform.pathSeparator}$base-$n.zip');
    }
    return f;
  }

  List<int> _buildZip(DateTime now, String who, {required bool auto}) {
    final s = ref.read(appProvider);
    final archive = Archive();
    void addText(String name, String text) {
      final b = utf8.encode(text);
      archive.addFile(ArchiveFile(name, b.length, b));
    }

    void addFileIfExists(String name, File? f) {
      if (f == null || !f.existsSync()) return;
      final b = f.readAsBytesSync();
      archive.addFile(ArchiveFile(name, b.length, b));
    }

    addText(
        'manifest.json',
        const JsonEncoder.withIndent(' ').convert({
          'app': kAppName,
          'format': kBackupFormat,
          'createdAt': now.toIso8601String(),
          'createdBy': who,
          'machine': Platform.environment['COMPUTERNAME'] ?? Platform.localHostname,
          'automatic': auto,
          'counts': {
            'productos': s.products.length,
            'unidades': s.totalUnits,
            'ordenes': s.orders.length,
            'recibos': s.receipts.length,
            'movimientos': s.history.length,
            'usuarios': s.users.length,
          },
        }));
    addText('data.json', jsonEncode(s.toDataJson()));
    final usersFile = ref.read(userStoreFileProvider);
    if (usersFile != null && usersFile.existsSync()) {
      addFileIfExists('users.json', usersFile);
    } else {
      // Sin archivo (pruebas o modo demostración): los usuarios en memoria, con su PIN cifrado.
      addText(
          'users.json',
          UserStoreData.encode(
              users: s.users, rolePresets: s.rolePresets, autoLogoutMinutes: s.settings.autoLogoutMinutes));
    }
    addFileIfExists('audit.log', ref.read(auditProvider).file);
    addFileIfExists('ledger.json', ref.read(ledgerProvider).file);
    addFileIfExists('settings.json', ref.read(syncProvider.notifier).settingsFile);
    final cfg = ref.read(appConfigProvider).source;
    addFileIfExists('config.json', cfg == null ? null : File(cfg));
    return ZipEncoder().encodeBytes(archive);
  }

  /// Borra los respaldos más viejos (solo archivos con nuestro nombre) más allá de "conservar".
  void _prune() {
    final all = list();
    for (final b in all.skip(state.settings.keep)) {
      try {
        b.file.deleteSync();
      } catch (_) {}
    }
  }

  /// Lee y valida un respaldo sin tocar nada. Lanza [FormatException] con el motivo.
  BackupContents inspect(File file) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(file.readAsBytesSync());
    } catch (e) {
      throw FormatException('el archivo no es un respaldo válido (${_short(e)})');
    }
    String? text(String name) {
      final f = zip.findFile(name);
      return f == null ? null : utf8.decode(f.content);
    }

    final manifestText = text('manifest.json');
    if (manifestText == null) throw const FormatException('falta manifest.json: no es un respaldo de esta app');
    final manifest = jsonDecode(manifestText);
    if (manifest is! Map || (manifest['format'] as num? ?? 99) > kBackupFormat) {
      throw const FormatException('respaldo de una versión más nueva de la app');
    }
    final dataText = text('data.json');
    if (dataText == null) throw const FormatException('falta data.json');
    final AppState data;
    try {
      final j = jsonDecode(dataText);
      if (j is! Map) throw const FormatException('no es un objeto JSON');
      data = AppState.fromDataJson(j);
    } catch (e) {
      throw FormatException('data.json dañado (${_short(e)})');
    }
    final usersText = text('users.json');
    if (usersText == null) throw const FormatException('falta users.json');
    final users = UserStoreData.parse(usersText);
    if (users.status != UserStoreStatus.ok) throw FormatException(users.error ?? 'users.json dañado');
    if (!users.hasLoginAdmin) {
      throw const FormatException('el respaldo no tiene ningún administrador activo con PIN: nadie podría entrar');
    }
    return BackupContents(
      manifest: Map<String, dynamic>.from(manifest),
      data: data,
      users: users,
      ledgerJson: text('ledger.json'),
      syncSettingsJson: text('settings.json'),
    );
  }

  /// Restaura un respaldo validado: primero un respaldo de seguridad de lo actual (salvo que los
  /// datos actuales estén dañados), luego reemplaza datos, usuarios, libro de despachos y
  /// sincronización, y cierra la sesión. config.json (dirección API del PC) y audit.log no se tocan.
  Future<String?> restore(File file) async {
    final BackupContents c;
    try {
      c = inspect(file);
    } on FormatException catch (e) {
      return 'No se puede restaurar: ${e.message}';
    }
    if (ref.read(appProvider).dataStoreError == null) {
      final safety = await backupNow(suffix: kSafetySuffix);
      if (!safety.ok) return 'No se restauró: falló el respaldo de seguridad (${safety.error}).';
    }
    try {
      final ledger = ref.read(ledgerProvider);
      if (c.ledgerJson != null && ledger.file != null) {
        DataStore.writeText(ledger.file!, c.ledgerJson!);
        ledger.reload();
      }
      final sync = ref.read(syncProvider.notifier);
      if (c.syncSettingsJson != null && sync.settingsFile != null) {
        DataStore.writeText(sync.settingsFile!, c.syncSettingsJson!);
        sync.reloadSettings();
      }
    } catch (e) {
      return 'No se pudo restaurar: ${_short(e)}';
    }
    ref.read(appProvider.notifier).restoreFrom(c.data, c.users);
    return null;
  }
}

class _BackupError implements Exception {
  const _BackupError(this.message);
  final String message;
}

String _short(Object e) => e is FileSystemException ? (e.osError?.message ?? e.message) : '$e';

final backupProvider = NotifierProvider<BackupService, BackupState>(BackupService.new);
