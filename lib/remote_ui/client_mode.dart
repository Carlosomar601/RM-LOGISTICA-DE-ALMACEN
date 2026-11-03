import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Este dispositivo trabaja contra un servidor (null = la app sola con sus archivos, en desarrollo).
class ClientMode {
  const ClientMode({required this.address, required this.changeServer});

  /// Dirección del servidor (`host:puerto`), null = aún sin configurar.
  final String? address;

  /// Guarda otra dirección y reconecta.
  final Future<void> Function(String address) changeServer;
}

final clientModeProvider = Provider<ClientMode?>((ref) => null);

/// Dirección del servidor elegida en este dispositivo (gana sobre la del instalador).
abstract final class ClientSettings {
  static const _key = 'serverAddress';

  static Future<String?> load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_key)?.trim();
      return v == null || v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String address) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, address.trim());
    } catch (_) {}
  }
}
