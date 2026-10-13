import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/pick_step_row.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// Badge de cada ítem de navegación (null = sin badge).
String? navBadge(AppState s, AppView v) => switch (v) {
      AppView.dashboard => '${s.products.length}',
      AppView.receiving => '${s.pendingReceipts.length}',
      AppView.orders => '${s.openOrders.length}',
      AppView.history => '${s.history.length}',
      AppView.users => '${s.users.length}',
      _ => null,
    };

void onNavTap(WidgetRef ref, AppView v) {
  final ok = ref.read(appProvider.notifier).navigate(v);
  if (!ok) showLockedToast(ref);
}

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final c = context.c;
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            // El logo ya incluye "Logistics & Warehouse".
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 6),
            child: const Align(alignment: Alignment.centerLeft, child: AppLogo(height: 84)),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                for (final v in AppView.values)
                  NavItem(
                    label: v.label,
                    badge: navBadge(s, v),
                    active: s.currentView == v,
                    locked: !s.allowed(v),
                    onTap: () => onNavTap(ref, v),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ThemeToggle(),
                const SizedBox(height: 12),
                Text('Demo funcional · datos de ejemplo', style: T.muted(context, size: 11.5)),
                const SizedBox(height: 2),
                Text('Centeno Tire — Almacén Central',
                    style: T.body(context, size: 11.5, weight: FontWeight.w600, color: c.inkMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class NavItem extends StatelessWidget {
  const NavItem({
    super.key,
    required this.label,
    required this.active,
    required this.locked,
    required this.onTap,
    this.badge,
    this.chip = false,
  });

  final String label;
  final String? badge;
  final bool active;
  final bool locked;
  final VoidCallback onTap;

  /// Variante compacta para la barra superior (≤760px).
  final bool chip;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = active ? c.accent : c.ink;
    final item = Material(
      color: active ? c.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(chip ? R.pill : R.input),
      child: InkWell(
        borderRadius: BorderRadius.circular(chip ? R.pill : R.input),
        onTap: onTap,
        child: Container(
          padding: chip
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 7)
              : const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: chip && !active
              ? BoxDecoration(
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(R.pill),
                )
              : null,
          child: Row(
            mainAxisSize: chip ? MainAxisSize.min : MainAxisSize.max,
            children: [
              if (locked) ...[Icon(Icons.lock_outline, size: 13, color: c.inkMuted), const SizedBox(width: 6)],
              chip
                  ? Text(label, style: T.body(context, size: 13, weight: active ? FontWeight.w600 : FontWeight.w500, color: fg))
                  : Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.body(context, size: 13.5, weight: active ? FontWeight.w600 : FontWeight.w500, color: fg),
                      ),
                    ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: active ? c.surface : c.surfaceSunken,
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                  child: Text(badge!,
                      style: T.mono(context, size: 10.5, weight: FontWeight.w600, color: active ? c.accent : c.inkMuted)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: chip ? const EdgeInsets.only(right: 6) : const EdgeInsets.only(bottom: 2),
      child: Opacity(opacity: locked ? 0.35 : 1, child: item),
    );
  }
}

/// Selector de tema: sistema / claro / oscuro.
class ThemeToggle extends ConsumerWidget {
  const ThemeToggle({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final c = context.c;
    Widget seg(ThemeMode m, IconData icon, String tip) {
      final on = mode == m;
      return Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => ref.read(themeModeProvider.notifier).state = m,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: on ? c.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: on ? Border.all(color: c.borderStrong) : null,
            ),
            child: Icon(icon, size: 16, color: on ? c.accent : c.inkMuted),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.surfaceSunken, borderRadius: BorderRadius.circular(R.input)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(ThemeMode.system, Icons.brightness_auto_outlined, 'Tema del sistema'),
          seg(ThemeMode.light, Icons.light_mode_outlined, 'Tema claro'),
          seg(ThemeMode.dark, Icons.dark_mode_outlined, 'Tema oscuro'),
        ],
      ),
    );
  }
}
