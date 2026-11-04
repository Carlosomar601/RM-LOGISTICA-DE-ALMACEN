import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:riverpod/riverpod.dart';
import 'package:rm_core/api/rm_api.dart';
import 'package:rm_core/models/app_user.dart';
import 'package:rm_core/notify/toast_state.dart';
import 'package:rm_core/remote/commands.dart';
import 'package:rm_core/remote/protocol.dart';
import 'package:rm_core/remote/service_codec.dart';
import 'package:rm_core/remote/wire_state.dart';
import 'package:rm_core/state/app_state.dart';
import 'package:rm_core/sync/sync_service.dart';
import 'package:rm_core/sync/sync_settings.dart';
import 'package:rm_core/util/clock.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'backup_rpc.dart';

/// Sesión iniciada con PIN. Sobrevive a reconexiones del mismo dispositivo.
class ServerSession {
  ServerSession(this.token, this.userId, this.device, this.foreignVersion);
  final String token;
  final String userId;
  final String device;

  /// Última versión del estado que cambió por acción de OTRO dispositivo o del servidor.
  int foreignVersion;
  DateTime lastSeen = DateTime.now();

  /// Resultado de las últimas acciones (por ID): una acción reenviada tras una reconexión
  /// no se aplica dos veces.
  final Map<String, String?> _done = {};
  static const _keep = 500;

  bool isDone(String id) => _done.containsKey(id);
  String? doneError(String id) => _done[id];
  void remember(String id, String? error) {
    _done[id] = error;
    if (_done.length > _keep) _done.remove(_done.keys.first);
  }
}

/// Un WebSocket abierto.
class _Conn {
  _Conn(this.ws, this.ip);
  final WebSocketChannel ws;
  final String ip;
  ServerSession? session;

  void send(Map<String, dynamic> m) {
    try {
      ws.sink.add(jsonEncode(m));
    } catch (_) {}
  }
}

/// Atiende a los dispositivos: es el único que ejecuta acciones y guarda los datos.
///
/// Todas las acciones corren en orden en el mismo hilo de Dart, así que dos piqueadores
/// no pueden tomar el mismo lote: el segundo recibe el error de negocio.
class AppServer {
  AppServer(this.container, {String? name, this.appVersion = ''}) : name = name ?? Platform.localHostname;

  final ProviderContainer container;
  final String name;
  final String appVersion;

  AppNotifier get app => container.read(appProvider.notifier);
  AppState get _state => container.read(appProvider);

  /// Versión del estado compartido; sube con cada cambio.
  int version = 0;
  final Map<String, String> _cache = {};
  final Map<String, dynamic> _wire = {};
  String _publicCache = '';

  final Set<_Conn> _conns = {};
  final Map<String, ServerSession> _sessions = {};
  final Map<String, PinThrottle> _throttles = {};
  final List<ProviderSubscription> _subs = [];
  bool _broadcastScheduled = false;

  HttpServer? _http;
  RawDatagramSocket? _udp;
  late final BackupRpc _backup = BackupRpc(container);

  int get port => _http?.port ?? 0;
  int get connectionCount => _conns.length;
  int get sessionCount => _sessions.length;

  /// Arranca HTTP + WebSocket (y la búsqueda automática por UDP si [discovery]).
  Future<void> start({int port = kDefaultServerPort, InternetAddress? address, bool discovery = true}) async {
    _diff(); // llena el caché con el estado inicial
    _publicCache = jsonEncode(encodePublicState(_state));
    _subs
      ..add(container.listen(appProvider, (_, _) => _scheduleBroadcast()))
      ..add(container.listen(syncProvider, (_, s) => _toSessions({'t': Msg.sync, 'state': encodeSyncState(s)})))
      ..add(container.listen(backupStateProvider, (_, s) => _toSessions({'t': Msg.backup, 'state': s})))
      ..add(container.listen(toastProvider, (_, m) {
        if (m != null) _toSessions({'t': Msg.toast, 'text': m.text});
      }));
    _http = await shelf_io.serve(handler, address ?? InternetAddress.anyIPv4, port);
    if (discovery) await _startDiscovery(_http!.port);
  }

