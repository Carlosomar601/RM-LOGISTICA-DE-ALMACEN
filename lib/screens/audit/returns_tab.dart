import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rm_core/models/audit.dart';
import 'package:rm_core/models/pending_item.dart';
import 'package:rm_core/models/return_entry.dart';
import 'package:rm_core/models/tone.dart';
import 'package:rm_core/state/app_state.dart';
import 'package:rm_core/state/pick_engine.dart';
import 'package:rm_core/util/clock.dart';
import 'package:rm_core/util/format.dart';
import '../../theme/tokens.dart';
import '../../widgets/badge.dart';
import '../../widgets/bin_tag.dart';
import '../../widgets/common.dart';
import '../../widgets/data_table_card.dart';
import '../../widgets/pick_step_row.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/toast.dart';
import 'pending_tab.dart';

enum _Kind { all, returns, missing }

/// Una fila de la bandeja: devolución de RM o «no estaba aquí» del piqueo.
class _Item {
  _Item.ret(ReturnEntry this.ret) : pen = null, date = ret.docDate;
  _Item.pen(PendingItem this.pen) : ret = null, date = pen.createdAt;
  final ReturnEntry? ret;
  final PendingItem? pen;
  final DateTime date;
}

/// Auditoría ▸ Devoluciones: lo que RM registró como devuelto o anulado (almacén central) pasa
/// por aquí antes de volver al inventario. También salen los faltantes del piqueo.
class ReturnsTab extends ConsumerStatefulWidget {
  const ReturnsTab({super.key});

  @override
  ConsumerState<ReturnsTab> createState() => _ReturnsTabState();
}

class _ReturnsTabState extends ConsumerState<ReturnsTab> {
  bool _showReviewed = false;
  _Kind _kind = _Kind.all;
  int? _days;
  String _query = '';
  final _selected = <String>{};
  final _search = TextEditingController();

