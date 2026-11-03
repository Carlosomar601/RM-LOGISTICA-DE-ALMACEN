import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'accuracy_tab.dart';
import 'audit_count_view.dart';
import 'audit_list_tab.dart';
import 'pending_tab.dart';

/// Auditoría de canastas. Supervisor y Administrador: Auditorías, Contar, Pendientes y Reporte.
/// El Auditor solo ve Contar (conteo a ciegas).
class AuditScreen extends ConsumerWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manage = ref.watch(appProvider.select((s) => s.canManageAudits));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenHeader(
          eyebrow: 'Control de inventario',
          title: 'Auditoría de canastas',
          subtitle: manage
              ? 'Crea auditorías de una canasta, de varias o de una zona completa. El auditor cuenta a ciegas; '
                  'lo que falta pasa a PENDIENTES con su lote y fecha, y aquí se resuelve.'
              : 'Escanea la canasta y cada producto con la cantidad que encuentras. '
                  'Mientras cuentas, la canasta queda bloqueada para piqueo y transferencias.',
        ),
        _AuditTabs(key: ValueKey(manage), manage: manage),
      ],
    );
  }
}

class _AuditTabs extends StatefulWidget {
  const _AuditTabs({super.key, required this.manage});
  final bool manage;

  @override
  State<_AuditTabs> createState() => _AuditTabsState();
}

class _AuditTabsState extends State<_AuditTabs> with SingleTickerProviderStateMixin {
  /// Solo existe para quien administra auditorías (el Auditor ve directamente «Contar»).
  TabController? _tabs;

  @override
  void initState() {
    super.initState();
    if (widget.manage) {
      _tabs = TabController(length: 4, vsync: this)
        ..addListener(() {
          if (mounted) setState(() {});
        });
    }
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    if (tabs == null) return const AuditCountView();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Auditorías'),
            Tab(text: 'Contar'),
            Tab(text: 'Pendientes'),
            Tab(text: 'Reporte'),
          ],
        ),
        const SizedBox(height: 16),
        switch (tabs.index) {
          0 => const AuditListTab(),
          1 => const AuditCountView(),
          2 => const PendingTab(),
          _ => const AccuracyTab(),
        },
      ],
    );
  }
}
