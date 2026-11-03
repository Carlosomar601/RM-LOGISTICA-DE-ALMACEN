import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:rm_core/auth/user_store.dart';
import 'package:rm_core/backup/backup_service.dart';
import 'package:rm_core/bootstrap.dart';
import 'package:rm_core/config/app_config.dart';
import 'package:rm_core/data/data_store.dart';
import 'package:rm_core/remote/protocol.dart';
import 'package:rm_core/remote/remote_link.dart';
import 'package:rm_core/selftest.dart';
import 'package:rm_core/state/app_state.dart';
import 'package:rm_core/sync/sync_service.dart';
import 'package:rm_core/sync/sync_settings.dart';
import 'package:rm_core/util/clock.dart';
import 'package:web_socket_channel/io.dart';

import 'auth/session.dart';
import 'remote_ui/client_container.dart';
import 'remote_ui/client_mode.dart';
import 'remote_ui/connection_gate.dart';
import 'shell/app_shell.dart';
import 'shell/sidebar.dart';
import 'theme/app_theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = kIsWeb ? AppConfig.empty : AppConfig.load();

  // Autodiagnóstico del instalador: sin ventana (no se pinta ningún frame).
  // En un cliente revisa que el servidor conteste (selftest-cliente.log); si no, datos y RMApiV2.
  if (!kIsWeb && args.contains('--selftest')) {
    final dir = AppConfig.configDir().path;
    exit(await runSelfTestAndLog(config, log: config.isClient ? File('$dir${Platform.pathSeparator}selftest-cliente.log') : null));
  }

  Intl.defaultLocale = 'es_PR';
  try {
    await initializeDateFormatting('es_PR');
  } catch (_) {
    await initializeDateFormatting('es');
  }

  // Cliente de un servidor: instalado como "cliente" o "servidor + cliente", con una dirección
  // elegida en este dispositivo, `--server=<dirección>`, o siempre en Android/iOS.
  // Si no, la app trabaja sola con sus archivos (desarrollo con `flutter run` e instalaciones 1.1).
  final serverArg = args.where((a) => a.startsWith('--server=')).map((a) => a.substring(9)).firstOrNull;
  final mobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  final saved = kIsWeb ? null : await ClientSettings.load();
  if (!kIsWeb && (serverArg != null || saved != null || config.isClient || mobile)) {
    final fromConfig = config.serverUrl.isNotEmpty ? config.serverUrl : (config.mode == 'both' ? 'localhost' : null);
    _runClient(serverArg ?? saved ?? fromConfig);
  } else {
    _runLocal(config);
  }
}

// ---------- La app sola (archivos locales) ----------

void _runLocal(AppConfig config) {
  // PC instalado (hay config.json): fecha real y, sin data.json, un almacén vacío.
  // Desarrollo (`flutter run`): fecha fija y datos de demostración.
  final installed = config.source != null;
  demoMode = !installed;
  final container = ProviderContainer(
    overrides: kIsWeb
        ? [appConfigProvider.overrideWithValue(config)]
        : localStorageOverrides(
            config: config,
            // Datos, usuarios y PIN, libro de despachos y respaldos: compartidos por todas las cuentas
            // de Windows del PC (ProgramData).
            sharedDir: defaultSharedDir(),
            userDataDir: defaultUserDataDir(),
            usersFile: defaultUserStoreFile(),
            installed: installed,
          ),
  );
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

// ---------- Cliente de un servidor ----------

ProviderContainer? _client;
RemoteLink? _clientLink;

String _deviceName() {
  try {
    return Platform.localHostname;
  } catch (_) {
    return Platform.operatingSystem;
  }
}

/// Arranca (o reinicia, al cambiar de servidor) la app conectada a [address].
void _runClient(String? address) {
  final old = _client;
  final oldLink = _clientLink;
  final uri = address == null ? null : serverWsUri(address);
  final link = uri == null
      ? null
      : RemoteLink(
          uri,
          device: _deviceName(),
          connect: (u) => IOWebSocketChannel.connect(
            u,
            pingInterval: const Duration(seconds: 10),
            connectTimeout: const Duration(seconds: 8),
          ),
        );
  final container = buildClientContainer(
    link: link,
    mode: ClientMode(
      address: uri == null ? address : serverLabel(uri),
      changeServer: (a) async {
        await ClientSettings.save(a);
        _runClient(a);
      },
    ),
  );
  _client = container;
  _clientLink = link;
  link?.start();
  runApp(UncontrolledProviderScope(key: UniqueKey(), container: container, child: const PiqueoApp()));
  if (old != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldLink?.close();
      old.dispose();
    });
  }
}

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
      home: const ConnectionGate(child: SessionGate(child: AppShell())),
    );
  }
}
