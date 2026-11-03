import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rm_core/models/tone.dart';
import 'package:rm_core/state/app_state.dart';
import '../../theme/tokens.dart';
import 'package:rm_core/util/clock.dart';
import 'package:rm_core/util/format.dart';
import '../../widgets/badge.dart';
import '../../widgets/bin_tag.dart';
import '../../widgets/common.dart';
import '../../widgets/data_table_card.dart';
import '../../widgets/rank_circle.dart';
import '../../widgets/stat_tile.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final c = context.c;
    final activeSkus = s.products.where((p) => s.total(p.id) > 0).length;
    final available = s.totalUnits - s.totalCommitted;

    final rows = <TRow>[];
    for (final p in s.products) {
      final total = s.total(p.id);
      final bins = s.fifoRowsOf(p.id);
      final oldest = bins.isEmpty ? 0 : ageDays(bins.first.entryDate);
      final (estado, tone) = total == 0
          ? ('Agotado', Tone.crit)
          : oldest >= s.settings.ageAlertDays
              ? ('Rotar pronto', Tone.warn)
              : ('Normal', Tone.good);
      final open = _expanded.contains(p.id);
      final disp = s.disponible(p.id);
      rows.add(TRow(
        [
          Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedRotation(
              turns: open ? 0.25 : 0,
              duration: const Duration(milliseconds: 160),
              child: Icon(Icons.chevron_right, size: 18, color: c.inkMuted),
            ),
            const SizedBox(width: 4),
            Flexible(child: tMono(context, p.code, weight: FontWeight.w600)),
          ]),
          tText(context, p.desc),
          tMono(context, fmtInt(total), weight: FontWeight.w600),
          tMono(context, fmtInt(p.committed), muted: p.committed == 0),
          tMono(context, fmtInt(disp), weight: FontWeight.w600, color: disp <= 0 ? c.crit : c.good),
          tMono(context, '${bins.length}'),
          AppBadge(estado, tone: tone),
        ],
        selected: open,
        onTap: () => setState(() => open ? _expanded.remove(p.id) : _expanded.add(p.id)),
        expanded: open ? _BinsTable(productId: p.id) : null,
      ));
    }

    final stale = s.staleRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScreenHeader(
          eyebrow: 'Dashboard',
          title: 'Inventario por localización',
          subtitle:
              'Distribución completa del inventario por bin y tienda. Expande un producto para ver sus localizaciones en orden FIFO.',
        ),
        StatRow(tiles: [
          StatTile(label: 'SKUs activos', value: '$activeSkus', hint: 'de ${s.products.length} productos'),
          StatTile(label: 'Unidades totales', value: fmtInt(s.totalUnits), hint: 'todas las tiendas'),
          StatTile(label: 'Comprometido', value: fmtInt(s.totalCommitted), hint: 'en órdenes abiertas'),
          StatTile(label: 'Disponible real', value: fmtInt(available), tone: Tone.good, hint: 'total − comprometido'),
          StatTile(
            label: 'Alertas de antigüedad',
            value: '${s.ageAlerts}',
            tone: s.ageAlerts > 0 ? Tone.crit : Tone.good,
            hint: 'bins con ≥ ${s.settings.ageAlertDays} días',
          ),
        ]),
        if (s.openAudits.isNotEmpty || s.openPending.isNotEmpty) ...[
          const SizedBox(height: 12),
          StatRow(maxColumns: 3, tiles: [
            StatTile(
              label: 'Auditorías abiertas',
              value: '${s.openAudits.length}',
              hint: '${s.lockedBins.length} canastas bloqueadas',
              tone: s.lockedBins.isEmpty ? null : Tone.warn,
            ),
            StatTile(
              label: 'Pendientes (unid.)',
              value: fmtInt(s.pendingUnits),
              hint: '${s.openPending.length} por resolver en Auditoría',
              tone: s.pendingUnits > 0 ? Tone.warn : Tone.good,
            ),
          ]),
        ],
        const SizedBox(height: 20),
        SectionCard(
          title: 'Productos',
          subtitle: 'Toca un producto para ver todas sus localizaciones.',
          trailing: Pill('${s.products.length} SKUs', mono: true),
          flushBody: true,
          child: AppTable(
            columns: const [
              TCol('Código', width: 150, flex: 0.6),
              TCol('Descripción', width: 250, flex: 3),
              TCol('Total', width: 76, flex: 0.3, numeric: true),
              TCol('Comprometido', width: 118, flex: 0.3, numeric: true),
              TCol('Disponible', width: 100, flex: 0.3, numeric: true),
              TCol('# Bins', width: 70, flex: 0.2, numeric: true),
              TCol('Estado', width: 130, flex: 0.5),
            ],
            rows: rows,
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          title: 'Inventario sin movimiento',
          subtitle:
              'Localizaciones donde el mismo lote lleva más de 6 meses sin que salga por piqueo ni transferencia — candidatas a liquidar, promocionar o auditar.',
          trailing: stale.isEmpty
              ? const Pill('Sin estancados', tone: Tone.good)
              : Pill('${stale.length} localización(es) estancada(s)', tone: Tone.crit),
          flushBody: true,
          child: AppTable(
            columns: const [
              TCol('Código', width: 130, flex: 0.5),
              TCol('Descripción', width: 230, flex: 2.5),
              TCol('Bin', width: 100, flex: 0.2),
              TCol('Tienda/almacén', width: 150, flex: 1),
              TCol('Cant.', width: 64, flex: 0.2, numeric: true),
              TCol('Última entrada', width: 124, flex: 0.5),
              TCol('Recibo', width: 100, flex: 0.4),
              TCol('Sin movimiento', width: 170, flex: 0.6),
            ],
            emptyText: 'No hay inventario estancado — todo se ha movido en los últimos 6 meses.',
            rows: [
              for (final r in stale)
                TRow([
                  tMono(context, s.product(r.productId).code, weight: FontWeight.w600),
                  tText(context, s.product(r.productId).desc),
                  BinTag(r.bin),
                  tText(context, r.store, maxLines: 1),
                  tMono(context, '${r.qty}', weight: FontWeight.w600),
                  tText(context, fmtDate(r.entryDate), maxLines: 1),
                  tMono(context, r.receipt, muted: true),
                  _StaleBadge(days: ageDays(r.entryDate)),
                ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _StaleBadge extends StatelessWidget {
  const _StaleBadge({required this.days});
  final int days;

  @override
  Widget build(BuildContext context) {
    final months = days ~/ 30;
    return AppBadge('$months meses sin moverse', tone: months >= 9 ? Tone.crit : Tone.warn);
  }
}

class _BinsTable extends ConsumerWidget {
  const _BinsTable({required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final bins = s.fifoRowsOf(productId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 6, 16, 12),
      child: AppTable(
        columns: const [
          TCol('FIFO', width: 56, flex: 0),
          TCol('Bin', width: 104, flex: 0.3),
          TCol('Tienda/almacén', width: 170, flex: 1.5),
          TCol('Cant.', width: 64, flex: 0.2, numeric: true),
          TCol('Entrada', width: 116, flex: 0.5),
          TCol('Recibo', width: 98, flex: 0.4),
          TCol('Lote', width: 84, flex: 0.3),
          TCol('Antigüedad', width: 104, flex: 0.4),
        ],
        cellPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        emptyText: 'Sin existencias en ninguna localización.',
        rows: [
          for (var i = 0; i < bins.length; i++)
            TRow([
              RankCircle(i + 1),
              BinTag(bins[i].bin),
              tText(context, bins[i].store, maxLines: 1),
              tMono(context, '${bins[i].qty}', weight: FontWeight.w600),
              tText(context, fmtDate(bins[i].entryDate), maxLines: 1),
              tMono(context, bins[i].receipt, muted: true),
              tMono(context, bins[i].lot, muted: true),
              AgeBadge(ageDays(bins[i].entryDate)),
            ]),
        ],
      ),
    );
  }
}
