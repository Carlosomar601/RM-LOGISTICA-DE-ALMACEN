import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/seed.dart';
import '../models/pick_session.dart';
import '../models/tone.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../util/clock.dart';
import '../util/format.dart';
import 'badge.dart';
import 'bin_tag.dart';
import 'data_table_card.dart';
import 'rank_circle.dart';
import 'toast.dart';

/// Toast estándar para secciones bloqueadas por permisos.
void showLockedToast(WidgetRef ref) {
  final u = ref.read(appProvider).simulatedUser;
  if (u == null) return;
  showToast(ref, '🔒 ${u.name} (${u.role}) no tiene acceso a esta sección.');
}

ButtonStyle compactFilled() => FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      minimumSize: const Size(0, 32),
      textStyle: const TextStyle(fontFamily: kBodyFont, fontSize: 12.5, fontWeight: FontWeight.w600),
    );

ButtonStyle compactOutlined({Color? fg}) => OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      minimumSize: const Size(0, 32),
      foregroundColor: fg,
      textStyle: const TextStyle(fontFamily: kBodyFont, fontSize: 12.5, fontWeight: FontWeight.w600),
    );

const kPickColumns = [
  TCol('FIFO', width: 58, flex: 0),
  TCol('Localización', width: 118, flex: 1),
  TCol('Recibo', width: 100, flex: 1),
  TCol('Fecha de entrada', width: 128, flex: 1),
  TCol('Antigüedad', width: 100, flex: 0.5),
  TCol('Disp.', width: 68, flex: 0, numeric: true),
  TCol('Tomar', width: 72, flex: 0, numeric: true),
  TCol('Estado', width: 132, flex: 0.5),
  TCol('Verificación', width: 236, flex: 1),
];

/// Pasos de una sesión de piqueo + fila de faltante + sugerencia de otra tienda.
class PickStepsView extends ConsumerWidget {
  const PickStepsView({super.key, required this.sessionKey});
  final String sessionKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final s = state.pickSessions[sessionKey];
    if (s == null) return const SizedBox.shrink();
    final n = ref.read(appProvider.notifier);
    final c = context.c;

    final rows = <TRow>[];
    for (var i = 0; i < s.steps.length; i++) {
      final st = s.steps[i];
      final missing = st.status == StepStatus.missingHere;
      rows.add(TRow(
        [
          RankCircle(i + 1),
          BinTag(st.bin, struck: missing),
          tMono(context, st.receipt, muted: true),
          tText(context, fmtDate(st.entryDate), maxLines: 1),
          AgeBadge(ageDays(st.entryDate)),
          tMono(context, '${st.available}'),
          tMono(context, '${st.take}', weight: FontWeight.w700, color: missing ? c.inkMuted : c.accent),
          switch (st.status) {
            StepStatus.pending => const AppBadge('Por verificar', tone: Tone.warn),
            StepStatus.picked => const AppBadge('Recogido', tone: Tone.good),
            StepStatus.missingHere => const AppBadge('No estaba aquí', tone: Tone.crit),
          },
          if (st.status == StepStatus.pending)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton(
                  style: compactFilled(),
                  onPressed: () => n.stepPicked(sessionKey, st.id),
                  child: const Text('✔ Recogido'),
                ),
                OutlinedButton(
                  style: compactOutlined(fg: c.crit),
                  onPressed: () => n.stepMissingHere(sessionKey, st.id),
                  child: const Text('No está aquí'),
                ),
              ],
            )
          else
            tText(context, st.status == StepStatus.picked ? 'Verificado' : 'Se ajustará por conteo', muted: true),
        ],
        opacity: missing ? 0.5 : 1,
      ));
    }

    final sf = s.shortfall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(R.input + 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: AppTable(
            columns: kPickColumns,
            rows: rows,
            headerBackground: c.surfaceSunken,
            cellPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            emptyText: 'No hay canastas de Almacén Central con este producto.',
          ),
        ),
        if (sf != null) ...[
          const SizedBox(height: 10),
          _ShortfallRow(sessionKey: sessionKey, shortfall: sf),
        ],
        if (sf != null && sf.status == ShortfallStatus.unresolved) _OtherStoreBox(sessionKey: sessionKey),
      ],
    );
  }
}

class _ShortfallRow extends ConsumerWidget {
  const _ShortfallRow({required this.sessionKey, required this.shortfall});
  final String sessionKey;
  final Shortfall shortfall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final accepted = shortfall.status == ShortfallStatus.missing;
    final n = shortfall.take;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.critSoft,
        borderRadius: BorderRadius.circular(R.input + 2),
        border: Border.all(color: c.crit.withValues(alpha: 0.35)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(accepted ? Icons.report_off_outlined : Icons.warning_amber_rounded, size: 18, color: c.crit),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  accepted
                      ? '$n unidad(es) declaradas como no encontradas en el almacén.'
                      : 'No quedan más ubicaciones en Almacén Central para cubrir $n unidad(es).',
                  style: T.body(context, size: 13, weight: FontWeight.w600, color: c.crit),
                ),
              ),
            ],
          ),
          if (accepted)
            const AppBadge('No encontrado — aceptado', tone: Tone.crit, strong: true)
          else
            OutlinedButton(
              style: compactOutlined(fg: c.crit),
              onPressed: () => ref.read(appProvider.notifier).declareShortfall(sessionKey),
              child: const Text('Marcar como no encontrado en almacén'),
            ),
        ],
      ),
    );
  }
}

class _OtherStoreBox extends ConsumerWidget {
  const _OtherStoreBox({required this.sessionKey});
  final String sessionKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final s = state.pickSessions[sessionKey];
    final sf = s?.shortfall;
    if (s == null || sf == null) return const SizedBox.shrink();
    final others = state.fifoRowsOf(s.productId).where((r) => r.store != kCentral).toList();
    if (others.isEmpty) return const SizedBox.shrink();
    final c = context.c;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.warnSoft,
        borderRadius: BorderRadius.circular(R.input + 2),
        border: Border.all(color: c.warn.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Antes de declarar el faltante — hay existencia en otra ubicación:',
              style: T.body(context, size: 13, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final r in others)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 6,
                children: [
                  Text('${r.store} · ${r.bin} · ${r.qty} disponibles', style: T.mono(context, size: 12.5)),
                  OutlinedButton(
                    style: compactOutlined(),
                    onPressed: () {
                      final qty = min(r.qty, sf.take);
                      final ok = ref.read(appProvider.notifier).prefillStoreTransfer(
                            productId: s.productId,
                            fromStore: r.store,
                            qty: qty,
                          );
                      if (ok) {
                        showToast(ref,
                            'Envía las $qty unidades desde ${r.store} y confirma la recepción — luego recalcula la ruta de piqueo para usarlas.');
                      } else {
                        showLockedToast(ref);
                      }
                    },
                    child: Text('Transferir ${min(r.qty, sf.take)} a Almacén Central'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
