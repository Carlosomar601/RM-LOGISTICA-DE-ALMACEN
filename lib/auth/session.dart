import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rm_core/state/app_state.dart';
import 'package:rm_core/sync/sync_service.dart';
import 'login_screen.dart';

/// Muestra la pantalla de PIN o la app, y cierra la sesión tras [AppSettings.autoLogoutMinutes]
/// sin tocar la pantalla ni el teclado.
class SessionGate extends ConsumerStatefulWidget {
  const SessionGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends ConsumerState<SessionGate> {
  DateTime _lastActivity = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _lastActivity = ref.read(clockProvider)();
    _ticker = ref.read(tickerFactoryProvider)(const Duration(seconds: 15), (_) => checkIdle());
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent _) {
    _touch();
    return false; // no consume la tecla
  }

  void _touch() => _lastActivity = ref.read(clockProvider)();

  void checkIdle() {
    final s = ref.read(appProvider);
    final minutes = s.settings.autoLogoutMinutes;
    if (s.currentUser == null || minutes <= 0) return;
    if (ref.read(clockProvider)().difference(_lastActivity) >= Duration(minutes: minutes)) {
      ref.read(appProvider.notifier).logout(reason: 'inactividad');
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(appProvider.select((s) => s.currentUserId != null));
    // Al iniciar sesión, la inactividad cuenta desde ese momento.
    ref.listen(appProvider.select((s) => s.currentUserId), (_, _) => _touch());
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _touch(),
      onPointerSignal: (_) => _touch(),
      child: signedIn ? widget.child : const LoginScreen(),
    );
  }
}
