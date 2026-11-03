import 'dart:io';

import 'package:rm_core/remote/commands.dart';
import 'package:rm_core/remote/protocol.dart';
import 'package:test/test.dart';

void main() {
  test('cada acción remota tiene su método en RemoteAppNotifier (y viceversa)', () {
    final src = File('lib/remote/remote_app_notifier.dart').readAsStringSync();
    final sent = RegExp(r"_cmd\(\s*'(\w+)'").allMatches(src).map((m) => m[1]!).toSet();
    expect(sent.difference(kRemoteCommands.keys.toSet()), isEmpty, reason: 'se mandan acciones que el servidor no conoce');
    expect(kRemoteCommands.keys.toSet().difference(sent), isEmpty, reason: 'acciones que el cliente aplicaría solo en local');
  });

  test('dirección del servidor', () {
    expect(serverWsUri('192.168.1.10').toString(), 'ws://192.168.1.10:8190/ws');
    expect(serverWsUri('http://almacen:9000/').toString(), 'ws://almacen:9000/ws');
    expect(serverWsUri('  '), isNull);
  });
}
