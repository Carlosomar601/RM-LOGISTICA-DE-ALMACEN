import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../models/audit.dart';
import '../../models/tone.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../util/format.dart';
import '../../widgets/badge.dart';
import '../../widgets/bin_tag.dart';
import '../../widgets/common.dart';
import '../../widgets/data_table_card.dart';
import '../../widgets/expandable_card.dart';
import '../../widgets/pick_step_row.dart';
import '../../widgets/toast.dart';

Tone auditResultTone(AuditResult r) => switch (r) {
      AuditResult.ok => Tone.good,
      AuditResult.faltante || AuditResult.noEsta => Tone.crit,
      AuditResult.sobrante || AuditResult.noRegistrado => Tone.warn,
    };

Tone auditStatusTone(AuditStatus s) => switch (s) {
      AuditStatus.abierta => Tone.neutral,
      AuditStatus.enCurso => Tone.warn,
      AuditStatus.cerrada => Tone.good,
      AuditStatus.cancelada => Tone.neutral,
    };

/// Supervisor/Administrador: crea auditorías, revisa lo contado, asigna motivos y cierra.
class AuditListTab extends ConsumerStatefulWidget {
  const AuditListTab({super.key});

  @override
  ConsumerState<AuditListTab> createState() => _AuditListTabState();
}

class _AuditListTabState extends ConsumerState<AuditListTab> {
  /// Auditorías cuyo estado expandido difiere del predeterminado (abiertas expandidas).
  final Set<String> _toggled = {};
  bool _showClosed = false;

