import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piqueo_fifo_centeno/main.dart';
import 'package:piqueo_fifo_centeno/shell/sidebar.dart';
import 'package:rm_core/state/app_state.dart';
import 'package:rm_core/sync/sync_service.dart';

class _FakeTimer implements Timer {
  @override
  void cancel() {}
  @override
  bool get isActive => true;
  @override
  int get tick => 0;
}

void main() {
  late ProviderContainer c;
  late DateTime now;
  void Function(Timer)? idleTick;

  Future<void> pump(WidgetTester t, {double width = 1440, ThemeMode mode = ThemeMode.light}) async {
    t.view.physicalSize = Size(width, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    now = DateTime(2026, 10, 13, 9);
    c = ProviderContainer(overrides: [
      clockProvider.overrideWithValue(() => now),
      tickerFactoryProvider.overrideWithValue((d, fn) {
        if (d == const Duration(seconds: 15)) idleTick = fn;
        return _FakeTimer();
      }),
    ]);
    addTearDown(c.dispose);
    c.read(themeModeProvider.notifier).state = mode;
    await t.pumpWidget(UncontrolledProviderScope(container: c, child: const PiqueoApp()));
    await t.pumpAndSettle();
  }

  Future<void> tapPin(WidgetTester t, String pin) async {
    for (final d in pin.split('')) {
      await t.tap(find.text(d).last);
      await t.pump();
    }
    await t.pumpAndSettle();
  }

  for (final width in [360.0, 1440.0]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('pantalla de PIN sin overflow, entrar y cerrar sesión (${width.toInt()}px, ${mode.name})', (t) async {
        await pump(t, width: width, mode: mode);
        expect(find.text('INGRESA TU PIN'), findsOneWidget);
        expect(find.textContaining('Modo demostración'), findsOneWidget);

        await tapPin(t, '9999');
        expect(find.text('PIN incorrecto'), findsOneWidget);
        expect(c.read(appProvider).currentUser, isNull);

        await tapPin(t, '1111');
        expect(c.read(appProvider).currentUser!.name, 'Carlos Omar');
        expect(find.text('INGRESA TU PIN'), findsNothing);
        expect(t.takeException(), isNull);

        if (width >= 761) {
          expect(find.text('Carlos Omar'), findsWidgets);
          await t.tap(find.text('Cerrar sesión'));
        } else {
          await t.tap(find.byTooltip('Carlos Omar · Administrador'));
          await t.pumpAndSettle();
          await t.tap(find.text('Cerrar sesión'));
        }
        await t.pumpAndSettle();
        expect(find.text('INGRESA TU PIN'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('teclado físico: dígitos y borrar', (t) async {
    await pump(t);
    await t.sendKeyEvent(LogicalKeyboardKey.digit2);
    await t.sendKeyEvent(LogicalKeyboardKey.digit9);
    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await t.sendKeyEvent(LogicalKeyboardKey.digit2);
    await t.sendKeyEvent(LogicalKeyboardKey.digit2);
    await t.sendKeyEvent(LogicalKeyboardKey.digit2);
    await t.pumpAndSettle();
    expect(c.read(appProvider).currentUser?.name, 'María Rivera');
  });

  testWidgets('bloqueo tras 5 intentos muestra la cuenta regresiva', (t) async {
    await pump(t);
    for (var i = 0; i < 5; i++) {
      await tapPin(t, '9999');
    }
    expect(find.textContaining('Demasiados intentos'), findsOneWidget);
    await tapPin(t, '1111');
    expect(c.read(appProvider).currentUser, isNull, reason: 'el teclado está deshabilitado');
    now = now.add(const Duration(seconds: 31));
    await t.pump(const Duration(seconds: 1));
    await tapPin(t, '1111');
    expect(c.read(appProvider).currentUser, isNotNull);
  });

  testWidgets('un Piqueador solo ve sus secciones', (t) async {
    await pump(t);
    await tapPin(t, '3333');
    final s = c.read(appProvider);
    expect(s.currentUser!.role, 'Piqueador');
    expect([for (final v in AppView.values) if (s.allowed(v)) v],
        [AppView.dashboard, AppView.orders, AppView.picking, AppView.about]);
  });

  testWidgets('cierre por inactividad vuelve al PIN y lo explica', (t) async {
    await pump(t);
    await tapPin(t, '1111');
    now = now.add(const Duration(minutes: 9));
    idleTick!(_FakeTimer());
    await t.pumpAndSettle();
    expect(c.read(appProvider).currentUser, isNotNull);

    now = now.add(const Duration(minutes: 1));
    idleTick!(_FakeTimer());
    await t.pumpAndSettle();
    expect(c.read(appProvider).currentUser, isNull);
    expect(find.text('Sesión cerrada por inactividad.'), findsOneWidget);
  });

  testWidgets('cambiar mi PIN desde la barra lateral', (t) async {
    await pump(t);
    await tapPin(t, '1111');
    await t.tap(find.byTooltip('Cambiar mi PIN'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('pin-field-Nuevo PIN')), '2222');
    await t.enterText(find.byKey(const ValueKey('pin-field-Repetir PIN')), '2222');
    await t.tap(find.text('Guardar PIN'));
    await t.pumpAndSettle();
    expect(find.text('Ese PIN ya lo usa otro empleado.'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('pin-field-Nuevo PIN')), '8080');
    await t.enterText(find.byKey(const ValueKey('pin-field-Repetir PIN')), '8080');
    await t.tap(find.text('Guardar PIN'));
    await t.pumpAndSettle();
    expect(c.read(appProvider).users.firstWhere((u) => u.id == 'u1').checkPin('8080'), isTrue);
    await t.pump(const Duration(seconds: 5)); // toast
  });
}
