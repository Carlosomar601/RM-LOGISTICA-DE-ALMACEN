import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piqueo_fifo_centeno/main.dart';
import 'package:piqueo_fifo_centeno/remote_ui/client_container.dart';
import 'package:piqueo_fifo_centeno/remote_ui/client_mode.dart';
import 'package:rm_core/remote/remote_link.dart';
import 'package:rm_core/state/app_state.dart';
import 'package:rm_server/app_server.dart';

/// La app en modo cliente contra un servidor real (en este mismo proceso, por loopback).
void main() {
  late ProviderContainer serverC;
  late AppServer server;
  late ProviderContainer client;
  late RemoteLink link;

  /// Alterna esperas reales (sockets) con frames: las respuestas del servidor continúan
  /// código de la app que corre en la zona de la prueba.
  Future<void> until(WidgetTester t, bool Function() cond) async {
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      await t.pump();
      if (cond()) break;
      if (DateTime.now().isAfter(end)) throw TimeoutException('condición no cumplida');
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await t.pump();
  }

  Future<void> start(WidgetTester t) async {
    t.view.physicalSize = const Size(1440, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(() async {
      serverC = ProviderContainer();
      server = AppServer(serverC, name: 'servidor-prueba', appVersion: 'test');
      await server.start(port: 0, address: InternetAddress.loopbackIPv4, discovery: false);
      link = RemoteLink(Uri.parse('ws://127.0.0.1:${server.port}/ws'), device: 'prueba');
      client = buildClientContainer(
        link: link,
        mode: ClientMode(address: '127.0.0.1:${server.port}', changeServer: (_) async {}),
      );
      await link.start();
    });
    addTearDown(() async {
      await t.runAsync(() async {
        await link.close();
        client.dispose();
        await server.stop();
        serverC.dispose();
      });
    });
    await t.pumpWidget(UncontrolledProviderScope(container: client, child: const PiqueoApp()));
    await until(t, () => find.text('INGRESA TU PIN').evaluate().isNotEmpty || client.read(appProvider).settings.companyName.isNotEmpty);
    await t.pump();
  }

  Future<void> tapPin(WidgetTester t, String pin) async {
    for (final d in pin.split('')) {
      await t.tap(find.text(d).last);
      await t.pump();
    }
  }

  testWidgets('cliente: PIN en el servidor, datos del servidor y cambios en vivo', (t) async {
    await start(t);
    expect(find.text('INGRESA TU PIN'), findsOneWidget);
    expect(find.textContaining('Servidor: 127.0.0.1'), findsOneWidget);

    await tapPin(t, '9999');
    await until(t, () => find.text('PIN incorrecto').evaluate().isNotEmpty);
    expect(find.text('PIN incorrecto'), findsOneWidget);

    await tapPin(t, '1111');
    await until(t, () => client.read(appProvider).currentUserId != null);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('INGRESA TU PIN'), findsNothing);
    expect(client.read(appProvider).currentUser!.name, 'Carlos Omar');
    expect(client.read(appProvider).products.length, serverC.read(appProvider).products.length);

    // Otro dispositivo (aquí, el propio servidor) cambia los parámetros: llega en vivo.
    await t.runAsync(() async {
      serverC.read(appProvider.notifier).updateSettings(companyName: 'Centeno Tire Norte');
    });
    await until(t, () => client.read(appProvider).settings.companyName == 'Centeno Tire Norte');
    expect(t.takeException(), isNull);
  });

  testWidgets('cliente: si se cae la conexión se bloquea la pantalla y se reconecta solo', (t) async {
    await start(t);
    await tapPin(t, '1111');
    await until(t, () => client.read(appProvider).currentUserId != null);
    await t.runAsync(() => server.dropConnectionsForTest());
    await until(t, () => !link.online);
    expect(find.text('Sin conexión con el servidor'), findsOneWidget);
    await until(t, () => link.online);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    expect(find.text('Sin conexión con el servidor'), findsNothing);
    expect(client.read(appProvider).currentUserId, 'u1', reason: 'la sesión se retoma sin pedir el PIN');
  });
}
