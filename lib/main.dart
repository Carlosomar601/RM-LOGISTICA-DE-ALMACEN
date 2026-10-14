import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'auth/audit_log.dart';
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
  final dataDir = kIsWeb ? null : defaultUserDataDir();
  // Usuarios y PIN: compartidos por todas las cuentas de Windows del PC (ProgramData).
  final usersFile = kIsWeb ? null : defaultUserStoreFile();
  final container = ProviderContainer(overrides: [
    appConfigProvider.overrideWithValue(config),
    userDataDirProvider.overrideWithValue(dataDir),
    ledgerProvider.overrideWithValue(
        DispatchLedger.load(dataDir == null ? null : File('${dataDir.path}\\ledger.json'))),
    userStoreFileProvider.overrideWithValue(usersFile),
    userStoreProvider.overrideWithValue(UserStoreData.load(usersFile, installed: config.source != null)),
    auditProvider.overrideWithValue(
        AuditLog.load(usersFile == null ? null : File('${usersFile.parent.path}\\audit.log'))),
  ]);
  runApp(UncontrolledProviderScope(container: container, child: const PiqueoApp()));
  // Sincronización con RM según Administración → Parámetros (solo mientras la app está abierta).
  container.read(syncProvider.notifier).start();
}

class PiqueoApp extends ConsumerWidget {
  const PiqueoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Piqueo FIFO Centeno',
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
