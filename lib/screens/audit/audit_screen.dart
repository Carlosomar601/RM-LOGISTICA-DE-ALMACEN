import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rm_core/state/app_state.dart';
import '../../widgets/common.dart';
import 'accuracy_tab.dart';
import 'audit_count_view.dart';
import 'audit_list_tab.dart';
import 'pending_tab.dart';
import 'returns_tab.dart';

enum AuditTab { audits, count, pending, returns, report }

/// Pestañas que ve el usuario según sus permisos: quien administra auditorías ve Auditorías,
/// Contar, Pendientes y Reporte; el Auditor solo Contar; «revisar devoluciones» agrega Devoluciones.
List<AuditTab> auditTabsFor({required bool manage, required bool count, required bool returns}) => [
      if (manage) AuditTab.audits,
      if (manage || count) AuditTab.count,
      if (manage) AuditTab.pending,
      if (returns) AuditTab.returns,
      if (manage) AuditTab.report,
    ];

/// Auditoría de canastas. Supervisor y Administrador: Auditorías, Contar, Pendientes, Devoluciones
/// y Reporte. El Auditor solo ve Contar (conteo a ciegas).
class AuditScreen extends ConsumerWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manage = ref.watch(appProvider.select((s) => s.canManageAudits));
    final count = ref.watch(appProvider.select((s) => s.canCountAudits));
    final returns = ref.watch(appProvider.select((s) => s.canReviewReturns));
    final toReview = ref.watch(appProvider.select((s) => s.returnsToReview));
    final tabs = auditTabsFor(manage: manage, count: count, returns: returns);
    final onlyReturns = tabs.length == 1 && tabs.first == AuditTab.returns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenHeader(
          eyebrow: 'Control de inventario',
          title: onlyReturns ? 'Devoluciones' : 'Auditoría de canastas',
          subtitle: onlyReturns
              ? 'Devoluciones y anulaciones de RM por revisar antes de volver al inventario, '
                  'y lo que el piqueador no encontró en la canasta.'
              : manage
                  ? 'Crea auditorías de una canasta, de varias o de una zona completa. El auditor cuenta a ciegas; '
                      'lo que falta pasa a PENDIENTES con su lote y fecha, y aquí se resuelve.'
                  : 'Escanea la canasta y cada producto con la cantidad que encuentras. '
                      'Mientras cuentas, la canasta queda bloqueada para piqueo y transferencias.',
        ),
        _AuditTabs(key: ValueKey(tabs.join(',')), tabs: tabs, toReview: toReview),
      ],
    );
  }
}

class _AuditTabs extends StatefulWidget {
  const _AuditTabs({super.key, required this.tabs, required this.toReview});
  final List<AuditTab> tabs;
  final int toReview;

  @override
  State<_AuditTabs> createState() => _AuditTabsState();
}

class _AuditTabsState extends State<_AuditTabs> with SingleTickerProviderStateMixin {
  /// Solo existe con más de una pestaña (el Auditor ve directamente «Contar»).
  TabController? _tabs;

  @override
  void initState() {
    super.initState();
    if (widget.tabs.length > 1) {
      _tabs = TabController(length: widget.tabs.length, vsync: this)
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

  String _label(AuditTab t) => switch (t) {
        AuditTab.audits => 'Auditorías',
        AuditTab.count => 'Contar',
        AuditTab.pending => 'Pendientes',
        AuditTab.returns => widget.toReview > 0 ? 'Devoluciones (${widget.toReview})' : 'Devoluciones',
        AuditTab.report => 'Reporte',
      };

  Widget _view(AuditTab t) => switch (t) {
        AuditTab.audits => const AuditListTab(),
        AuditTab.count => const AuditCountView(),
        AuditTab.pending => const PendingTab(),
        AuditTab.returns => const ReturnsTab(),
        AuditTab.report => const AccuracyTab(),
      };

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    if (widget.tabs.isEmpty) return const SizedBox.shrink();
    if (tabs == null) return _view(widget.tabs.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in widget.tabs) Tab(text: _label(t))],
        ),
        const SizedBox(height: 16),
        _view(widget.tabs[tabs.index]),
      ],
    );
  }
}
