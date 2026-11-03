import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'protocol.dart';

enum LinkStatus { connecting, online, offline }

/// La conexión se cayó antes de recibir la respuesta.
class RemoteOfflineException implements Exception {
  const RemoteOfflineException([this.message = 'Sin conexión con el servidor.']);
  final String message;
  @override
  String toString() => message;
}

/// WebSocket hacia el servidor con reconexión automática.
///
/// Los mensajes del servidor llegan por [messages]. [request] manda un mensaje con `id`
/// y espera la respuesta que traiga el mismo `id`.
class RemoteLink {
  RemoteLink(
    this.uri, {
    this.device = 'dispositivo',
    WebSocketChannel Function(Uri uri)? connect,
    this.retryDelays = const [Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 5)],
  }) : _connectFn = connect ?? WebSocketChannel.connect;

  final Uri uri;

  /// Nombre del equipo, para el registro de accesos del servidor.
  final String device;
  final WebSocketChannel Function(Uri) _connectFn;
  final List<Duration> retryDelays;

  final _messages = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final _statusCtl = StreamController<LinkStatus>.broadcast(sync: true);
  final _waiting = <String, Completer<Map<String, dynamic>>>{};

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _retry;
  bool _closed = false;
  int _attempt = 0;
  int _seq = 0;
  final String _prefix = Random().nextInt(1 << 32).toRadixString(36);

  LinkStatus _status = LinkStatus.connecting;
  LinkStatus get status => _status;
  bool get online => _status == LinkStatus.online;

  /// Último error de conexión, para mostrarlo en la pantalla de conexión.
  String? lastError;

  Stream<Map<String, dynamic>> get messages => _messages.stream;
  Stream<LinkStatus> get statusChanges => _statusCtl.stream;

  /// ID único de mensaje (el servidor lo usa también para no aplicar dos veces una acción).
  String nextId() => '$_prefix-${_seq++}';

  void _setStatus(LinkStatus s) {
    if (_status == s) return;
    _status = s;
    _statusCtl.add(s);
  }

  /// Abre la conexión (y la reabre sola si se cae, hasta [close]).
  Future<void> start() => _connect();

  Future<void> _connect() async {
    if (_closed) return;
    _retry?.cancel();
    _setStatus(LinkStatus.connecting);
    final WebSocketChannel ch;
    try {
      ch = _connectFn(uri);
      await ch.ready.timeout(const Duration(seconds: 8));
    } catch (e) {
      lastError = '$e';
      _scheduleRetry();
      return;
    }
    if (_closed) {
      ch.sink.close();
      return;
    }
    _ch = ch;
    _attempt = 0;
    lastError = null;
    _sub = ch.stream.listen(
      (data) {
        final Object? m;
        try {
          m = jsonDecode(data as String);
        } catch (_) {
          return;
        }
        if (m is! Map) return;
        final msg = Map<String, dynamic>.from(m);
        final id = msg['id'];
        if (id is String && msg['t'] != Msg.result) _waiting.remove(id)?.complete(msg);
        _messages.add(msg);
      },
      onDone: _onDown,
      onError: (Object e) {
        lastError = '$e';
        _onDown();
      },
      cancelOnError: true,
    );
    _setStatus(LinkStatus.online);
  }

  void _onDown() {
    _sub?.cancel();
    _sub = null;
    _ch = null;
    for (final c in _waiting.values) {
      if (!c.isCompleted) c.completeError(const RemoteOfflineException());
    }
    _waiting.clear();
    if (_closed) return;
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _setStatus(LinkStatus.offline);
    if (_closed) return;
    final d = retryDelays[min(_attempt, retryDelays.length - 1)];
    _attempt++;
    _retry = Timer(d, _connect);
  }

  /// Reintenta ya (botón «Reintentar»).
  void retryNow() {
    if (_closed || online) return;
    _connect();
  }

  /// Manda un mensaje si hay conexión. Devuelve false si no se pudo.
  bool send(Map<String, dynamic> msg) {
    final ch = _ch;
    if (ch == null || !online) return false;
    ch.sink.add(jsonEncode(msg));
    return true;
  }

  /// Manda [msg] con un `id` nuevo y espera la respuesta con ese `id`.
  Future<Map<String, dynamic>> request(Map<String, dynamic> msg, {Duration timeout = const Duration(seconds: 60)}) {
    final id = nextId();
    final c = Completer<Map<String, dynamic>>();
    _waiting[id] = c;
    if (!send({...msg, 'id': id})) {
      _waiting.remove(id);
      return Future.error(const RemoteOfflineException());
    }
    return c.future.timeout(
      timeout,
      onTimeout: () {
        _waiting.remove(id);
        throw const RemoteOfflineException('El servidor no respondió a tiempo.');
      },
    );
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    await _sub?.cancel();
    await _ch?.sink.close();
    _ch = null;
    _onDown();
    _setStatus(LinkStatus.offline);
  }
}
