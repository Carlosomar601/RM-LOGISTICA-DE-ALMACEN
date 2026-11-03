import 'dart:async';

import 'package:riverpod/riverpod.dart';

/// Mensaje breve para el usuario. La app lo pinta con `ToastHost`; el servidor
/// lo reenvía a los clientes conectados.
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
