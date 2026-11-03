import 'dart:io';

import 'api/rm_api.dart';
import 'auth/user_store.dart';
import 'config/app_config.dart';
import 'data/data_store.dart';
import 'models/app_user.dart';
import 'state/app_state.dart';
import 'util/format.dart';

/// Resultado de una verificación del autodiagnóstico.
class SelfTestCheck {
  const SelfTestCheck(this.name, this.ok, this.detail);
  final String name;
  final bool ok;
  final String detail;

  @override
  String toString() => '${ok ? 'OK  ' : 'FAIL'} $name: $detail';
}

/// Autodiagnóstico posinstalación (`--selftest`). Solo lectura contra RM.
Future<List<SelfTestCheck>> runSelfTest(AppConfig config,
    {RmApi Function(String url)? apiFactory, DateTime? now, File? usersFile, File? dataFile}) async {
  final checks = <SelfTestCheck>[];
  if (usersFile != null) checks.add(checkUsers(usersFile));
  if (dataFile != null) checks.add(checkData(dataFile));
  final url = config.apiUrl;
  if (config.source == null) {
    checks.add(const SelfTestCheck('Configuración', false, 'no se encontró config.json'));
    return checks;
  }
  final valid = RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(url);
  checks.add(SelfTestCheck('Configuración', valid, valid ? 'API $url' : 'dirección API inválida: «$url»'));
  if (!valid) return checks;

  final api = (apiFactory ?? (u) => RmHttpApi(u))(url);
  try {
    checks.add(SelfTestCheck('API RMApiV2 (HealthCheck)', true, await api.healthCheck()));
  } on RmApiException catch (e) {
    checks.add(SelfTestCheck('API RMApiV2 (HealthCheck)', false, e.message));
    return checks;
  }
  final today = now ?? DateTime.now();
  try {
    final lines = await api.receiptsByDate(today.subtract(const Duration(days: 1)), today);
    checks.add(SelfTestCheck('Recibos (RecReceiptsByDate)', true, '${lines.length} línea(s) en el último día'));
  } on RmApiException catch (e) {
    checks.add(SelfTestCheck('Recibos (RecReceiptsByDate)', false, e.message));
  }
  // Endpoints solicitados al equipo de la API: informan, pero no hacen fallar la instalación.
  Future<void> optional(String name, Future<int> Function() run) async {
    try {
      checks.add(SelfTestCheck(name, true, '${await run()} línea(s)'));
    } on RmApiException catch (e) {
      checks.add(SelfTestCheck(name, true, e.notAvailable ? 'aún no disponible en esta API' : 'aviso: ${e.message}'));
    }
  }

  await optional('Órdenes (OrdOpenOrders)', () async => (await api.openOrders()).length);
  await optional('Facturas (SalesInvoicesByDate)',
      () async => (await api.invoicesByDate(today.subtract(const Duration(days: 1)), today)).length);
  return checks;
}

/// Alguien tiene que poder iniciar sesión: users.json legible y un administrador activo con PIN.
SelfTestCheck checkUsers(File usersFile) {
  const name = 'Usuarios (users.json)';
  if (!usersFile.existsSync()) return SelfTestCheck(name, false, 'no existe ${usersFile.path}');
  final data = UserStoreData.load(usersFile);
  if (data.status != UserStoreStatus.ok) return SelfTestCheck(name, false, data.error ?? 'no se pudo leer');
  final admins = data.users.where((u) => u.active && u.can(Area.users) && u.hasPin).length;
  if (admins == 0) return const SelfTestCheck(name, false, 'ningún administrador activo con PIN');
  return SelfTestCheck(name, true, '${data.users.length} usuario(s), $admins administrador(es) con PIN');
}

/// Datos del almacén: informa, pero no hace fallar la instalación (un data.json dañado se
/// resuelve en la app restaurando un respaldo).
SelfTestCheck checkData(File dataFile) {
  const name = 'Datos (data.json)';
  final load = DataStore.load(dataFile);
  switch (load.status) {
    case DataStoreStatus.missing:
      return const SelfTestCheck(name, true, 'aún no hay datos (primer arranque: almacén vacío)');
    case DataStoreStatus.broken:
      return SelfTestCheck(name, true, 'aviso: ${load.error} - restaura un respaldo en Administración');
    case DataStoreStatus.ok:
      try {
        final s = AppState.fromDataJson(load.json!);
        return SelfTestCheck(name, true,
            '${s.products.length} producto(s), ${s.totalUnits} unidad(es), ${s.orders.length} orden(es)');
      } catch (e) {
        return SelfTestCheck(name, true, 'aviso: datos dañados ($e) - restaura un respaldo en Administración');
      }
  }
}

bool selfTestPassed(List<SelfTestCheck> checks) => checks.isNotEmpty && checks.every((c) => c.ok);

/// Escribe `selftest.log` junto a la configuración y devuelve el código de salida.
Future<int> runSelfTestAndLog(AppConfig config, {File? log}) async {
  List<SelfTestCheck> checks;
  try {
    final shared = defaultSharedDir();
    checks = await runSelfTest(config,
        usersFile: defaultUserStoreFile(), dataFile: shared == null ? null : File('${shared.path}\\data.json'));
  } catch (e) {
    checks = [SelfTestCheck('Autodiagnóstico', false, 'error inesperado: $e')];
  }
  final pass = selfTestPassed(checks);
  final out = log ?? File('${AppConfig.configDir().path}\\selftest.log');
  final text = [
    'Retail Manager Logistics & Warehouse — autodiagnóstico ${DateTime.now().toIso8601String()}',
    'App: ${Platform.resolvedExecutable}',
    ...checks.map((c) => c.toString()),
    'RESULT: ${pass ? 'PASS' : 'FAIL'}',
  ].join('\r\n');
  // ASCII: el instalador (Inno Setup) lee el archivo como ANSI.
  final ascii = String.fromCharCodes(
      stripAccents(text).replaceAll('—', '-').replaceAll('·', '-').runes.map((r) => r < 128 ? r : 0x3F));
  try {
    out.parent.createSync(recursive: true);
    out.writeAsStringSync('$ascii\r\n');
  } catch (_) {
    // Sin permiso de escritura: el código de salida sigue reflejando el resultado.
  }
  return pass ? 0 : 1;
}
