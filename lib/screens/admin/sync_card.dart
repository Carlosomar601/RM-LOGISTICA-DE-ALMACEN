import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rm_core/models/tone.dart';
import 'package:rm_core/sync/sync_service.dart';
import 'package:rm_core/sync/sync_settings.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'package:rm_core/util/format.dart';
import '../../widgets/badge.dart';
import '../../widgets/common.dart';
import '../../widgets/toast.dart';

/// Administración → Parámetros → Sincronización con RM.
class SyncCard extends ConsumerStatefulWidget {
  const SyncCard({super.key});

  @override
  ConsumerState<SyncCard> createState() => _SyncCardState();
}

class _SyncCardState extends ConsumerState<SyncCard> {
  late final _lookback = TextEditingController(text: '${ref.read(syncProvider).settings.lookbackDays}');
  late final _skipTx =
      TextEditingController(text: (ref.read(syncProvider).settings.skipTransactions.toList()..sort()).join(', '));
  late final _returnsDays = TextEditingController(text: '${ref.read(syncProvider).settings.returnsFirstRunDays}');
  String? _skipError;

  @override
  void dispose() {
    _lookback.dispose();
    _skipTx.dispose();
    _returnsDays.dispose();
    super.dispose();
  }

  Future<void> _syncNow() async {
    final parts = await ref.read(syncProvider.notifier).syncNow();
    if (!mounted) return;
    final failed = parts.where((p) => !p.ok && !p.notAvailable).length;
    showToast(ref, failed == 0 ? 'Sincronización terminada' : 'Sincronización con $failed error(es); revisa el detalle');
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncProvider);
    final n = ref.read(syncProvider.notifier);
    final c = context.c;
    final last = sync.settings.lastSync;
    return SectionCard(
      title: 'Sincronización con RM',
      subtitle: 'Trae recibos, facturas y órdenes desde RMApiV2. Corre mientras la app está abierta; '
          'al abrirla recupera los últimos días indicados.',
      trailing: sync.running ? const AppBadge('Sincronizando…', tone: Tone.accent) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 14,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              LabeledField(
                label: 'Frecuencia',
                width: 220,
                child: AppDropdown<SyncInterval>(
                  value: sync.settings.interval,
                  items: [for (final v in SyncInterval.values) ddItem(context, v, v.label)],
                  onChanged: (v) {
                    if (v == null) return;
                    n.setInterval(v);
                    showToast(ref, 'Sincronización: ${v.label}');
                  },
                ),
              ),
              LabeledField(
                label: 'Días a recuperar al abrir',
                width: 190,
                child: NumField(
                  controller: _lookback,
                  onChanged: (v) {
                    final d = parseInt(v);
                    if (d > 0) n.setLookbackDays(d);
                  },
                ),
              ),
              LabeledField(
                label: 'Facturas que no se despachan (transacción)',
                width: 290,
                child: AppTextField(
                  controller: _skipTx,
                  mono: true,
                  hint: '10, 11, 12, 19',
                  onChanged: (v) {
                    final tx = SyncSettings.parseTransactions(v);
                    setState(() => _skipError = tx == null ? 'Solo números separados por coma' : null);
                    if (tx != null) n.setSkipTransactions(tx);
                  },
                ),
              ),
              FilledButton(
                onPressed: sync.running ? null : _syncNow,
                child: Text(sync.running ? 'Sincronizando…' : 'Sincronizar ahora'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _skipError ??
                'Por defecto 10, 11, 12 y 19: ventas en caja, el cliente se lleva la mercancía. '
                    'Las facturas de una orden ya importada no se despachan dos veces.',
            style: T.body(context, size: 12, color: _skipError != null ? c.crit : c.inkMuted),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Switch(
                  value: sync.settings.returnsEnabled,
                  onChanged: (v) {
                    n.setReturnsEnabled(v);
                    showToast(ref, v ? 'Detección de devoluciones activada' : 'Detección de devoluciones apagada');
                  },
                ),
                const SizedBox(width: 8),
                Flexible(child: Text('Detectar devoluciones (almacén central)', style: T.body(context, size: 13.5))),
              ]),
              LabeledField(
                label: 'Días en la primera detección (máx. $kMaxReturnsFirstRunDays)',
                width: 250,
                child: NumField(
                  controller: _returnsDays,
                  onChanged: (v) {
                    final d = parseInt(v);
                    if (d > 0) n.setReturnsFirstRunDays(d);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            sync.settings.returnsLastSync == null
                ? 'Las devoluciones y anulaciones de RM quedan por revisar en Auditoría ▸ Devoluciones; nada entra '
                    'al inventario hasta aceptarlas. Actívalo cuando se haya verificado el formato en la base de RM.'
                : 'Última detección de devoluciones: ${fmtDateTime(sync.settings.returnsLastSync!)}',
            style: T.body(context, size: 12, color: c.inkMuted),
          ),
          const SizedBox(height: 14),
          Text(
            last == null ? 'Aún no se ha sincronizado.' : 'Última sincronización: ${fmtDateTime(last)}',
            style: T.muted(context, size: 12.5),
          ),
          for (final p in sync.parts)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      p.ok ? '✓' : (p.notAvailable ? '…' : '✕'),
                      style: T.mono(context,
                          size: 12.5, weight: FontWeight.w700, color: p.ok ? c.good : (p.notAvailable ? c.inkMuted : c.crit)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${p.label}: ${p.message}',
                        style: T.body(context, size: 12.5, color: p.ok || p.notAvailable ? c.inkMuted : c.crit)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
