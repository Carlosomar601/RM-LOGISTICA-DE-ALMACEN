/// Protocolo entre el servidor de RM Logistics y sus clientes (Windows y Android).
///
/// Un WebSocket por dispositivo en `ws://<servidor>:<puerto>/ws`. Todos los mensajes son
/// objetos JSON con un campo `t` (tipo).
///
/// Cliente → servidor
///   `login`  {pin, device}            → `auth`
///   `resume` {token}                  → `auth` (reconexión sin volver a pedir PIN)
///   `logout` {reason?}
///   `cmd`    {id, name, args, base}   → `patch` (con `ack`) y `result`
///   `rpc`    {id, name, args}         → `rpcResult`
///
/// Servidor → cliente
///   `hello`     {protocol, server, appVersion, demo}
///   `public`    {data}                datos visibles antes de iniciar sesión
///   `auth`      {ok, error?, lockSeconds?, token?, userId?}
///   `snapshot`  {v, data}             estado completo (al iniciar sesión o reconectar)
///   `patch`     {v, data, ack?}       solo las colecciones que cambiaron
///   `result`    {id, error?}
///   `rpcResult` {id, result?, error?}
///   `sync`      {state}               estado de la sincronización con RM
///   `backup`    {state}               estado de los respaldos
///   `toast`     {text}
///   `kicked`    {reason}             la sesión se cerró en el servidor (p. ej. tras restaurar)
library;

/// Sube cuando un cambio del protocolo no es compatible con clientes anteriores.
const kProtocolVersion = 1;

/// Puerto TCP del servidor (RMApiV2 usa 8180).
const kDefaultServerPort = 8190;

/// Puerto UDP en el que el servidor contesta a la búsqueda automática en la red local.
const kDiscoveryPort = 8191;

/// Mensaje de búsqueda que mandan los clientes por broadcast UDP.
const kDiscoveryQuery = 'RMLOGISTICS?';

/// Respuesta del servidor a la búsqueda: `RMLOGISTICS!` seguido de JSON {name, port}.
const kDiscoveryReplyPrefix = 'RMLOGISTICS!';

abstract final class Msg {
  static const login = 'login';
  static const resume = 'resume';
  static const logout = 'logout';
  static const cmd = 'cmd';
  static const rpc = 'rpc';

  static const hello = 'hello';
  static const public = 'public';
  static const auth = 'auth';
  static const snapshot = 'snapshot';
  static const patch = 'patch';
  static const result = 'result';
  static const rpcResult = 'rpcResult';
  static const sync = 'sync';
  static const backup = 'backup';
  static const toast = 'toast';
  static const kicked = 'kicked';
}

/// Normaliza lo que escribe el usuario ("192.168.1.10", "srv:8190", "http://srv") a la URL
/// del WebSocket. Devuelve null si no se puede interpretar.
Uri? serverWsUri(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  s = s.replaceFirst(RegExp(r'^(https?|wss?)://', caseSensitive: false), '');
  s = s.split('/').first;
  if (s.isEmpty) return null;
  final hasPort = RegExp(r':\d+$').hasMatch(s);
  final uri = Uri.tryParse('ws://${hasPort ? s : '$s:$kDefaultServerPort'}/ws');
  if (uri == null || uri.host.isEmpty) return null;
  return uri;
}

/// "host:puerto" para mostrar y guardar.
String serverLabel(Uri ws) => '${ws.host}:${ws.port}';
