import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rm_core/backup/backup_service.dart';
import 'package:rm_core/remote/remote_app_notifier.dart';
import 'package:rm_core/remote/remote_link.dart';
import 'package:rm_core/remote/remote_services.dart';
import 'package:rm_core/state/app_state.dart';
import 'package:rm_core/sync/sync_service.dart';

import 'client_mode.dart';

/// Proveedores de un dispositivo cliente: los datos, la sincronización y los respaldos vienen
/// del servidor por [link]. Sin [link] (aún sin dirección) solo se muestra la pantalla de conexión.
/// Llama a [RemoteLink.start] después de crear el contenedor.
ProviderContainer buildClientContainer({
  required RemoteLink? link,
  required ClientMode mode,
  List<Override> extra = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      clientModeProvider.overrideWithValue(mode),
      remoteLinkProvider.overrideWithValue(link),
      if (link != null) ...[
        appProvider.overrideWith(RemoteAppNotifier.new),
        syncProvider.overrideWith(RemoteSyncService.new),
        backupProvider.overrideWith(RemoteBackupService.new),
      ],
      ...extra,
    ],
  );
  if (link != null) {
    // Se suscriben antes de conectar para no perder los primeros mensajes del servidor.
    container.read(connectionProvider);
    container.read(appProvider);
    container.read(syncProvider);
    container.read(backupProvider);
  }
  return container;
}
