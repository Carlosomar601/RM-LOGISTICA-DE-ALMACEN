import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'protocol.dart';

/// Un servidor que contestó a la búsqueda en la red local.
class FoundServer {
  const FoundServer(this.name, this.host, this.port);
  final String name;
  final String host;
  final int port;

  String get address => '$host:$port';
}

/// Busca servidores de RM Logistics en la red local (broadcast UDP). Devuelve los que
/// contesten antes de [timeout]. No lanza: sin red devuelve una lista vacía.
Future<List<FoundServer>> discoverServers({Duration timeout = const Duration(milliseconds: 1500)}) async {
  final found = <String, FoundServer>{};
  RawDatagramSocket? sock;
  try {
    sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    sock.broadcastEnabled = true;
    final s = sock;
    s.listen((e) {
      if (e != RawSocketEvent.read) return;
      final d = s.receive();
      if (d == null) return;
      final text = utf8.decode(d.data, allowMalformed: true);
      if (!text.startsWith(kDiscoveryReplyPrefix)) return;
      try {
        final j = jsonDecode(text.substring(kDiscoveryReplyPrefix.length)) as Map;
        final port = (j['port'] as num?)?.toInt() ?? kDefaultServerPort;
        final host = d.address.address;
        found['$host:$port'] = FoundServer('${j['name'] ?? host}', host, port);
      } catch (_) {}
    });
    final query = utf8.encode(kDiscoveryQuery);
    final targets = {InternetAddress('255.255.255.255'), ...await _subnetBroadcasts()};
    // Se repite por si se pierde un paquete en Wi-Fi.
    for (var i = 0; i < 3; i++) {
      for (final t in targets) {
        try {
          s.send(query, t, kDiscoveryPort);
        } catch (_) {}
      }
      await Future<void>.delayed(timeout ~/ 3);
    }
  } catch (_) {
    // Sin red o sin permiso: se escribe la dirección a mano.
  } finally {
    sock?.close();
  }
  return found.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}

/// Direcciones de broadcast de cada red /24 del equipo (algunos routers no reenvían 255.255.255.255).
Future<Set<InternetAddress>> _subnetBroadcasts() async {
  final out = <InternetAddress>{};
  try {
    for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in ni.addresses) {
        final p = a.rawAddress;
        if (p.length == 4 && !a.isLoopback) {
          out.add(InternetAddress.fromRawAddress(Uint8List.fromList([p[0], p[1], p[2], 255])));
        }
      }
    }
  } catch (_) {}
  return out;
}