  AppNotifier get _n => ref.read(appProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final open = s.openAudits;
    final closed = s.audits.where((a) => !a.isOpen).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Pill('${open.length} abiertas · ${s.lockedBins.length} canastas bloqueadas', mono: true),
            FilledButton(
              onPressed: () => showDialog<void>(context: context, builder: (_) => const CreateAuditDialog()),
              child: const Text('+ Nueva auditoría'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (open.isEmpty) const NoteBox('No hay auditorías abiertas.'),
        for (final a in open) ...[
          _auditCard(context, s, a),
          const SizedBox(height: 12),
        ],
        if (closed.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showClosed = !_showClosed),
              child: Text(_showClosed ? 'Ocultar cerradas' : 'Ver cerradas y canceladas (${closed.length})'),
            ),
          ),
          if (_showClosed)
            for (final a in closed) ...[
              _auditCard(context, s, a),
              const SizedBox(height: 12),
            ],
        ],
      ],
    );
  }

  Widget _auditCard(BuildContext context, AppState s, Audit a) {
    final assigned = a.assignedTo == null
        ? 'Cualquier auditor'
        : (s.users.where((u) => u.id == a.assignedTo).firstOrNull?.name ?? '—');
    final counted = a.bins.where((b) => b.status != AuditBinStatus.pendiente).length;
    final expanded = a.isOpen != _toggled.contains(a.id);
    return ExpandableCard(
      title: a.id,
      subtitle: '${a.scopeLabel} · creada por ${a.createdBy} el ${fmtDateTime(a.createdAt)} · $assigned',
      trailing: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Pill('$counted/${a.bins.length} canastas', mono: true),
        AppBadge(kAuditStatusLabels[a.status]!, tone: auditStatusTone(a.status)),
      ]),
      expanded: expanded,
      onToggle: () => setState(() => _toggled.contains(a.id) ? _toggled.remove(a.id) : _toggled.add(a.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final b in a.bins) ...[
            _binSection(context, s, a, b),
            const SizedBox(height: 12),
          ],
          if (a.isOpen)
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    final ok = await _confirm(context, 'Cancelar ${a.id}',
                        'Se desbloquean sus canastas y no se cambia el inventario.');
                    if (!ok) return;
                    final err = _n.cancelAudit(a.id);
                    showToast(ref, err ?? '${a.id} cancelada');
                  },
                  child: const Text('Cancelar auditoría'),
                ),
                FilledButton(
                  onPressed: () async {
                    final ok = await _confirm(
                        context,
                        'Cerrar ${a.id}',
                        'Se aplican las diferencias de las canastas contadas (los faltantes pasan a PENDIENTES) '
                            'y las que no se contaron quedan canceladas.');
                    if (!ok) return;
                    final err = _n.closeAudit(a.id);
                    showToast(ref, err ?? '${a.id} cerrada');
                  },
                  child: const Text('Cerrar auditoría'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _binSection(BuildContext context, AppState s, Audit a, AuditBin b) {
    final c = context.c;
    final header = Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        BinTag(b.bin),
        if (b.zone.isNotEmpty) tText(context, b.zone, muted: true),
        AppBadge(kAuditBinStatusLabels[b.status]!,
            tone: b.status == AuditBinStatus.contando ? Tone.warn : (b.locked ? Tone.accent : Tone.neutral)),
        if (b.auditor != null) tText(context, 'Auditor: ${b.auditor}', muted: true),
      ],
    );
    final showLines = b.status == AuditBinStatus.contada || b.status == AuditBinStatus.cerrada;
    if (!showLines) return header;
    final editable = b.status == AuditBinStatus.contada;
    final diffs = b.lines.where((l) => !l.isOk).length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 10),
          AppTable(
            headerBackground: c.surfaceSunken,
            cellPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            emptyText: 'La canasta estaba vacía y no se contó nada.',
            columns: const [
              TCol('Producto', width: 150, flex: 0.6),
              TCol('Esperado', width: 80, flex: 0, numeric: true),
              TCol('Contado', width: 110, flex: 0, numeric: true),
              TCol('Resultado', width: 130, flex: 0),
              TCol('Motivo', width: 240, flex: 1),
            ],
            rows: [for (final l in b.lines) _lineRow(context, s, a, b, l, editable)],
          ),
          if (editable) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                tText(context, diffs == 0 ? 'Todo cuadra.' : '$diffs diferencia(s): toda diferencia necesita un motivo.',
                    muted: true),
                FilledButton(
                  style: compactFilled(),
                  onPressed: () {
                    final err = _n.closeAuditBin(a.id, b.bin);
                    showToast(ref, err ?? 'Canasta ${b.bin} cerrada y desbloqueada');
                  },
                  child: const Text('Cerrar canasta'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  TRow _lineRow(BuildContext context, AppState s, Audit a, AuditBin b, AuditLine l, bool editable) {
    final p = s.product(l.productId);
    final first = b.counts[l.productId] ?? 0;
    final recounted = b.recounts?.containsKey(l.productId) ?? false;
    final note = b.notes[l.productId];
    final surplus = l.result == AuditResult.sobrante || l.result == AuditResult.noRegistrado;
    final candidates = surplus
        ? s.openPending.where((x) => x.productId == l.productId).toList()
        : const [];
    Widget reasonCell;
    if (l.isOk) {
      reasonCell = tText(context, '—', muted: true);
    } else if (!editable) {
      reasonCell = tText(
          context,
          [l.reason ?? '—', if (l.reasonNote != null) l.reasonNote!, if (l.matchedPendingId != null) '= ${l.matchedPendingId}']
              .join(' · '),
          maxLines: 2);
    } else {
      reasonCell = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppDropdown<String?>(
            value: l.reason,
            items: [
              ddItem<String?>(context, null, 'Elegir motivo…'),
              for (final r in kAuditReasons) ddItem<String?>(context, r, r),
            ],
            onChanged: (v) async {
              String? n = l.reasonNote;
              if (v == kReasonOther) n = await _askNote(context, l.reasonNote);
              _n.setLineReason(a.id, b.bin, l.productId, v, note: n);
            },
          ),
          if (l.reasonNote != null || l.reason != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  final n = await _askNote(context, l.reasonNote);
                  if (n != null) _n.setLineReason(a.id, b.bin, l.productId, l.reason, note: n);
                },
                child: Text(l.reasonNote == null ? '+ Nota' : 'Nota: ${l.reasonNote}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          if (candidates.isNotEmpty) ...[
            const SizedBox(height: 4),
            AppDropdown<String?>(
              value: l.matchedPendingId,
              items: [
                ddItem<String?>(context, null, 'No es un pendiente'),
                for (final x in candidates)
                  ddItem<String?>(context, x.id, 'Es ${x.id} (${x.qty} u., ${x.originBin}, lote ${x.lot})'),
              ],
              onChanged: (v) {
                final err = _n.matchSurplusToPending(a.id, b.bin, l.productId, v);
                if (err != null) showToast(ref, err);
              },
            ),
          ],
        ],
      );
    }
    return TRow([
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          tMono(context, p.code, weight: FontWeight.w600),
          tText(context, p.desc, muted: true, maxLines: 1),
          if (note != null) tText(context, 'Auditor: $note', muted: true, maxLines: 2),
        ],
      ),
      tMono(context, '${l.expected}'),
      tMono(context, recounted ? '$first → ${l.counted}' : '${l.counted}', weight: FontWeight.w700),
      Align(
        alignment: Alignment.centerLeft,
        child: AppBadge(
          '${kAuditResultLabels[l.result]}${l.isOk ? '' : ' ${l.diff > 0 ? '+' : ''}${l.diff}'}',
          tone: auditResultTone(l.result),
        ),
      ),
      reasonCell,
    ]);
  }

  Future<String?> _askNote(BuildContext context, String? current) async {
    final ctl = TextEditingController(text: current ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nota del motivo'),
        content: SizedBox(width: 360, child: AppTextField(controller: ctl, hint: 'Explica la diferencia')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Guardar')),
        ],
      ),
    );
    ctl.dispose();
    return v;
  }

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 380, child: Text(body)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    return ok ?? false;
  }
}

