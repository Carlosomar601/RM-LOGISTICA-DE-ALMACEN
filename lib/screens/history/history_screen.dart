import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/movement.dart';
import '../../models/tone.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../../util/format.dart';
import '../../widgets/badge.dart';
import '../../widgets/common.dart';
import '../../widgets/data_table_card.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final c = context.c;
    final rows = s.history.where((m) => _filter == null || m.type == _filter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScreenHeader(
          eyebrow: 'Trazabilidad',
          title: 'Historial de movimientos',
          subtitle:
              'Entradas, piqueos, transferencias, recepciones, auditorías, pendientes y ajustes — con documento, motivo, usuario, fecha y hora.',
        ),
        SectionCard(
          title: 'Movimientos',
          trailing: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: AppDropdown<String?>(
                  value: _filter,
                  items: [for (final (k, label) in kHistoryFilters) ddItem<String?>(context, k, label)],
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              Pill('${rows.length} movimientos', mono: true),
            ],
          ),
          flushBody: true,
          child: AppTable(
            columns: const [
              TCol('Tipo', width: 140, flex: 0.3),
              TCol('Producto', width: 130, flex: 0.4),
              TCol('Documento', width: 100, flex: 0.3),
              TCol('Cant.', width: 64, flex: 0.1, numeric: true),
              TCol('Origen', width: 190, flex: 1),
              TCol('Destino', width: 190, flex: 1),
              TCol('Usuario', width: 96, flex: 0.3),
              TCol('Fecha', width: 124, flex: 0.3),
            ],
            emptyText: 'No hay movimientos de este tipo.',
            rows: [
              for (final m in rows)
                TRow([
                  AppBadge(kMovementTypes[m.type]?.label ?? m.type, tone: kMovementTypes[m.type]?.tone ?? Tone.neutral),
                  tMono(context, s.product(m.productId).code, weight: FontWeight.w600),
                  tMono(context, m.doc, muted: true),
                  tMono(context, '${m.qty}', weight: FontWeight.w600, color: m.qty < 0 ? c.crit : null),
                  tText(context, m.from, maxLines: 1),
                  m.note == null
                      ? tText(context, m.to, maxLines: 1)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            tText(context, m.to, maxLines: 1),
                            tText(context, m.note!, muted: true, maxLines: 2),
                          ],
                        ),
                  tText(context, m.user, maxLines: 1),
                  tText(context, fmtDateTime(m.dateTime), maxLines: 1),
                ]),
            ],
          ),
        ),
      ],
    );
  }
}
