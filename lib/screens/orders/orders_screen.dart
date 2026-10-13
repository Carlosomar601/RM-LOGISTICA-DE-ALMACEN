import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/order.dart';
import '../../models/pick_session.dart';
import '../../models/tone.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../util/format.dart';
import '../../widgets/badge.dart';
import '../../widgets/common.dart';
import '../../widgets/data_table_card.dart';
import '../../widgets/expandable_card.dart';
import '../../widgets/pick_step_row.dart';
import '../../widgets/toast.dart';

(String, Tone) orderStatus(String status) => switch (status) {
      'parcial' => ('Parcial', Tone.warn),
      'completada' => ('Completada', Tone.good),
      _ => ('Pendiente', Tone.neutral),
    };

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() {
      if (mounted) setState(() {});
    });
  final _expanded = <String>{};

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _simulate() {
    final n = ref.read(appProvider.notifier);
    final id = n.simulateOrder();
    final o = ref.read(appProvider).orders.firstWhere((x) => x.id == id);
    setState(() => _expanded.add(id));
    if (_tabs.index != 0) _tabs.animateTo(0);
    showToast(ref, 'Nueva orden $id de ${o.customer} → ${o.store}');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final open = s.openOrders;
    final done = s.completedOrders;
    final list = _tabs.index == 0 ? open : done;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenHeader(
          eyebrow: 'Despacho',
          title: 'Órdenes entrantes',
          subtitle:
              'Órdenes de venta de las sucursales. Calcula la ruta de piqueo FIFO de todos los artículos y verifica cada canasta antes de despachar.',
          actions: [FilledButton(onPressed: _simulate, child: const Text('+ Simular orden entrante'))],
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: 'Pendientes (${open.length})'),
            Tab(text: 'Completadas (${done.length})'),
          ],
        ),
        const SizedBox(height: 16),
        if (list.isEmpty)
          SectionCard(
            child: Text(
              _tabs.index == 0 ? 'No hay órdenes pendientes.' : 'Aún no hay órdenes completadas.',
              style: T.muted(context, size: 13.5),
            ),
          ),
        for (final o in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _OrderCard(
              order: o,
              expanded: _expanded.contains(o.id),
              onToggle: () => setState(() => _expanded.contains(o.id) ? _expanded.remove(o.id) : _expanded.add(o.id)),
            ),
          ),
      ],
    );
  }
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order, required this.expanded, required this.onToggle});
  final Order order;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final n = ref.read(appProvider.notifier);
    final c = context.c;
    final o = order;
    final (label, tone) = orderStatus(o.status);
    final showDelivered = o.items.any((i) => i.delivered > 0);
    final hasRoute = s.orderHasRoute(o);
    final canConfirm = s.orderCanConfirm(o);

    final itemRows = [
      for (final i in o.items)
        () {
          final p = s.product(i.productId);
          final avail = s.central(i.productId);
          final need = o.isOpen ? i.remaining : i.qty;
          final (chip, chipTone) = need == 0
              ? ('Despachado', Tone.good)
              : avail >= need
                  ? ('Disponible', Tone.good)
                  : avail > 0
                      ? ('Parcial', Tone.warn)
                      : ('Sin stock', Tone.crit);
          return TRow([
            tMono(context, p.code, weight: FontWeight.w600),
            tText(context, p.desc),
            tMono(context, '${i.qty}', weight: FontWeight.w600),
            if (showDelivered) tMono(context, '${i.delivered}'),
            tMono(context, '$avail'),
            AppBadge(chip, tone: chipTone),
          ]);
        }(),
    ];

    return ExpandableCard(
      title: '${o.id} — ${o.customer}',
      monoTitle: false,
      subtitle: '${o.store} · ${o.items.length} artículo(s) · ${fmtDate(o.date)}',
      trailing: AppBadge(label, tone: tone),
      expanded: expanded,
      onToggle: onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(R.input + 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: AppTable(
              headerBackground: c.surfaceSunken,
              cellPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              columns: [
                const TCol('Código', width: 130, flex: 0.5),
                const TCol('Descripción', width: 230, flex: 3),
                const TCol('Solicitado', width: 92, flex: 0.2, numeric: true),
                if (showDelivered) const TCol('Entregado', width: 92, flex: 0.2, numeric: true),
                const TCol('Disp. Almacén', width: 112, flex: 0.2, numeric: true),
                const TCol('', width: 116, flex: 0.4),
              ],
              rows: itemRows,
            ),
          ),
          const SizedBox(height: 14),
          if (!o.isOpen)
            const NoteBox('Orden despachada por completo.', tone: Tone.good)
          else ...[
            if (o.status == 'parcial')
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: NoteBox(
                  'Orden parcial: quedan unidades por despachar. Recalcula la ruta para piquear lo pendiente.',
                  tone: Tone.warn,
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: hasRoute
                  ? OutlinedButton(
                      onPressed: () => n.calcOrderRoute(o.id),
                      child: const Text('Calcular ruta de piqueo (todos los artículos)'),
                    )
                  : FilledButton(
                      onPressed: () => n.calcOrderRoute(o.id),
                      child: const Text('Calcular ruta de piqueo (todos los artículos)'),
                    ),
            ),
            if (hasRoute) ...[
              for (final i in o.items.where((i) => i.remaining > 0))
                _ItemBlock(order: o, item: i),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton(
                    onPressed: canConfirm
                        ? () {
                            final partial = n.confirmOrder(o.id);
                            if (partial == null) return;
                            showToast(
                                ref,
                                'Piqueo de orden ${o.id} confirmado'
                                '${partial ? ' (parcial — hay faltantes declarados)' : ''}');
                          }
                        : null,
                    child: const Text('Confirmar piqueo de la orden'),
                  ),
                  if (!canConfirm)
                    Text(
                      'Verifica todas las canastas pendientes (o declara los faltantes) antes de confirmar.',
                      style: T.muted(context, size: 12.5),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ItemBlock extends ConsumerWidget {
  const _ItemBlock({required this.order, required this.item});
  final Order order;
  final OrderItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final key = orderSessionKey(order.id, item.productId);
    final session = s.pickSessions[key];
    final p = s.product(item.productId);
    final c = context.c;
    final need = item.remaining;

    Widget? badge;
    if (session != null) {
      final k = session.steps.where((st) => st.status != StepStatus.missingHere).length;
      badge = k == 0
          ? const AppBadge('Sin existencia en Almacén Central', tone: Tone.crit)
          : k == 1
              ? const AppBadge('1 canasta', tone: Tone.neutral)
              : AppBadge('$k canastas — ninguna sola cubría las $need', tone: Tone.accent);
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(R.tile),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              Text(
                '${p.code} — ${p.desc} (solicitado $need)',
                style: T.body(context, size: 14, weight: FontWeight.w700),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ?badge,
                  if (session != null)
                    TextButton(
                      onPressed: () => ref.read(appProvider.notifier).recalcSession(key),
                      child: const Text('↺ Recalcular ruta'),
                    ),
                ],
              ),
            ],
          ),
          if (item.delivered > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Ya entregado: ${item.delivered} de ${item.qty}', style: T.muted(context, size: 12)),
            ),
          const SizedBox(height: 10),
          if (session == null)
            Text('Calcula la ruta para ver las canastas de este artículo.', style: T.muted(context, size: 12.5))
          else
            PickStepsView(sessionKey: key),
        ],
      ),
    );
  }
}
