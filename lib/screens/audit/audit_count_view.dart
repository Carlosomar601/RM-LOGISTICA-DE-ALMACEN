import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/audit.dart';
import '../../models/tone.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/badge.dart';
import '../../widgets/bin_tag.dart';
import '../../widgets/common.dart';
import '../../widgets/data_table_card.dart';
import '../../widgets/pick_step_row.dart';
import '../../widgets/toast.dart';

/// Conteo a ciegas: el auditor escanea la canasta y cada producto con la cantidad que encuentra.
/// Nunca se muestra la cantidad que el sistema espera.
class AuditCountView extends ConsumerStatefulWidget {
  const AuditCountView({super.key});

  @override
  ConsumerState<AuditCountView> createState() => _AuditCountViewState();
}

class _AuditCountViewState extends ConsumerState<AuditCountView> {
  String? _auditSel;
  final _binScan = TextEditingController();
  final _prodScan = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _binFocus = FocusNode();
  final _prodFocus = FocusNode();
  final Map<String, TextEditingController> _recount = {};

  @override
  void dispose() {
    _binScan.dispose();
    _prodScan.dispose();
    _qty.dispose();
    _binFocus.dispose();
    _prodFocus.dispose();
    for (final c in _recount.values) {
      c.dispose();
    }
    super.dispose();
  }

  AppNotifier get _n => ref.read(appProvider.notifier);

  void _scanBin(Audit a) {
    final code = _binScan.text.trim();
    if (code.isEmpty) return;
    final err = _n.startBinCount(a.id, code);
    if (err != null) {
      showToast(ref, err);
      _binScan.selection = TextSelection(baseOffset: 0, extentOffset: _binScan.text.length);
      _binFocus.requestFocus();
      return;
    }
    _binScan.clear();
    _prodFocus.requestFocus();
  }

  void _addProduct(Audit a, AuditBin b) {
    final code = _prodScan.text.trim();
    if (code.isEmpty) return;
    final qty = _qty.text.trim().isEmpty ? 1 : parseInt(_qty.text);
    final err = _n.addCount(a.id, b.bin, code, qty);
    if (err != null) {
      showToast(ref, err);
    } else {
      _prodScan.clear();
      _qty.text = '1';
    }
    _prodFocus.requestFocus();
  }

  void _finish(Audit a, AuditBin b) {
    final res = _n.finishBinCount(a.id, b.bin);
    if (res.error != null) {
      showToast(ref, res.error!);
      return;
    }
    if (res.recount.isEmpty) {
      showToast(ref, 'Canasta ${b.bin} contada. Escanea la siguiente.');
      _binFocus.requestFocus();
    }
  }

  void _submitRecount(Audit a, AuditBin b, {bool skip = false}) {
    final values = <String, int>{};
    for (final id in b.recountIds ?? const <String>[]) {
      final t = _recount[id]?.text.trim() ?? '';
      if (t.isNotEmpty) values[id] = parseInt(t);
    }
    final err = _n.submitRecount(a.id, b.bin, values, skip: skip);
    if (err != null) {
      showToast(ref, err);
      return;
    }
    for (final c in _recount.values) {
      c.dispose();
    }
    _recount.clear();
    showToast(ref, 'Canasta ${b.bin} contada. Escanea la siguiente.');
    _binFocus.requestFocus();
  }

