import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_widgets.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'sidebar.dart';

/// Barra superior para anchos ≤ 760px: logo (46px) + chips desplazables.
class TopNav extends ConsumerWidget {
  const TopNav({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const AppLogo(height: 46),
                const Spacer(),
                const ThemeToggle(compact: true),
                const SizedBox(width: 10),
                const SessionPanel(compact: true),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final v in AppView.values)
                  Center(
                    child: NavItem(
                      chip: true,
                      label: v.label,
                      badge: navBadge(s, v),
                      active: s.currentView == v,
                      locked: !s.allowed(v),
                      onTap: () => onNavTap(ref, v),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
