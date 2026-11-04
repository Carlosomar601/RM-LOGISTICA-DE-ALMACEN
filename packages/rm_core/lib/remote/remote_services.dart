import 'dart:async';
import 'dart:io';

import '../auth/user_store.dart';
import '../backup/backup_service.dart';
import '../backup/backup_settings.dart';
import '../notify/toast_state.dart';
import '../state/app_state.dart';
import '../sync/sync_service.dart';
import '../sync/sync_settings.dart';
import 'protocol.dart';
import 'remote_app_notifier.dart';
import 'remote_link.dart';
import 'service_codec.dart';

/// Error devuelto por el servidor a una consulta.
class RemoteRpcException implements Exception {
  const RemoteRpcException(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<Object?> remoteRpc(RemoteLink link, String name, Map<String, dynamic> args) async {
  final Map<String, dynamic> r;
  try {
    r = await link.request({'t': Msg.rpc, 'name': name, 'args': args});
  } on RemoteOfflineException catch (e) {
    throw RemoteRpcException(e.message);
  }
  if (r['error'] != null) throw RemoteRpcException('${r['error']}');
  return r['result'];
}

/// Sincronización con RM vista desde un cliente: corre en el servidor; aquí solo se ve
/// su estado y se piden acciones.
class RemoteSyncService extends SyncService {
  RemoteLink get _link => ref.read(remoteLinkProvider)!;

  @override
  SyncState build() {
    final sub = _link.messages.listen((m) {
      if (m['t'] == Msg.sync) state = decodeSyncState(Map<String, dynamic>.from(m['state'] as Map));
    });
    ref.onDispose(sub.cancel);
    return SyncState(settings: SyncSettings());
  }

  @override
  void start() {}

  @override
  Future<void> tick() async {}

  @override
  void reloadSettings() {}

  void _send(String name, Object value) {
    state = state.copyWith();
    remoteRpc(_link, name, {'value': value}).catchError((Object e) {
      ref.read(toastProvider.notifier).show('No se guardó: $e');
      return null;
    });
  }

  @override
  void setInterval(SyncInterval v) {
    state.settings.interval = v;
    _send('sync.setInterval', v.name);
  }

  @override
  void setLookbackDays(int days) {
    state.settings.lookbackDays = days.clamp(1, 366);
    _send('sync.setLookbackDays', state.settings.lookbackDays);
  }

  @override
  void setSkipTransactions(Set<int> tx) {
    state.settings.skipTransactions = tx;
    _send('sync.setSkipTransactions', tx.toList());
  }

  @override
  void setReturnsEnabled(bool v) {
    state.settings.returnsEnabled = v;
    _send('sync.setReturnsEnabled', v);
  }

  @override
  void setReturnsFirstRunDays(int days) {
    state.settings.returnsFirstRunDays = days.clamp(1, kMaxReturnsFirstRunDays);
    _send('sync.setReturnsFirstRunDays', state.settings.returnsFirstRunDays);
  }

  @override
  Future<List<SyncPart>> syncNow({bool auto = false}) async {
    if (state.running) return state.parts;
    try {
      return decodeSyncParts(await remoteRpc(_link, 'sync.now', {}));
    } on RemoteRpcException catch (e) {
      return [SyncPart('Servidor', ok: false, message: e.message)];
    }
  }
}

/// Respaldos vistos desde un cliente: los archivos están en el servidor.
class RemoteBackupService extends BackupService {
  RemoteLink get _link => ref.read(remoteLinkProvider)!;
  String? _folder;
  List<BackupInfo> _files = const [];

  @override
  BackupState build() {
    final sub = _link.messages.listen((m) {
      if (m['t'] != Msg.backup) return;
      final j = Map<String, dynamic>.from(m['state'] as Map);
      _folder = j['folder'] as String?;
      _files = [
        for (final f in (j['files'] as List? ?? const []))
          BackupInfo(
            File('${(f as Map)['path']}'),
            DateTime.tryParse('${f['createdAt']}') ?? DateTime(2000),
            (f['size'] as num?)?.toInt() ?? 0,
          ),
      ];
      state = BackupState(settings: BackupSettings.fromJson(j['settings'] as Map), running: j['running'] == true);
    });
    ref.onDispose(sub.cancel);
    return BackupState(settings: BackupSettings());
  }

  @override
  bool get isLocal => false;

  @override
  Directory? get folder => _folder == null ? null : Directory(_folder!);

  @override
  List<BackupInfo> list() => _files;

  @override
  void start() {}

  @override
  Future<void> tick() async {}

  @override
  void update(void Function(BackupSettings s) change) {
    change(state.settings);
    state = BackupState(settings: state.settings, running: state.running);
    remoteRpc(_link, 'backup.update', {'settings': state.settings.toJson()}).catchError((Object e) {
      ref.read(toastProvider.notifier).show('No se guardó: $e');
      return null;
    });
  }

  @override
  String? testFolder(String path) => 'Se prueba en el servidor.';

  @override
  Future<String?> testFolderAsync(String path) async {
    try {
      return await remoteRpc(_link, 'backup.testFolder', {'path': path}) as String?;
    } on RemoteRpcException catch (e) {
      return e.message;
    }
  }

  @override
  Future<BackupResult> backupNow({bool auto = false, String? suffix}) async {
    try {
      final r = await remoteRpc(_link, 'backup.now', {}) as Map;
      if (r['ok'] == true) return BackupResult.ok(File('${r['file']}'));
      return BackupResult.failed('${r['error'] ?? 'No se pudo crear el respaldo.'}');
    } on RemoteRpcException catch (e) {
      return BackupResult.failed(e.message);
    }
  }

  @override
  BackupContents inspect(File file) => throw const FormatException('se revisa en el servidor');

  @override
  Future<BackupContents> inspectAsync(BackupInfo b) async {
    final Map r;
    try {
      r = await remoteRpc(_link, 'backup.inspect', {'name': b.name}) as Map;
    } on RemoteRpcException catch (e) {
      throw FormatException(e.message);
    }
    if (r['error'] != null) throw FormatException('${r['error']}');
    return BackupContents(
      manifest: Map<String, dynamic>.from(r['manifest'] as Map),
      data: AppState.empty(),
      users: UserStoreData(status: UserStoreStatus.ok, users: [], rolePresets: {}),
    );
  }

  @override
  Future<String?> restore(File file) async {
    try {
      final name = file.path.split(RegExp(r'[\\/]')).last;
      return await remoteRpc(_link, 'backup.restore', {'name': name}) as String?;
    } on RemoteRpcException catch (e) {
      return e.message;
    }
  }
}
