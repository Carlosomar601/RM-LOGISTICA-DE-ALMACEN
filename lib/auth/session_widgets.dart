import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/toast.dart';

/// Diálogo para asignar o cambiar un PIN (4 dígitos + confirmación).
Future<void> showPinDialog(BuildContext context, WidgetRef ref, {required String userId, required String title}) =>
    showDialog<void>(context: context, builder: (_) => _PinDialog(userId: userId, title: title));

class _PinDialog extends ConsumerStatefulWidget {
  const _PinDialog({required this.userId, required this.title});
  final String userId;
  final String title;

  @override
  ConsumerState<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends ConsumerState<_PinDialog> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _save() {
    if (_pin.text != _confirm.text) {
      setState(() => _error = 'Los dos PIN no coinciden.');
      return;
    }
    final err = ref.read(appProvider.notifier).setPin(widget.userId, _pin.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context);
    showToast(ref, 'PIN guardado');
  }

  Widget _field(TextEditingController c, String hint, {bool autofocus = false}) => TextField(
        key: ValueKey('pin-field-$hint'),
        controller: c,
        autofocus: autofocus,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
        style: T.mono(context, size: 20),
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (_) => _save(),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabeledField(label: 'PIN (4 dígitos)', child: _field(_pin, 'Nuevo PIN', autofocus: true)),
            const SizedBox(height: 12),
            LabeledField(label: 'Confirmar PIN', child: _field(_confirm, 'Repetir PIN')),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: T.body(context, size: 12.5, color: c.crit)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Guardar PIN')),
      ],
    );
  }
}

/// Usuario con sesión iniciada + "Cerrar sesión" (pie de la barra lateral).
class SessionPanel extends ConsumerWidget {
  const SessionPanel({super.key, this.compact = false});

  /// Versión de una línea para la barra superior en pantallas angostas.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(appProvider.select((s) => s.currentUser));
    if (u == null) return const SizedBox.shrink();
    final c = context.c;
    void logout() => ref.read(appProvider.notifier).logout();

    final avatar = CircleAvatar(
      radius: compact ? 15 : 17,
      backgroundColor: c.accentSoft,
      child: Text(initials(u.name), style: T.body(context, size: 12, weight: FontWeight.w700, color: c.accent)),
    );

    if (compact) {
      return PopupMenuButton<String>(
        tooltip: '${u.name} · ${u.role}',
        onSelected: (v) => v == 'pin'
            ? showPinDialog(context, ref, userId: u.id, title: 'Cambiar mi PIN')
            : logout(),
        itemBuilder: (_) => [
          PopupMenuItem(enabled: false, child: Text('${u.name} · ${u.role}')),
          const PopupMenuItem(value: 'pin', child: Text('Cambiar mi PIN')),
          const PopupMenuItem(value: 'logout', child: Text('Cerrar sesión')),
        ],
        child: avatar,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            avatar,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.body(context, size: 13, weight: FontWeight.w700)),
                  Text(u.role, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.muted(context, size: 11.5)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: logout,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34), padding: EdgeInsets.zero),
                child: const Text('Cerrar sesión'),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Cambiar mi PIN',
              onPressed: () => showPinDialog(context, ref, userId: u.id, title: 'Cambiar mi PIN'),
              icon: const Icon(Icons.pin_outlined, size: 20),
            ),
          ],
        ),
      ],
    );
  }
}
