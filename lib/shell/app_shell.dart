import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/about/about_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/history/history_screen.dart';
import '../screens/orders/orders_screen.dart';
import '../screens/picking/picking_screen.dart';
import '../screens/receiving/receiving_screen.dart';
import '../screens/transfers/transfers_screen.dart';
import '../screens/admin/admin_screen.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/toast.dart';
import 'sidebar.dart';
import 'top_nav.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(appProvider.select((s) => s.currentView));
    return Scaffold(
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 761;
        final content = _Content(view: view, hPad: wide ? 32 : 16);
        return Stack(
          children: [
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [const Sidebar(), Expanded(child: content)],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [const SafeArea(bottom: false, child: TopNav()), Expanded(child: content)],
              ),
            const ToastHost(),
          ],
        );
      }),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.view, required this.hPad});
  final AppView view;
  final double hPad;

  Widget _screen() => switch (view) {
        AppView.dashboard => const DashboardScreen(),
        AppView.receiving => const ReceivingScreen(),
        AppView.orders => const OrdersScreen(),
        AppView.picking => const PickingScreen(),
        AppView.transfers => const TransfersScreen(),
        AppView.history => const HistoryScreen(),
        AppView.users => const AdminScreen(),
        AppView.about => const AboutScreen(),
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SimulationBanner(),
        Expanded(
          child: SingleChildScrollView(
            key: PageStorageKey('scroll-${view.name}'),
            padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 64),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1360),
                child: KeyedSubtree(key: ValueKey(view), child: _screen()),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Banner fijo mientras se simula un usuario.
class SimulationBanner extends ConsumerWidget {
  const SimulationBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(appProvider).simulatedUser;
    if (u == null) return const SizedBox.shrink();
    final c = context.c;
    return Container(
      color: c.accent,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            '👁 Viendo el dashboard como ${u.name} (${u.role}) — solo se muestran las secciones permitidas para su rol.',
            style: T.body(context, size: 13, weight: FontWeight.w600, color: c.accentInk),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: c.accentInk,
              side: BorderSide(color: c.accentInk.withValues(alpha: 0.7)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 32),
            ),
            onPressed: () => ref.read(appProvider.notifier).exitSimulation(),
            child: const Text('Salir de la vista previa'),
          ),
        ],
      ),
    );
  }
}