  Future<void> stop() async {
    for (final s in _subs) {
      s.close();
    }
    _subs.clear();
    for (final c in _conns.toList()) {
      await c.ws.sink.close();
    }
    _udp?.close();
    await _http?.close(force: true);
  }

  /// Pruebas: corta todas las conexiones (las sesiones siguen válidas, como tras un corte de Wi-Fi).
  Future<void> dropConnectionsForTest() async {
    for (final c in _conns.toList()) {
      await c.ws.sink.close();
    }
  }

  // ---------- HTTP ----------

  Handler get handler => (Request req) {
    switch (req.url.path) {
      case 'health':
        return Response.ok(
          jsonEncode({
            'ok': true,
            'server': name,
            'appVersion': appVersion,
            'protocol': kProtocolVersion,
            'clients': _conns.length,
            'dataError': _state.dataStoreError,
          }),
          headers: {'content-type': 'application/json'},
        );
      case 'ws':
        final info = req.context['shelf.io.connection_info'];
        final ip = info is HttpConnectionInfo ? info.remoteAddress.address : '?';
        return webSocketHandler((WebSocketChannel ws, String? _) => _onConnect(ws, ip),
            pingInterval: const Duration(seconds: 15))(req);
      default:
        return Response.notFound('RM Logistics server');
    }
  };

  // ---------- Búsqueda en la red local ----------

