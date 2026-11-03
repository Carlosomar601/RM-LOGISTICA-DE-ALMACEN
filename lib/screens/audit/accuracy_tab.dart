import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rm_core/models/tone.dart';
import 'package:rm_core/state/app_state.dart';
import 'package:rm_core/state/audit_engine.dart';
import 'package:rm_core/util/clock.dart';
import 'package:rm_core/util/format.dart';
import '../../widgets/badge.dart';
import '../../widgets/common.dart';
import '../../widgets/data_table_card.dart';
import '../../widgets/stat_tile.dart';
import 'audit_list_tab.dart' show fmtPct;

const _periods = <(int?, String)>[
  (7, 'Últimos 7 días'),
  (30, 'Últimos 30 días'),
  (90, 'Últimos 90 días'),
  (null, 'Todo'),
];

Tone _accTone(double v) => v >= 0.98 ? Tone.good : (v >= 0.9 ? Tone.warn : Tone.crit);

/// Reporte de exactitud de las canastas cerradas: por canasta, zona, auditor y motivo.
class AccuracyTab extends ConsumerStatefulWidget {
  const AccuracyTab({super.key});

  @override
  ConsumerState<AccuracyTab> createState() => _AccuracyTabState();
}

class _AccuracyTabState extends ConsumerState<AccuracyTab> {
  int? _days = 30;
  AccuracyGroup _group = AccuracyGroup.canasta;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final from = _days == null ? null : kToday.subtract(Duration(days: _days!));
    final bins = closedAuditBins(s.audits, from: from).toList();
    final total = accuracyTotal(s.audits, from: from);
    final rows = accuracyBy(s.audits, _group, from: from);
    final byMotivo = _group == AccuracyGroup.motivo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            LabeledField(
              label: 'Periodo (fecha de cierre)',
              width: 220,
              child: AppDropdown<int?>(
                value: _days,
                items: [for (final (d, l) in _periods) ddItem<int?>(context, d, l)],
                onChanged: (v) => setState(() => _days = v),
              ),
            ),
            LabeledField(
              label: 'Agrupar por',
              width: 200,
              child: AppDropdown<AccuracyGroup>(
                value: _group,
                items: [for (final g in AccuracyGroup.values) ddItem(context, g, kAccuracyGroupLabels[g]!)],
                onChanged: (v) => setState(() => _group = v ?? _group),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        StatRow(maxColumns: 4, tiles: [
          StatTile(label: 'Canastas auditadas', value: '${bins.length}'),
          StatTile(label: 'Líneas contadas', value: fmtInt(total.lines), hint: '${total.lines - total.okLines} con diferencia'),
          StatTile(
            label: 'Exactitud por línea',
            value: total.lines == 0 ? '—' : fmtPct(total.lineAccuracy),
            tone: total.lines == 0 ? null : _accTone(total.lineAccuracy),
          ),
          StatTile(
            label: 'Exactitud por unidades',
            value: total.lines == 0 ? '—' : fmtPct(total.unitAccuracy),
            hint: '${fmtInt(total.diffUnits)} u. de diferencia',
            tone: total.lines == 0 ? null : _accTone(total.unitAccuracy),
          ),
        ]),
        const SizedBox(height: 20),
        SectionCard(
          title: 'Exactitud por ${kAccuracyGroupLabels[_group]!.toLowerCase()}',
          subtitle: byMotivo
              ? 'Solo las líneas con diferencia, agrupadas por el motivo asignado al cerrar.'
              : 'Exactitud por línea = líneas OK / líneas. Por unidades = 1 − diferencias / unidades esperadas.',
          flushBody: true,
          child: AppTable(
            emptyText: 'No hay canastas cerradas en este periodo.',
            columns: [
              TCol(kAccuracyGroupLabels[_group]!, width: 160, flex: 1),
              const TCol('Líneas', width: 80, flex: 0, numeric: true),
              if (!byMotivo) const TCol('OK', width: 70, flex: 0, numeric: true),
              const TCol('Esperado', width: 90, flex: 0, numeric: true),
              const TCol('Diferencia', width: 100, flex: 0, numeric: true),
              if (!byMotivo) const TCol('Exactitud línea', width: 130, flex: 0),
              if (!byMotivo) const TCol('Exactitud unid.', width: 130, flex: 0),
            ],
            rows: [
              for (final r in rows)
                TRow([
                  _group == AccuracyGroup.canasta ? tMono(context, r.key, weight: FontWeight.w600) : tText(context, r.key),
                  tMono(context, '${r.lines}'),
                  if (!byMotivo) tMono(context, '${r.okLines}'),
                  tMono(context, fmtInt(r.expectedUnits)),
                  tMono(context, fmtInt(r.diffUnits), weight: FontWeight.w600),
                  if (!byMotivo)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppBadge(fmtPct(r.lineAccuracy), tone: _accTone(r.lineAccuracy)),
                    ),
                  if (!byMotivo)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppBadge(fmtPct(r.unitAccuracy), tone: _accTone(r.unitAccuracy)),
                    ),
                ]),
            ],
          ),
        ),
      ],
    );
  }
}
