import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

class ToastMsg {
  const ToastMsg(this.id, this.text);
  final int id;
  final String text;
}

class ToastNotifier extends Notifier<ToastMsg?> {
  Timer? _timer;
  int _seq = 0;

  @override
  ToastMsg? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void show(String text) {
    _timer?.cancel();
    state = ToastMsg(++_seq, text);
    _timer = Timer(const Duration(milliseconds: 2600), () => state = null);
  }
}

final toastProvider = NotifierProvider<ToastNotifier, ToastMsg?>(ToastNotifier.new);

void showToast(WidgetRef ref, String text) => ref.read(toastProvider.notifier).show(text);

/// Pill flotante abajo a la derecha (fondo ink), se oculta sola a los ~2.6 s.
class ToastHost extends ConsumerWidget {
  const ToastHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final msg = ref.watch(toastProvider);
    final c = context.c;
    final width = MediaQuery.sizeOf(context).width;
    return Positioned(
      right: 20,
      bottom: 20,
      child: IgnorePointer(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(anim),
              child: child,
            ),
          ),
          child: msg == null
              ? const SizedBox.shrink()
              : ConstrainedBox(
                  key: ValueKey(msg.id),
                  constraints: BoxConstraints(maxWidth: (width - 40).clamp(200.0, 460.0)),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        color: c.ink,
                        borderRadius: BorderRadius.circular(R.pill + 4),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 6)),
                        ],
                      ),
                      child: Text(msg.text, style: T.body(context, size: 13, weight: FontWeight.w500, color: c.bg)),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