  Future<void> _startDiscovery(int httpPort) async {
    try {
      final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kDiscoveryPort, reuseAddress: true);
      _udp = udp;
      udp.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = udp.receive();
        if (d == null || utf8.decode(d.data, allowMalformed: true).trim() != kDiscoveryQuery) return;
        final reply = '$kDiscoveryReplyPrefix${jsonEncode({'name': name, 'port': httpPort})}';
        udp.send(utf8.encode(reply), d.address, d.port);
      });
    } catch (e) {
      stderr.writeln('Búsqueda automática no disponible (puerto UDP $kDiscoveryPort): $e');
    }
  }

  // ---------- Conexiones ----------

  void _onConnect(WebSocketChannel ws, String ip) {
    final c = _Conn(ws, ip);
    _conns.add(c);
    c.send({'t': Msg.hello, 'protocol': kProtocolVersion, 'server': name, 'appVersion': appVersion, 'demo': demoMode});
    c.send({'t': Msg.public, 'data': encodePublicState(_state)});
    ws.stream.listen(
      (data) {
        try {
          final m = jsonDecode(data as String);
          if (m is Map) _onMessage(c, Map<String, dynamic>.from(m));
        } catch (e) {
          stderr.writeln('Mensaje inválido de $ip: $e');
        }
      },
      onDone: () => _conns.remove(c),
      onError: (_) => _conns.remove(c),
    );
  }

  void _onMessage(_Conn c, Map<String, dynamic> m) {
    c.session?.lastSeen = DateTime.now();
    switch (m['t']) {
      case Msg.login:
        _login(c, m);
      case Msg.resume:
        _resume(c, m);
      case Msg.logout:
        _logout(c, m['reason'] as String?);
      case Msg.cmd:
        _command(c, m);
      case Msg.rpc:
        _rpc(c, m);
    }
  }

  AppUser? _userOf(ServerSession s) => _state.users.where((u) => u.id == s.userId && u.active).firstOrNull;

  String _newToken() {
    final r = Random.secure();
    return List.generate(24, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  void _login(_Conn c, Map<String, dynamic> m) {
    final th = _throttles.putIfAbsent(c.ip, PinThrottle.new);
    String? userId;
    final err = app.runAs(null, () {
      final e = app.login('${m['pin'] ?? ''}', throttle: th);
      if (e == null) userId = _state.currentUserId;
      return e;
    });
    if (err != null || userId == null) {
      c.send({
        't': Msg.auth,
        'id': m['id'],
        'ok': false,
        'error': err ?? 'No se pudo iniciar sesión.',
        'lockSeconds': app.lockSecondsLeft(throttle: th),
      });
      return;
    }
    final s = ServerSession(_newToken(), userId!, '${m['device'] ?? c.ip}', version);
    _sessions[s.token] = s;
    _expireSessions();
    _startSession(c, s, m['id']);
  }

  void _resume(_Conn c, Map<String, dynamic> m) {
    final s = _sessions['${m['token']}'];
    if (s == null || _userOf(s) == null) {
      c.send({'t': Msg.auth, 'id': m['id'], 'ok': false, 'error': 'La sesión ya no es válida.'});
      return;
    }
    s.foreignVersion = version;
    _startSession(c, s, m['id']);
  }

  void _startSession(_Conn c, ServerSession s, Object? reqId) {
    c.session = s;
    c.send({'t': Msg.snapshot, 'v': version, 'data': _wire});
    c.send({'t': Msg.sync, 'state': encodeSyncState(container.read(syncProvider))});
    c.send({'t': Msg.backup, 'state': container.read(backupStateProvider)});
    c.send({'t': Msg.auth, 'id': reqId, 'ok': true, 'token': s.token, 'userId': s.userId});
  }

  void _logout(_Conn c, String? reason) {
    final s = c.session;
    if (s == null) return;
    app.runAs(s.userId, () => app.logout(reason: reason));
    _sessions.remove(s.token);
    c.session = null;
    c.send({'t': Msg.public, 'data': encodePublicState(_state)});
  }

  /// Sesiones sin actividad en 24 h.
  void _expireSessions() {
    final limit = DateTime.now().subtract(const Duration(hours: 24));
    final active = {for (final c in _conns) c.session?.token};
    _sessions.removeWhere((t, s) => !active.contains(t) && s.lastSeen.isBefore(limit));
  }

  // ---------- Acciones ----------

  void _command(_Conn c, Map<String, dynamic> m) {
    final id = '${m['id']}';
    void reply(String? error) => c.send({'t': Msg.result, 'id': id, 'error': ?error});

    final s = c.session;
    if (s == null) return reply('Inicia sesión de nuevo.');
    if (s.isDone(id)) return reply(s.doneError(id));
    final user = _userOf(s);
    if (user == null) return reply('Tu usuario está inactivo. Avisa al administrador.');
    final cmd = kRemoteCommands['${m['name']}'];
    if (cmd == null) return reply('Acción desconocida: ${m['name']}. Actualiza la app.');
    final args = Map<String, dynamic>.from((m['args'] as Map?) ?? const {});
    String? error;
    if (!cmd.can(user, args)) {
      error = 'No tienes permiso para esta acción.';
    } else if (cmd.createsId && ((m['base'] as num?)?.toInt() ?? -1) < s.foreignVersion) {
      error = 'Otro dispositivo cambió los datos al mismo tiempo. Intenta de nuevo.';
    } else {
      try {
        error = cmd.errorOf(app.runAs(user.id, () => cmd.run(app, args)));
      } catch (e) {
        error = 'Error en el servidor: $e';
      }
    }
    _broadcast(origin: s, ack: id);
    s.remember(id, error);
    reply(error);
  }

  Future<void> _rpc(_Conn c, Map<String, dynamic> m) async {
    void reply(Map<String, dynamic> r) => c.send({'t': Msg.rpcResult, 'id': m['id'], ...r});
    final s = c.session;
    final user = s == null ? null : _userOf(s);
    if (user == null) return reply({'error': 'Inicia sesión de nuevo.'});
    final a = Map<String, dynamic>.from((m['args'] as Map?) ?? const {});
    bool need(bool ok) {
      if (!ok) reply({'error': 'No tienes permiso para esta acción.'});
      return ok;
    }

    try {
      final name = '${m['name']}';
      final sync = container.read(syncProvider.notifier);
      switch (name) {
        case 'fetchReceiptLines':
          if (!need(user.can(Area.receiving))) return;
          final lines = await app.fetchReceiptLines(
              '${a['storeId']}', DateTime.parse('${a['from']}'), DateTime.parse('${a['to']}'));
          return reply({
            'result': [for (final l in lines) l.toJson()],
          });
        case 'confirmPin':
          // Confirmación con el PIN propio (p. ej. antes de restaurar). Cuenta como intento fallido.
          final th = _throttles.putIfAbsent(c.ip, PinThrottle.new);
          if (app.lockSecondsLeft(throttle: th) > 0) return reply({'result': false});
          final ok = user.checkPin('${a['pin'] ?? ''}');
          if (!ok && ++th.failed >= AppNotifier.maxPinAttempts) {
            th
              ..failed = 0
              ..lockedUntil = DateTime.now().add(AppNotifier.lockDuration);
          }
          return reply({'result': ok});
        case 'testStoreConnection':
          if (!need(user.can(Area.users))) return;
          return reply({'result': await app.testStoreConnection('${a['id']}')});
        case 'sync.now':
          if (!need(user.can(Area.orders) || user.can(Area.users))) return;
          final parts = await sync.syncNow();
          return reply({
            'result': [for (final p in parts) encodeSyncPart(p)],
          });
        case 'sync.setInterval':
          if (!need(user.can(Area.users))) return;
          sync.setInterval(SyncInterval.values.byName('${a['value']}'));
          return reply({'result': true});
        case 'sync.setLookbackDays':
          if (!need(user.can(Area.users))) return;
          sync.setLookbackDays((a['value'] as num).toInt());
          return reply({'result': true});
        case 'sync.setSkipTransactions':
          if (!need(user.can(Area.users))) return;
          sync.setSkipTransactions({for (final x in a['value'] as List) (x as num).toInt()});
          return reply({'result': true});
        case 'sync.setReturnsEnabled':
          if (!need(user.can(Area.users))) return;
          sync.setReturnsEnabled(a['value'] == true);
          return reply({'result': true});
        case 'sync.setReturnsFirstRunDays':
          if (!need(user.can(Area.users))) return;
          sync.setReturnsFirstRunDays((a['value'] as num).toInt());
          return reply({'result': true});
        default:
          if (name.startsWith('backup.')) {
            if (!need(user.can(Area.users))) return;
            final r = await _backup.call(name, a, userId: user.id);
            _broadcast();
            reply({'result': r});
            // Restaurado: los usuarios y PIN pudieron cambiar; todos vuelven a entrar.
            if (name == 'backup.restore' && r == null) _kickAll('Respaldo restaurado. Entra con tu PIN.');
            return;
          }
          return reply({'error': 'Consulta desconocida: $name. Actualiza la app.'});
      }
    } on RmApiException catch (e) {
      reply({'error': e.message, 'notAvailable': e.notAvailable});
    } on BackupRpcException catch (e) {
      reply({'error': e.message});
    } catch (e) {
      reply({'error': 'Error en el servidor: $e'});
    }
  }

  // ---------- Difusión de cambios ----------

  /// Colecciones que cambiaron desde la última difusión.
  Map<String, dynamic> _diff() {
    final changed = <String, dynamic>{};
    encodeWireState(_state).forEach((k, v) {
      final enc = jsonEncode(v);
      if (_cache[k] != enc) {
        _cache[k] = enc;
        changed[k] = v;
      }
    });
    if (changed.isNotEmpty) {
      version++;
      _wire.addAll(changed);
    }
    return changed;
  }

  void _scheduleBroadcast() {
    if (_broadcastScheduled) return;
    _broadcastScheduled = true;
    scheduleMicrotask(() {
      _broadcastScheduled = false;
      _broadcast();
    });
  }

  /// Manda los cambios a todos. [origin] = sesión que causó el cambio (recibe el `ack`).
  void _broadcast({ServerSession? origin, String? ack}) {
    final changed = _diff();
    if (changed.isEmpty) return;
    for (final s in _sessions.values) {
      if (s != origin) s.foreignVersion = version;
    }
    for (final c in _conns) {
      final s = c.session;
      if (s == null) continue;
      c.send({
        't': Msg.patch,
        'v': version,
        'data': changed,
        if (s == origin && ack != null) 'ack': ack,
      });
    }
    final pub = jsonEncode(encodePublicState(_state));
    if (pub != _publicCache) {
      _publicCache = pub;
      for (final c in _conns) {
        if (c.session == null) c.send({'t': Msg.public, 'data': encodePublicState(_state)});
      }
    }
  }

  /// Cierra todas las sesiones (después de restaurar un respaldo).
  void _kickAll(String reason) {
    _sessions.clear();
    for (final c in _conns) {
      if (c.session == null) continue;
      c.session = null;
      c.send({'t': Msg.kicked, 'reason': reason});
      c.send({'t': Msg.public, 'data': encodePublicState(_state)});
    }
  }

  void _toSessions(Map<String, dynamic> m) {
    for (final c in _conns) {
      if (c.session != null) c.send(m);
    }
  }
}