/// Nueva auditoría: una canasta, varias o una zona completa; auditor opcional.
class CreateAuditDialog extends ConsumerStatefulWidget {
  const CreateAuditDialog({super.key});

  @override
  ConsumerState<CreateAuditDialog> createState() => _CreateAuditDialogState();
}

class _CreateAuditDialogState extends ConsumerState<CreateAuditDialog> {
  bool _byZone = false;
  String? _zone;
  final Set<String> _bins = {};
  String? _auditor;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final zones = s.centralZones;
    final bins = s.auditableBins.toList()..sort((a, b) => a.code.compareTo(b.code));
    final auditors = s.users.where((u) => u.active && u.can(Area.audit)).toList();
    final zone = _zone != null && zones.contains(_zone) ? _zone : (zones.isEmpty ? null : zones.first);
    final zoneCount = zone == null ? 0 : bins.where((b) => b.zone.trim() == zone).length;

    return AlertDialog(
      title: const Text('Nueva auditoría'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Canastas')),
                  ButtonSegment(value: true, label: Text('Zona completa')),
                ],
                selected: {_byZone},
                onSelectionChanged: (v) => setState(() => _byZone = v.first),
              ),
              const SizedBox(height: 16),
              if (_byZone)
                zones.isEmpty
                    ? const NoteBox('Ninguna canasta tiene zona. Asígnalas en Administración → Canastas.')
                    : LabeledField(
                        label: 'Zona ($zoneCount canastas)',
                        child: AppDropdown<String>(
                          value: zone,
                          items: [for (final z in zones) ddItem(context, z, z)],
                          onChanged: (v) => setState(() => _zone = v),
                        ),
                      )
              else
                LabeledField(
                  label: 'Canastas (${_bins.length} elegidas)',
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final b in bins)
                        FilterChip(
                          label: Text(b.code, style: T.mono(context, size: 12.5)),
                          tooltip: s.auditHolding(b.code) == null ? b.zone : 'En ${s.auditHolding(b.code)}',
                          selected: _bins.contains(b.code),
                          onSelected: s.auditHolding(b.code) != null
                              ? null
                              : (v) => setState(() => v ? _bins.add(b.code) : _bins.remove(b.code)),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              LabeledField(
                label: 'Auditor',
                child: AppDropdown<String?>(
                  value: _auditor,
                  items: [
                    ddItem<String?>(context, null, 'Cualquier auditor'),
                    for (final u in auditors) ddItem<String?>(context, u.id, '${u.name} · ${u.role}'),
                  ],
                  onChanged: (v) => setState(() => _auditor = v),
                ),
              ),
              const SizedBox(height: 12),
              tText(context,
                  'El conteo es a ciegas: el auditor no ve la cantidad esperada. Cada canasta se bloquea al escanearla.',
                  muted: true, maxLines: 3),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final res = ref.read(appProvider.notifier).createAudit(
                  bins: _byZone ? const [] : _bins.toList(),
                  zone: _byZone ? zone : null,
                  assignedTo: _auditor,
                );
            if (res.error != null) {
              showToast(ref, res.error!);
              return;
            }
            Navigator.pop(context);
            showToast(ref, 'Auditoría ${res.id} creada');
          },
          child: const Text('Crear auditoría'),
        ),
      ],
    );
  }
}

/// Texto corto de exactitud: 0.953 → "95.3 %".
String fmtPct(double v) => '${(v * 100).toStringAsFixed(1)} %';
