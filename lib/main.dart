import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'auth/audit_log.dart';
import 'backup/backup_service.dart';
import 'data/data_store.dart';
import 'state/app_state.dart';
import 'util/clock.dart';
import 'auth/session.dart';
import 'auth/user_store.dart';
import 'config/app_config.dart';
import 'selftest.dart';
import 'shell/app_shell.dart';
import 'sync/dispatch_ledger.dart';
import 'sync/sync_service.dart';
import 'sync/sync_settings.dart';
import 'shell/sidebar.dart';
import 'theme/app_theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = kIsWeb ? AppConfig.empty : AppConfig.load();

  // Autodiagnóstico del instalador: sin ventana (no se pinta ningún frame).
  if (!kIsWeb && args.contains('--selftest')) {
    exit(await runSelfTestAndLog(config));
  }

  Intl.defaultLocale = 'es_PR';
  try {
    await initializeDateFormatting('es_PR');
  } catch (_) {
    await initializeDateFormatting('es');
  }
  // PC instalado (hay config.json): fecha real y, sin data.json, un almacén vacío.
  // Desarrollo (`flutter run`): fecha fija y datos de demostración.
  final installed = config.source != null;
  demoMode = !installed;
  final dataDir = kIsWeb ? null : defaultUserDataDir();
  // Datos, usuarios y PIN, libro de despachos y respaldos: compartidos por todas las cuentas
  // de Windows del PC (ProgramData).
  final sharedDir = kIsWeb ? null : defaultSharedDir();
  final usersFile = kIsWeb ? null : defaultUserStoreFile();
  final dataFile = sharedDir == null ? null : File('${sharedDir.path}\\data.json');
  final container = ProviderContainer(overrides: [
    appConfigProvider.overrideWithValue(config),
    userDataDirProvider.overrideWithValue(dataDir),
    sharedDirProvider.overrideWithValue(sharedDir),
    dataLoadProvider.overrideWithValue(DataStore.load(dataFile)),
    ledgerProvider.overrideWithValue(DispatchLedger.load(DispatchLedger.sharedFile(sharedDir, dataDir))),
    userStoreFileProvider.overrideWithValue(usersFile),
    userStoreProvider.overrideWithValue(UserStoreData.load(usersFile, installed: installed)),
    auditProvider.overrideWithValue(
        AuditLog.load(usersFile == null ? null : File('${usersFile.parent.path}\\audit.log'))),
  ]);
  // Guarda lo pendiente al cerrar la ventana o al ocultarse la app.
  _lifecycle = AppLifecycleListener(
    onExitRequested: () async {
      container.read(appProvider.notifier).flush();
      return AppExitResponse.exit;
    },
    onHide: () => container.read(appProvider.notifier).flush(),
    onDetach: () => container.read(appProvider.notifier).flush(),
  );
  runApp(UncontrolledProviderScope(container: container, child: const PiqueoApp()));
  // Sincronización con RM y respaldos según Administración (solo mientras la app está abierta).
  container.read(syncProvider.notifier).start();
  container.read(backupProvider.notifier).start();
}

// ignore: unused_element
AppLifecycleListener? _lifecycle;

class PiqueoApp extends ConsumerWidget {
  const PiqueoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Retail Manager Logistics & Warehouse',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('es', 'PR'),
      supportedLocales: const [Locale('es', 'PR'), Locale('es'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SessionGate(child: AppShell()),
    );
  }
}
