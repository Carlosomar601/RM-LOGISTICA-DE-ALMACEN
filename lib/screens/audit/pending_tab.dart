import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/audit.dart';
import '../../models/pending_item.dart';
import '../../models/tone.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../../util/format.dart';
import '../../widgets/badge.dart';
import '../../widgets/bin_tag.dart';
import '../../widgets/common.dart';
import '../../widgets/data_table_card.dart';
import '../../widgets/pick_step_row.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/toast.dart';

/// Área PENDIENTES: lo que no apareció (auditoría o piqueo), con su lote y fecha originales.
/// Administración lo marca como encontrado (vuelve a una canasta) o lo da de baja con motivo.
class PendingTab extends ConsumerStatefulWidget {
  const PendingTab({super.key});

  @override
  ConsumerState<PendingTab> createState() => _PendingTabState();
}

class _PendingTabState extends ConsumerState<PendingTab> {
  bool _showResolved = false;

  AppNotifier get _n => ref.read(appProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final open = s.openPending;
    final resolved = s.pendingItems.where((p) => !p.isOpen).toList();
    final rows = _showResolved ? resolved : open;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatRow(maxColumns: 4, tiles: [
          StatTile(label: 'Pendientes abiertos', value: '${open.length}', tone: open.isEmpty ? null : Tone.warn),
          StatTile(label: 'Unidades en PENDIENTES', value: fmtInt(s.pendingUnits)),
          StatTile(
              label: 'Encontrados',
              value: '${resolved.where((p) => p.status == PendingStatus.encontrado).length}',
              tone: Tone.good),
          StatTile(
              label: 'Dados de baja', value: '${resolved.where((p) => p.status == PendingStatus.baja).length}'),
        ]),
        const SizedBox(height: 20),
        SectionCard(
          title: _showResolved ? 'Pendientes resueltos' : 'Pendientes abiertos',
          subtitle: 'Lo que falta no cuenta como existencia ni se piquea hasta que se encuentra.',
          trailing: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Abiertos')),
              ButtonSegment(value: true, label: Text('Resueltos')),
            ],
            selected: {_showResolved},
            onSelectionChanged: (v) => setState(() => _showResolved = v.first),
          ),
          flushBody: true,
          child: AppTable(
            emptyText: _showResolved ? 'Todavía no se ha resuelto ningún pendiente.' : 'No hay pendientes abiertos.',
            columns: [
              const TCol('Pendiente', width: 90, flex: 0.2),
              const TCol('Producto', width: 150, flex: 0.6),
              const TCol('Cant.', width: 60, flex: 0, numeric: true),
              const TCol('Lote / fecha', width: 140, flex: 0.3),
              const TCol('Origen', width: 120, flex: 0.3),
              const TCol('Motivo', width: 170, flex: 0.6),
              if (_showResolved) const TCol('Resolución', width: 200, flex: 0.6) else const TCol('', width: 220, flex: 0),
            ],
            rows: [
              for (final p in rows)
                TRow([
                  tMono(context, p.id, weight: FontWeight.w600),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      tMono(context, s.product(p.productId).code, weight: FontWeight.w600),
                      tText(context, s.product(p.productId).desc, muted: true, maxLines: 1),
                    ],
                  ),
                  tMono(context, '${p.qty}', weight: FontWeight.w700),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      tMono(context, p.lot),
                      tText(context, fmtDate(p.entryDate), muted: true, maxLines: 1),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BinTag(p.originBin),
                      tMono(context, p.sourceDoc, muted: true),
                    ],
                  ),
                  tText(context, [p.reason, if (p.note != null) p.note!].join(' · '), maxLines: 2),
                  if (_showResolved)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppBadge(kPendingStatusLabels[p.status]!,
                            tone: p.status == PendingStatus.encontrado ? Tone.good : Tone.crit),
                        tText(
                            context,
                            [
                              if (p.foundBin != null) 'En ${p.foundBin}',
                              if (p.resolutionReason != null) p.resolutionReason!,
                              if (p.resolutionNote != null) p.resolutionNote!,
                              '${p.resolvedBy ?? '—'} · ${p.resolvedAt == null ? '' : fmtDate(p.resolvedAt!)}',
                            ].join(' · '),
                            muted: true,
                            maxLines: 2),
                      ],
                    )
                  else
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      FilledButton(
                        style: compactFilled(),
                        onPressed: () => _found(context, p),
                        child: const Text('Encontrado'),
                      ),
                      OutlinedButton(
                        style: compactOutlined(fg: context.c.crit),
                        onPressed: () => _writeOff(context, p),
                        child: const Text('Dar de baja'),
                      ),
                    ]),
                ]),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _found(BuildContext context, PendingItem p) async {
    final s = ref.read(appProvider);
    final codes = s.centralBinCodes.where((b) => !s.lockedBins.contains(b)).toList()..sort();
    var bin = codes.contains(p.originBin) ? p.originBin : (codes.isEmpty ? null : codes.first);
    final qty = TextEditingController(text: '${p.qty}');
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Encontrado · ${p.id}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tText(ctx, 'Vuelve al inventario con el lote ${p.lot} y la fecha ${fmtDate(p.entryDate)} originales.',
                    muted: true, maxLines: 3),
                const SizedBox(height: 12),
                LabeledField(
                  label: 'Canasta donde apareció',
                  child: AppDropdown<String>(
                    value: bin,
                    mono: true,
                    items: [for (final c in codes) ddItem(ctx, c, c == p.originBin ? '$c (la misma)' : c, mono: true)],
                    onChanged: (v) => setD(() => bin = v),
                  ),
                ),
                const SizedBox(height: 12),
                LabeledField(label: 'Cantidad (de ${p.qty})', child: NumField(controller: qty)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (bin == null) return;
                final err = _n.resolvePendingFound(p.id, bin!, parseInt(qty.text));
                if (err != null) {
                  showToast(ref, err);
                  return;
                }
                Navigator.pop(ctx);
                showToast(ref, '${p.id}: vuelve a $bin');
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
    qty.dispose();
  }

  Future<void> _writeOff(BuildContext context, PendingItem p) async {
    var reason = kWriteOffReasons.first;
    final qty = TextEditingController(text: '${p.qty}');
    final note = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Dar de baja · ${p.id}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledField(
                  label: 'Motivo',
                  child: AppDropdown<String>(
                    value: reason,
                    items: [for (final r in kWriteOffReasons) ddItem(ctx, r, r)],
                    onChanged: (v) => setD(() => reason = v ?? reason),
                  ),
                ),
                const SizedBox(height: 12),
                LabeledField(label: 'Cantidad (de ${p.qty})', child: NumField(controller: qty)),
                const SizedBox(height: 12),
                LabeledField(
                  label: reason == kReasonOther ? 'Nota (obligatoria)' : 'Nota',
                  child: AppTextField(controller: note),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final err = _n.writeOffPending(p.id, parseInt(qty.text), reason, note: note.text);
                if (err != null) {
                  showToast(ref, err);
                  return;
                }
                Navigator.pop(ctx);
                showToast(ref, '${p.id} dado de baja');
              },
              child: const Text('Dar de baja'),
            ),
          ],
        ),
      ),
    );
    qty.dispose();
    note.dispose();
  }
}