  AppNotifier get _n => ref.read(appProvider.notifier);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(AppState s, _Item it) {
    if (_days != null && ageDays(it.date) > _days!) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final p = s.product(it.ret?.productId ?? it.pen!.productId);
    final hay = [
      p.code,
      p.desc,
      if (it.ret != null) ...[it.ret!.id, it.ret!.docNumber, it.ret!.originalInvoice, it.ret!.customerName],
      if (it.pen != null) ...[it.pen!.id, it.pen!.sourceDoc],
    ].join(' ').toLowerCase();
    return hay.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final openRet = s.openReturns;
    final openPen = s.pickMissingOpen;
    final reviewedRet = s.returns.where((r) => !r.isOpen).toList();
    final reviewedPen = s.pendingItems.where((p) => !p.isOpen && p.reason == kPickMissingReason).toList();

    final items = <_Item>[
      if (_kind != _Kind.missing)
        for (final r in _showReviewed ? reviewedRet : openRet) _Item.ret(r),
      if (_kind != _Kind.returns)
        for (final p in _showReviewed ? reviewedPen : openPen) _Item.pen(p),
    ].where((it) => _matches(s, it)).toList()..sort((a, b) => b.date.compareTo(a.date));

    final selectable = {
      for (final it in items)
        if (it.ret != null && it.ret!.isOpen) it.ret!.id,
    };
    _selected.removeWhere((id) => !selectable.contains(id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatRow(
          maxColumns: 4,
          tiles: [
            StatTile(
              label: 'Devoluciones por revisar',
              value: '${openRet.length}',
              tone: openRet.isEmpty ? null : Tone.warn,
            ),
            StatTile(
              label: 'No encontrados (piqueo)',
              value: '${openPen.length}',
              tone: openPen.isEmpty ? null : Tone.warn,
            ),
            StatTile(
              label: 'Aceptadas',
              value: '${reviewedRet.where((r) => r.status == ReturnStatus.aceptada).length}',
              tone: Tone.good,
            ),
            StatTile(
              label: 'Bajas y descartadas',
              value: '${reviewedRet.where((r) => r.status != ReturnStatus.aceptada).length}',
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionCard(
          title: _showReviewed ? 'Revisados' : 'Por revisar',
          subtitle:
              'Nada entra al inventario hasta que se acepta. Al aceptar, la devolución pasa a '
              '«Recibido sin ubicar» con la fecha de entrada elegida.',
          trailing: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Por revisar')),
              ButtonSegment(value: true, label: Text('Revisados')),
            ],
            selected: {_showReviewed},
            onSelectionChanged: (v) => setState(() {
              _showReviewed = v.first;
              _selected.clear();
            }),
          ),
          flushBody: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    SegmentedButton<_Kind>(
                      segments: const [
                        ButtonSegment(value: _Kind.all, label: Text('Todos')),
                        ButtonSegment(value: _Kind.returns, label: Text('Devoluciones')),
                        ButtonSegment(value: _Kind.missing, label: Text('No encontrados')),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (v) => setState(() => _kind = v.first),
                    ),
                    SizedBox(
                      width: 170,
                      child: AppDropdown<int?>(
                        value: _days,
                        items: [
                          ddItem<int?>(context, null, 'Cualquier fecha'),
                          ddItem<int?>(context, 7, 'Últimos 7 días'),
                          ddItem<int?>(context, 30, 'Últimos 30 días'),
                          ddItem<int?>(context, 90, 'Últimos 90 días'),
                        ],
                        onChanged: (v) => setState(() => _days = v),
                      ),
                    ),
                    SizedBox(
                      width: 240,
                      child: AppTextField(
                        controller: _search,
                        hint: 'Producto, documento o cliente',
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    if (!_showReviewed && selectable.isNotEmpty)
                      FilledButton(
                        onPressed: _selected.isEmpty ? null : () => _acceptSelected(context),
                        child: Text(
                          _selected.isEmpty ? 'Aceptar seleccionadas' : 'Aceptar seleccionadas (${_selected.length})',
                        ),
                      ),
                  ],
                ),
              ),
              AppTable(
                emptyText: _showReviewed ? 'Todavía no se ha revisado nada.' : 'No hay nada por revisar.',
                columns: [
                  if (!_showReviewed) const TCol('', width: 44, flex: 0),
                  const TCol('Tipo', width: 120, flex: 0.2),
                  const TCol('Documento', width: 140, flex: 0.3),
                  const TCol('Producto', width: 160, flex: 0.6),
                  const TCol('Cant.', width: 56, flex: 0, numeric: true),
                  const TCol('Fecha de entrada', width: 130, flex: 0.2),
                  const TCol('Despacho / origen', width: 170, flex: 0.5),
                  if (_showReviewed)
                    const TCol('Resolución', width: 210, flex: 0.6)
                  else
                    const TCol('', width: 250, flex: 0),
                ],
                rows: [for (final it in items) _row(context, s, it)],
              ),
            ],
          ),
        ),
      ],
    );
  }

  TRow _row(BuildContext context, AppState s, _Item it) {
    final r = it.ret;
    final p = it.pen;
    final product = s.product(r?.productId ?? p!.productId);
    return TRow([
      if (!_showReviewed)
        r == null
            ? const SizedBox.shrink()
            : Checkbox(
                value: _selected.contains(r.id),
                onChanged: (v) => setState(() => v == true ? _selected.add(r.id) : _selected.remove(r.id)),
              ),
      r != null ? AppBadge(r.docTypeLabel, tone: Tone.accent) : const AppBadge('No encontrado', tone: Tone.warn),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: r != null
            ? [
                tMono(context, r.docNumber, weight: FontWeight.w600),
                tText(
                  context,
                  r.originalInvoice.isEmpty ? r.id : '${r.id} · fact. ${r.originalInvoice}',
                  muted: true,
                  maxLines: 1,
                ),
              ]
            : [tMono(context, p!.sourceDoc, weight: FontWeight.w600), tText(context, p.id, muted: true, maxLines: 1)],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          tMono(context, product.code, weight: FontWeight.w600),
          tText(
            context,
            r != null && r.customerName.isNotEmpty ? '${product.desc} · ${r.customerName}' : product.desc,
            muted: true,
            maxLines: 1,
          ),
        ],
      ),
      tMono(context, '${r?.qty ?? p!.qty}', weight: FontWeight.w700),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: r != null
            ? [
                tText(context, fmtDate(r.entryDate), maxLines: 1),
                tText(
                  context,
                  r.originalDate != null ? 'venta original' : 'fecha de la devolución',
                  muted: true,
                  maxLines: 1,
                ),
              ]
            : [tText(context, fmtDate(p!.entryDate), maxLines: 1), tMono(context, p.lot, muted: true)],
      ),
      r != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [_shipBadge(r), if (r.shipNote != null) tText(context, r.shipNote!, muted: true, maxLines: 2)],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [BinTag(p!.originBin), tText(context, p.reason, muted: true, maxLines: 1)],
            ),
      if (_showReviewed)
        r != null ? _retResolution(context, r) : _penResolution(context, p!)
      else if (r != null)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (r.notShipped) ...[
              FilledButton(
                style: compactFilled(),
                onPressed: () => _discard(context, r),
                child: const Text('Descartar'),
              ),
              OutlinedButton(
                style: compactOutlined(),
                onPressed: () => _accept(context, r),
                child: const Text('Aceptar'),
              ),
            ] else ...[
              FilledButton(style: compactFilled(), onPressed: () => _accept(context, r), child: const Text('Aceptar')),
              OutlinedButton(
                style: compactOutlined(),
                onPressed: () => _discard(context, r),
                child: const Text('Descartar'),
              ),
            ],
            OutlinedButton(
              style: compactOutlined(fg: context.c.crit),
              onPressed: () => _writeOff(context, r),
              child: const Text('Dar de baja'),
            ),
          ],
        )
      else
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FilledButton(
              style: compactFilled(),
              onPressed: () => showPendingFoundDialog(context, ref, p!, pickMissing: true),
              child: const Text('Encontrado'),
            ),
            OutlinedButton(
              style: compactOutlined(fg: context.c.crit),
              onPressed: () => showPendingWriteOffDialog(context, ref, p!, pickMissing: true),
              child: const Text('Dar de baja'),
            ),
          ],
        ),
    ]);
  }

  Widget _shipBadge(ReturnEntry r) {
    final sh = r.shipped;
    if (sh == null) return const AppBadge('Origen desconocido');
    if (sh <= 0) return const AppBadge('No salió del almacén', tone: Tone.crit);
    if (sh < r.qty) return AppBadge('Despachadas $sh de ${r.qty}', tone: Tone.warn);
    return const AppBadge('Despachada por almacén', tone: Tone.good);
  }

  Widget _retResolution(BuildContext context, ReturnEntry r) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      AppBadge(
        kReturnStatusLabels[r.status]!,
        tone: switch (r.status) {
          ReturnStatus.aceptada => Tone.good,
          ReturnStatus.baja => Tone.crit,
          _ => Tone.neutral,
        },
      ),
      tText(
        context,
        [
          if (r.receiptId != null) 'Recibo ${r.receiptId}',
          if (r.reason != null) r.reason!,
          if (r.note != null) r.note!,
          '${r.reviewedBy ?? '—'} · ${r.reviewedAt == null ? '' : fmtDate(r.reviewedAt!)}',
        ].join(' · '),
        muted: true,
        maxLines: 2,
      ),
    ],
  );

  Widget _penResolution(BuildContext context, PendingItem p) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      AppBadge(kPendingStatusLabels[p.status]!, tone: p.status == PendingStatus.encontrado ? Tone.good : Tone.crit),
      tText(
        context,
        [
          if (p.foundBin != null) 'En ${p.foundBin}',
          if (p.resolutionReason != null) p.resolutionReason!,
          if (p.resolutionNote != null) p.resolutionNote!,
          '${p.resolvedBy ?? '—'} · ${p.resolvedAt == null ? '' : fmtDate(p.resolvedAt!)}',
        ].join(' · '),
        muted: true,
        maxLines: 2,
      ),
    ],
  );

  void _acceptSelected(BuildContext context) {
    final res = _n.acceptReturns(_selected.toList());
    setState(_selected.clear);
    showToast(
      ref,
      [
        '${res.accepted} devolución(es) aceptada(s): ya están en «Recibido sin ubicar»',
        if (res.skipped > 0) '${res.skipped} omitida(s) (no salieron del almacén: revísalas una por una)',
      ].join(' · '),
    );
  }

  Future<void> _accept(BuildContext context, ReturnEntry r) async {
    final qty = TextEditingController(text: '${r.qty}');
    final note = TextEditingController();
    var date = r.entryDate;
    var condition = kReturnConditions.first;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Aceptar devolución · ${r.id}'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tText(
                    ctx,
                    '${ref.read(appProvider).product(r.productId).code} · ${r.docNumber}'
                    '${r.originalInvoice.isEmpty ? '' : ' (factura ${r.originalInvoice})'}',
                    maxLines: 2,
                  ),
                  if (r.shipNote != null) ...[
                    const SizedBox(height: 10),
                    NoteBox(
                      r.shipNote!,
                      tone: r.notShipped ? Tone.crit : (r.shipped == null ? Tone.warn : Tone.neutral),
                    ),
                  ],
                  const SizedBox(height: 12),
                  LabeledField(
                    label: 'Cantidad que llegó (de ${r.qty}; el resto queda descartado como «no llegó»)',
                    child: NumField(controller: qty),
                  ),
                  const SizedBox(height: 12),
                  LabeledField(
                    label: 'Fecha de entrada (FIFO)',
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event, size: 18),
                      label: Text(
                        '${fmtDate(date)} · ${r.originalDate != null && date == r.originalDate ? 'venta original' : 'elegida'}',
                      ),
                      onPressed: () async {
                        final today = kToday;
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: date.isAfter(today) ? today : date,
                          firstDate: DateTime(today.year - 5),
                          lastDate: today,
                        );
                        if (picked != null) setD(() => date = picked);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  LabeledField(
                    label: 'Condición',
                    child: AppDropdown<String>(
                      value: condition,
                      items: [for (final c in kReturnConditions) ddItem(ctx, c, c)],
                      onChanged: (v) => setD(() => condition = v ?? condition),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LabeledField(
                    label: 'Nota',
                    child: AppTextField(controller: note),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final err = _n.acceptReturn(r.id, parseInt(qty.text), date, condition: condition, note: note.text);
                if (err != null) {
                  showToast(ref, err);
                  return;
                }
                Navigator.pop(ctx);
                showToast(ref, '${r.id} aceptada: ya está en «Recibido sin ubicar»');
              },
              child: const Text('Aceptar'),
            ),
          ],
        ),
      ),
    );
    qty.dispose();
    note.dispose();
  }

  Future<void> _discard(BuildContext context, ReturnEntry r) => _reasonDialog(
    context,
    r,
    title: 'Descartar · ${r.id}',
    help: 'No entra al inventario: la mercancía no llegó al almacén.',
    reasons: kReturnDiscardReasons,
    initial: r.notShipped ? kReturnDiscardReasons[1] : kReturnDiscardReasons.first,
    action: 'Descartar',
    run: (qty, reason, note) => _n.discardReturn(r.id, qty, reason, note: note),
    done: '${r.id} descartada',
  );

  Future<void> _writeOff(BuildContext context, ReturnEntry r) => _reasonDialog(
    context,
    r,
    title: 'Dar de baja · ${r.id}',
    help: 'Llegó, pero no se puede vender: no entra al inventario y queda una baja en el Historial.',
    reasons: kReturnWriteOffReasons,
    initial: kReturnWriteOffReasons.first,
    action: 'Dar de baja',
    run: (qty, reason, note) => _n.writeOffReturn(r.id, qty, reason, note: note),
    done: '${r.id} dada de baja',
  );

  Future<void> _reasonDialog(
    BuildContext context,
    ReturnEntry r, {
    required String title,
    required String help,
    required List<String> reasons,
    required String initial,
    required String action,
    required String? Function(int qty, String reason, String note) run,
    required String done,
  }) async {
    var reason = initial;
    final qty = TextEditingController(text: '${r.qty}');
    final note = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tText(ctx, help, muted: true, maxLines: 3),
                  const SizedBox(height: 12),
                  LabeledField(
                    label: 'Motivo',
                    child: AppDropdown<String>(
                      value: reason,
                      items: [for (final x in reasons) ddItem(ctx, x, x)],
                      onChanged: (v) => setD(() => reason = v ?? reason),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LabeledField(
                    label: 'Cantidad (de ${r.qty}; el resto sigue por revisar)',
                    child: NumField(controller: qty),
                  ),
                  const SizedBox(height: 12),
                  LabeledField(
                    label: reason == kReasonOther ? 'Nota (obligatoria)' : 'Nota',
                    child: AppTextField(controller: note),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final err = run(parseInt(qty.text), reason, note.text);
                if (err != null) {
                  showToast(ref, err);
                  return;
                }
                Navigator.pop(ctx);
                showToast(ref, done);
              },
              child: Text(action),
            ),
          ],
        ),
      ),
    );
    qty.dispose();
    note.dispose();
  }
}
