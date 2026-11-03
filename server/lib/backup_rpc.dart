import 'dart:io';

import 'package:riverpod/riverpod.dart';
import 'package:rm_core/backup/backup_service.dart';
import 'package:rm_core/backup/backup_settings.dart';
import 'package:rm_core/state/app_state.dart';

class BackupRpcException implements Exception {
  const BackupRpcException(this.message);
  final String message;
}

/// Estado de los respaldos para los clientes: programación, carpeta y archivos guardados.
final backupStateProvider = Provider<Map<String, dynamic>>((ref) {
  final st = ref.watch(backupProvider);
  final svc = ref.read(backupProvider.notifier);
  return {
    'settings': st.settings.toJson(),
    'running': st.running,
    'folder': svc.folder?.path,
    'files': [
      for (final b in svc.list())
        {'path': b.file.path, 'createdAt': b.createdAt.toIso8601String(), 'size': b.size},
    ],
  };
});

/// Respaldos pedidos por un administrador desde otro dispositivo. Los archivos viven en el servidor.
class BackupRpc {
  BackupRpc(this.container);
  final ProviderContainer container;

  BackupService get _svc => container.read(backupProvider.notifier);
  AppNotifier get _app => container.read(appProvider.notifier);

  /// Busca el respaldo por nombre en la carpeta (nunca una ruta arbitraria del cliente).
  BackupInfo _find(Object? name) {
    final n = '$name'.split(RegExp(r'[\\/]')).last;
    for (final b in _svc.list()) {
      if (b.name == n) return b;
    }
    throw BackupRpcException('No existe el respaldo $n en la carpeta del servidor.');
  }

  Future<Object?> call(String name, Map<String, dynamic> a, {required String userId}) async {
    switch (name) {
      case 'backup.now':
        final r = await _app.runAs(userId, () => _svc.backupNow());
        return {'ok': r.ok, 'error': r.error, 'file': r.file?.path};
      case 'backup.update':
        final s = BackupSettings.fromJson(a['settings'] as Map);
        _svc.update((x) => x
          ..frequency = s.frequency
          ..hour = s.hour
          ..minute = s.minute
          ..weekdays = s.weekdays
          ..dayOfMonth = s.dayOfMonth
          ..folder = s.folder
          ..keep = s.keep);
        return true;
      case 'backup.testFolder':
        return _svc.testFolder('${a['path'] ?? ''}');
      case 'backup.inspect':
        final b = _find(a['name']);
        try {
          final c = _svc.inspect(b.file);
          final manifest = Map<String, dynamic>.from(c.manifest);
          manifest['counts'] = {
            'productos': c.data.products.length,
            'unidades': c.data.totalUnits,
            'ordenes': c.data.orders.length,
            'recibos': c.data.receipts.length,
            'movimientos': c.data.history.length,
            ...c.counts,
            'usuarios': c.users.users.length,
          };
          return {'manifest': manifest};
        } on FormatException catch (e) {
          return {'error': e.message};
        }
      case 'backup.restore':
        final b = _find(a['name']);
        return await _svc.restore(File(b.file.path));
      default:
        throw BackupRpcException('Acción de respaldo desconocida: $name');
    }
  }
}
