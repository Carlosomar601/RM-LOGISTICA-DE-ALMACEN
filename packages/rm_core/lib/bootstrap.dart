import 'dart:io';

import 'package:riverpod/riverpod.dart';

import 'auth/audit_log.dart';
import 'auth/user_store.dart';
import 'config/app_config.dart';
import 'data/data_store.dart';
import 'sync/dispatch_ledger.dart';
import 'sync/sync_settings.dart';

/// Proveedores que leen y escriben los archivos del almacén (data.json, users.json,
/// ledger.json, audit.log). Los usa quien guarda los datos: el servidor o, en desarrollo,
/// la app trabajando sola.
List<Override> localStorageOverrides({
  required AppConfig config,
  required Directory? sharedDir,
  required Directory? userDataDir,
  required File? usersFile,
  required bool installed,
}) {
  final sep = Platform.pathSeparator;
  final dataFile = sharedDir == null ? null : File('${sharedDir.path}${sep}data.json');
  return [
    appConfigProvider.overrideWithValue(config),
    userDataDirProvider.overrideWithValue(userDataDir),
    sharedDirProvider.overrideWithValue(sharedDir),
    dataLoadProvider.overrideWithValue(DataStore.load(dataFile)),
    ledgerProvider.overrideWithValue(DispatchLedger.load(DispatchLedger.sharedFile(sharedDir, userDataDir))),
    userStoreFileProvider.overrideWithValue(usersFile),
    userStoreProvider.overrideWithValue(UserStoreData.load(usersFile, installed: installed)),
    auditProvider.overrideWithValue(AuditLog.load(usersFile == null ? null : File('${usersFile.parent.path}${sep}audit.log'))),
  ];
}
