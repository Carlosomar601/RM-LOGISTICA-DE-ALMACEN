import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rm_core/remote/remote_app_notifier.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'client_mode.dart';
import 'connect_screen.dart';

/// En un dispositivo cliente: pantalla de conexión hasta tener datos del servidor y, si la
/// conexión se cae, un aviso que bloquea la pantalla mientras se reconecta (nada se pierde:
/// lo que estaba en camino se reenvía al volver).
class ConnectionGate extends ConsumerWidget {
  const ConnectionGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(clientModeProvider) == null) return child;
    if (ref.watch(remoteLinkProvider) == null) return const ConnectScreen();
    final info = ref.watch(connectionProvider);
    if (!info.hasData) return const ConnectScreen();
    return Stack(
      children: [
        child,
        if (!info.online) const Positioned.fill(child: _Offline()),
      ],
    );
  }
}

class _Offline extends ConsumerWidget {
  const _Offline();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final address = ref.watch(clientModeProvider)?.address ?? '';
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxWidth: 380),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(height: 14),
              Text('Sin conexión con el servidor', style: T.h(context, 18), textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(
                'Reconectando con $address… Lo que hiciste se envía al volver la conexión.',
                textAlign: TextAlign.center,
                style: T.muted(context, size: 13),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.read(remoteLinkProvider)?.retryNow(),
                child: const Text('Reintentar ahora'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