  Future<void> _editQty(Audit a, AuditBin b, String productId, int current) async {
    final ctl = TextEditingController(text: '$current');
    final s = ref.read(appProvider);
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cantidad de ${s.product(productId).code}'),
        content: SizedBox(
          width: 280,
          child: LabeledField(label: 'Unidades contadas (0 = quitar)', child: NumField(controller: ctl)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, parseInt(ctl.text)), child: const Text('Guardar')),
        ],
      ),
    );
    ctl.dispose();
    if (value == null) return;
    final err = _n.setCount(a.id, b.bin, productId, value);
    if (err != null) showToast(ref, err);
  }

  Future<void> _editNote(Audit a, AuditBin b, String productId) async {
    final ctl = TextEditingController(text: b.notes[productId] ?? '');
    final s = ref.read(appProvider);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nota para ${s.product(productId).code}'),
        content: SizedBox(
          width: 360,
          child: LabeledField(
            label: 'Observación (p. ej. «2 dañadas»)',
            child: AppTextField(controller: ctl),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Guardar')),
        ],
      ),
    );
    ctl.dispose();
    if (value != null) _n.setCountNote(a.id, b.bin, productId, value);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final audits = s.auditsToCount;
    if (audits.isEmpty) {
      return const NoteBox('No hay auditorías abiertas para contar. El supervisor las crea en la pestaña Auditorías.');
    }
    final a = audits.firstWhereOrNull((x) => x.id == _auditSel) ?? audits.first;
    final mine = a.bins.firstWhereOrNull((b) => b.status == AuditBinStatus.contando && b.auditor == s.actor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Auditoría',
          subtitle: 'Elige la auditoría y escanea el código de la canasta que vas a contar.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabeledField(
                label: 'Auditoría',
                width: 360,
                child: AppDropdown<String>(
                  value: a.id,
                  items: [for (final x in audits) ddItem(context, x.id, '${x.id} · ${x.scopeLabel}')],
                  onChanged: mine != null ? null : (v) => setState(() => _auditSel = v),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final b in a.bins) _BinChip(b)],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (mine == null)
          SectionCard(
            title: 'Escanear canasta',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                LabeledField(
                  label: 'Código de la canasta',
                  width: 260,
                  child: TextField(
                    key: const Key('audit-bin-scan'),
                    controller: _binScan,
                    focusNode: _binFocus,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    style: T.mono(context, size: 14),
                    decoration: const InputDecoration(hintText: 'A-01-02'),
                    onSubmitted: (_) => _scanBin(a),
                  ),
                ),
                FilledButton(onPressed: () => _scanBin(a), child: const Text('Empezar conteo')),
              ],
            ),
          )
        else if (mine.recountIds != null)
          _recountCard(context, s, a, mine)
        else
          _countCard(context, s, a, mine),
      ],
    );
  }

  Widget _countCard(BuildContext context, AppState s, Audit a, AuditBin b) {
    final c = context.c;
    final lines = b.counts.entries.toList();
    final units = lines.fold(0, (x, e) => x + e.value);
    return SectionCard(
      title: 'Contando ${b.bin}',
      subtitle: 'Escanea cada producto. Cada lectura suma la cantidad indicada (1 por defecto). '
          'Si un producto no está, simplemente no lo escanees.',
      trailing: const AppBadge('Canasta bloqueada', tone: Tone.warn),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              LabeledField(
                label: 'Código del producto',
                width: 260,
                child: TextField(
                  key: const Key('audit-product-scan'),
                  controller: _prodScan,
                  focusNode: _prodFocus,
                  autofocus: true,
                  style: T.mono(context, size: 14),
                  decoration: const InputDecoration(hintText: 'Escanea o escribe'),
                  onSubmitted: (_) => _addProduct(a, b),
                ),
              ),
              LabeledField(label: 'Cantidad', width: 100, child: NumField(controller: _qty)),
              FilledButton(onPressed: () => _addProduct(a, b), child: const Text('+ Sumar')),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: AppTable(
              headerBackground: c.surfaceSunken,
              emptyText: 'Todavía no has escaneado productos en esta canasta.',
              columns: const [
                TCol('Producto', width: 120, flex: 0.3),
                TCol('Descripción', width: 180, flex: 1),
                TCol('Contado', width: 90, flex: 0, numeric: true),
                TCol('', width: 220, flex: 0),
              ],
              rows: [
                for (final e in lines)
                  TRow([
                    tMono(context, s.product(e.key).code, weight: FontWeight.w600),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        tText(context, s.product(e.key).desc, maxLines: 1),
                        if (b.notes[e.key] != null) tText(context, b.notes[e.key]!, muted: true, maxLines: 1),
                      ],
                    ),
                    tMono(context, '${e.value}', weight: FontWeight.w700, color: c.accent),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      OutlinedButton(
                        style: compactOutlined(),
                        onPressed: () => _editQty(a, b, e.key, e.value),
                        child: const Text('Cantidad'),
                      ),
                      OutlinedButton(
                        style: compactOutlined(),
                        onPressed: () => _editNote(a, b, e.key),
                        child: const Text('Nota'),
                      ),
                    ]),
                  ]),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Pill('${lines.length} productos · $units unidades', mono: true),
              FilledButton(onPressed: () => _finish(a, b), child: const Text('Terminar canasta')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recountCard(BuildContext context, AppState s, Audit a, AuditBin b) {
    final c = context.c;
    final ids = b.recountIds!;
    return SectionCard(
      title: 'Reconteo de ${b.bin}',
      subtitle: 'Estos productos no cuadran con el sistema. Vuélvelos a contar con cuidado y escribe lo que encuentras '
          '(0 si no está). El reconteo se hace una sola vez.',
      trailing: const AppBadge('Reconteo', tone: Tone.warn),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: AppTable(
              headerBackground: c.surfaceSunken,
              columns: const [
                TCol('Producto', width: 120, flex: 0.3),
                TCol('Descripción', width: 180, flex: 1),
                TCol('Reconteo', width: 120, flex: 0),
              ],
              rows: [
                for (final id in ids)
                  TRow([
                    tMono(context, s.product(id).code, weight: FontWeight.w600),
                    tText(context, s.product(id).desc, maxLines: 1),
                    NumField(controller: _recount.putIfAbsent(id, TextEditingController.new), hint: '0'),
                  ]),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => _submitRecount(a, b, skip: true),
                child: const Text('Confirmar sin recontar'),
              ),
              FilledButton(onPressed: () => _submitRecount(a, b), child: const Text('Guardar reconteo')),
            ],
          ),
        ],
      ),
    );
  }
}

class _BinChip extends StatelessWidget {
  const _BinChip(this.b);
  final AuditBin b;

  @override
  Widget build(BuildContext context) {
    final tone = switch (b.status) {
      AuditBinStatus.pendiente => Tone.neutral,
      AuditBinStatus.contando => Tone.warn,
      AuditBinStatus.contada || AuditBinStatus.cerrada => Tone.good,
      AuditBinStatus.cancelada => Tone.neutral,
    };
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [BinTag(b.bin), AppBadge(kAuditBinStatusLabels[b.status]!, tone: tone)],
    );
  }
}
