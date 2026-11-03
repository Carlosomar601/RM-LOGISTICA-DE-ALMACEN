import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tone.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'user_store.dart';

/// Pantalla de PIN: se muestra mientras no hay sesión iniciada.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  final _focus = FocusNode();
  String _pin = '';
  String? _error;
  Timer? _lockTimer;
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 360));

  @override
  void initState() {
    super.initState();
    _error = ref.read(appProvider).logoutReason;
    _syncLock();
  }

  @override
  void dispose() {
    _focus.dispose();
    _lockTimer?.cancel();
    _shake.dispose();
    super.dispose();
  }

  int get _lockLeft => ref.read(appProvider.notifier).lockSecondsLeft();

  /// Refresca la cuenta regresiva del bloqueo cada segundo.
  void _syncLock() {
    _lockTimer?.cancel();
    if (_lockLeft <= 0) return;
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_lockLeft <= 0) {
        t.cancel();
        setState(() => _error = null);
      } else {
        setState(() => _error = 'Demasiados intentos. Espera $_lockLeft s.');
      }
    });
  }

  void _digit(String d) {
    if (_pin.length >= 4 || _lockLeft > 0) return;
    setState(() {
      _pin += d;
      if (_pin.length == 1) _error = null;
    });
    if (_pin.length == 4) _submit();
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _submit() {
    final err = ref.read(appProvider.notifier).login(_pin);
    if (err == null) return; // la app pasa a la pantalla principal
    setState(() {
      _error = err;
      _pin = '';
    });
    _shake.forward(from: 0);
    _syncLock();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final ch = e.character;
    if (ch != null && RegExp(r'^\d$').hasMatch(ch)) {
      _digit(ch);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace || e.logicalKey == LogicalKeyboardKey.delete) {
      _back();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final c = context.c;
    final demo = ref.watch(userStoreProvider).status == UserStoreStatus.demo;
    final broken = s.userStoreError;
    final locked = _lockLeft > 0;

    return Scaffold(
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(height: 64),
                  const SizedBox(height: 10),
                  Text(
                    '${s.settings.companyName} — ${s.settings.warehouseName}',
                    textAlign: TextAlign.center,
                    style: T.muted(context, size: 13),
                  ),
                  const SizedBox(height: 28),
                  Text('INGRESA TU PIN', style: T.th(context)),
                  const SizedBox(height: 14),
                  AnimatedBuilder(
                    animation: _shake,
                    builder: (context, child) {
                      final t = _shake.value;
                      final dx = t == 0 ? 0.0 : 10 * (1 - t) * (t * 24).remainder(2) * ((t * 12).floor().isEven ? 1 : -1);
                      return Transform.translate(offset: Offset(dx, 0), child: child);
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < 4; i++)
                          Container(
                            key: ValueKey('pin-dot-$i'),
                            width: 18,
                            height: 18,
                            margin: const EdgeInsets.symmetric(horizontal: 9),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < _pin.length ? c.accent : Colors.transparent,
                              border: Border.all(color: i < _pin.length ? c.accent : c.borderStrong, width: 2),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 44,
                    child: Center(
                      child: Text(
                        broken ?? _error ?? '',
                        textAlign: TextAlign.center,
                        style: T.body(context, size: 13, weight: FontWeight.w600, color: c.crit),
                      ),
                    ),
                  ),
                  _Keypad(
                    enabled: broken == null && !locked,
                    onDigit: _digit,
                    onBack: _back,
                  ),
                  if (s.dataStoreError != null) ...[
                    const SizedBox(height: 22),
                    const NoteBox(
                      'Los datos del almacén no se pudieron leer. Un administrador debe entrar y restaurar '
                      'un respaldo en Administración → Respaldos.',
                      tone: Tone.crit,
                    ),
                  ],
                  if (demo) ...[
                    const SizedBox(height: 22),
                    NoteBox(
                      'Modo demostración (sin users.json): administrador 1111, supervisora 2222, piqueador 3333.',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.enabled, required this.onDigit, required this.onBack});
  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget key(String label, VoidCallback? onTap, {String? tooltip}) => Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            width: 84,
            height: 64,
            child: Material(
              color: c.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(R.card),
                side: BorderSide(color: c.border),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(R.card),
                onTap: enabled ? onTap : null,
                child: Center(
                  child: Text(
                    label,
                    semanticsLabel: tooltip ?? label,
                    style: T.mono(context, size: 24, weight: FontWeight.w600, color: enabled ? null : c.inkMuted),
                  ),
                ),
              ),
            ),
          ),
        );

    Widget row(List<Widget> keys) => Row(mainAxisAlignment: MainAxisAlignment.center, children: keys);
    return Column(
      children: [
        row([for (final d in ['1', '2', '3']) key(d, () => onDigit(d))]),
        row([for (final d in ['4', '5', '6']) key(d, () => onDigit(d))]),
        row([for (final d in ['7', '8', '9']) key(d, () => onDigit(d))]),
        row([
          const SizedBox(width: 96),
          key('0', () => onDigit('0')),
          key('⌫', onBack, tooltip: 'Borrar'),
        ]),
      ],
    );
  }
}
