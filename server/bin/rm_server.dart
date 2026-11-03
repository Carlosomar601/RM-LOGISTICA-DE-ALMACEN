import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:riverpod/riverpod.dart';
import 'package:rm_core/auth/user_store.dart';
import 'package:rm_core/backup/backup_service.dart';
import 'package:rm_core/bootstrap.dart';
import 'package:rm_core/config/app_config.dart';
import 'package:rm_core/data/data_store.dart';
import 'package:rm_core/remote/protocol.dart';
import 'package:rm_core/selftest.dart';
import 'package:rm_core/state/app_state.dart';
import 'package:rm_core/sync/sync_service.dart';
import 'package:rm_core/util/clock.dart';
import 'package:rm_server/app_server.dart';
import 'package:rm_server/version.dart';

/// Servidor de RM Logistics. Lo instala el instalador como servicio de Windows.
///
///   rm_server.exe [--port 8190] [--data-dir <carpeta>] [--no-discovery]
Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption('port', defaultsTo: '$kDefaultServerPort', help: 'Puerto TCP (HTTP + WebSocket).')
    ..addOption('data-dir', help: r'Carpeta de datos (por defecto %ProgramData%\RetailManager\PiqueoFIFO).')
    ..addFlag('discovery', defaultsTo: true, help: 'Contestar a la búsqueda automática en la red local (UDP).')
    ..addFlag('selftest', negatable: false, help: 'Autodiagnóstico para el instalador (selftest.log) y salir.')
    ..addFlag('help', abbr: 'h', negatable: false);
  final ArgResults args;
  try {
    args = parser.parse(argv);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n${parser.usage}');
    exit(64);
  }
  if (args['help'] == true) {
    stdout.writeln('RM Logistics server $kServerVersion\n${parser.usage}');
    return;
  }
  final port = int.tryParse('${args['port']}') ?? kDefaultServerPort;

  final custom = args['data-dir'] as String?;
  final sharedDir = custom == null ? defaultSharedDir() : Directory(custom);
  if (sharedDir == null) {
    stderr.writeln('No se encontró la carpeta de datos (ProgramData).');
    exit(1);
  }
  sharedDir.createSync(recursive: true);
  final sep = Platform.pathSeparator;
  final config = AppConfig.load(File('${sharedDir.path}${sep}config.json'));
  final installed = config.source != null;
  // Sin config.json (desarrollo): fecha fija y datos de demostración, como la app.
  demoMode = !installed;
  final usersFile = custom == null ? defaultUserStoreFile() : File('${sharedDir.path}${sep}users.json');

  if (args['selftest'] == true) {
    exit(await runSelfTestAndLog(config,
        dataDir: sharedDir, log: File('${sharedDir.path}${sep}selftest.log'), title: 'RM Logistics Server'));
  }

  final log = _Log(File('${sharedDir.path}${sep}server.log'));
  log('Iniciando RM Logistics server $kServerVersion · datos en ${sharedDir.path}'
      '${installed ? '' : ' · MODO DEMOSTRACIÓN (sin config.json)'}');

  final container = ProviderContainer(overrides: [
    ...localStorageOverrides(
      config: config,
      sharedDir: sharedDir,
      // La configuración de sincronización también vive en la carpeta compartida
      // (el servicio no tiene una cuenta de usuario de Windows propia).
      userDataDir: sharedDir,
      usersFile: usersFile,
      installed: installed,
    ),
  ]);

  final app = container.read(appProvider.notifier);
  final state = container.read(appProvider);
  if (state.dataStoreError != null) log('AVISO: ${state.dataStoreError}');
  if (state.userStoreError != null) log('AVISO: ${state.userStoreError}');

  final server = AppServer(container, appVersion: kServerVersion);
  try {
    await server.start(port: port, discovery: args['discovery'] == true);
  } on SocketException catch (e) {
    log('No se pudo abrir el puerto $port: ${e.message}. ¿Ya hay otro servidor corriendo?');
    exit(2);
  }
  log('Escuchando en el puerto ${server.port} (${server.name})');

  container.read(syncProvider.notifier).start();
  container.read(backupProvider.notifier).start();

  // Guardado al detener el servicio (WinSW manda Ctrl+C) o al cerrar la consola.
  var stopping = false;
  Future<void> shutdown(String why) async {
    if (stopping) return;
    stopping = true;
    log('Deteniendo ($why)…');
    app.flush();
    await server.stop();
    log('Detenido. Datos guardados.');
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown('Ctrl+C'));
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen((_) => shutdown('SIGTERM'));
  // Red de seguridad: además del guardado 2 s después de cada cambio.
  Timer.periodic(const Duration(minutes: 1), (_) => app.flush());
}

/// Registro sencillo en consola y en server.log (se recorta al pasar de 2 MB).
class _Log {
  _Log(this.file) {
    try {
      if (file.existsSync() && file.lengthSync() > 2 * 1024 * 1024) {
        file.renameSync('${file.path}.1');
      }
    } catch (_) {}
  }
  final File file;

  void call(String msg) {
    final line = '${DateTime.now().toIso8601String().substring(0, 19)}  $msg';
    stdout.writeln(line);
    try {
      file.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {}
  }
}
