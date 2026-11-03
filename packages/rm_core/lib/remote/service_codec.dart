import '../sync/sync_service.dart';
import '../sync/sync_settings.dart';

/// Estado de la sincronización con RM tal como viaja a los clientes.
Map<String, dynamic> encodeSyncState(SyncState s) => {
  'settings': s.settings.toJson(),
  'running': s.running,
  'parts': [for (final p in s.parts) encodeSyncPart(p)],
  'lastRun': s.lastRun?.toIso8601String(),
};

SyncState decodeSyncState(Map<String, dynamic> j) => SyncState(
  settings: SyncSettings.fromJson(j['settings'] as Map),
  running: j['running'] == true,
  parts: decodeSyncParts(j['parts']),
  lastRun: DateTime.tryParse('${j['lastRun'] ?? ''}'),
);

Map<String, dynamic> encodeSyncPart(SyncPart p) => {
  'label': p.label,
  'ok': p.ok,
  'message': p.message,
  'notAvailable': p.notAvailable,
  'newItems': p.newItems,
};

List<SyncPart> decodeSyncParts(Object? raw) => [
  for (final x in (raw as List? ?? const []))
    SyncPart(
      '${(x as Map)['label']}',
      ok: x['ok'] == true,
      message: '${x['message'] ?? ''}',
      notAvailable: x['notAvailable'] == true,
      newItems: (x['newItems'] as num?)?.toInt() ?? 0,
    ),
];
