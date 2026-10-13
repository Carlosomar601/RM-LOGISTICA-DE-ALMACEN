import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/seed.dart';
import '../../models/receipt.dart';
import '../../models/tone.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../util/format.dart';
import '../../widgets/badge.dart';
import '../../widgets/common.dart';
import '../../widgets/expandable_card.dart';
import '../../widgets/pick_step_row.dart';
import '../../widgets/toast.dart';

class ReceivingScreen extends ConsumerStatefulWidget {
  const ReceivingScreen({super.key});

  @override
  ConsumerState<ReceivingScreen> createState() => _ReceivingScreenState();
}

class _ReceivingScreenState extends ConsumerState<ReceivingScreen> {
  final _expanded = <String>{'REC-3430'};
  final _panels = <String>{};

  void _simulate() {
    final id = ref.read(appProvider.notifier).simulateReceipt();
    final r = ref.read(appProvider).receipts.firstWhere((x) => x.id == id);
    setState(() => _expanded.add(id));
    showToast(ref, 'Recibo $id de ${r.supplier} listo para ubicar');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final pending = s.pendingReceipts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenHeader(
          eyebrow: 'Recepción',
          title: 'Recibido sin ubicar',
          subtitle:
              'Mercancía recibida que todavía no tiene localización. Asígnala a una o varias canastas (bins) para que quede disponible para el piqueo FIFO.',
          actions: [FilledButton(onPressed: _simulate, child: const Text('+ Simular recibo entrante'))],
        ),
        const FlowSteps(steps: [
          ('Recibe la mercancía', 'El recibo entra con la cantidad recibida y queda pendiente de ubicar.'),
          ('Asigna canastas', 'Reparte las unidades entre uno o varios bins de Almacén Central.'),
          ('Confirma la ubicación', 'El inventario queda disponible por bin, con su fecha de entrada y lote para FIFO.'),
        ]),
        const SizedBox(height: 20),
        if (pending.isEmpty)
          SectionCard(
            child: Text(
              'No hay recibos pendientes de ubicar. Todo el inventario recibido ya está en canasta.',
              style: T.muted(context, size: 13.5),
            ),
          ),
        for (final r in pending)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ExpandableCard(
              title: '${r.id} — ${r.supplier}',
              monoTitle: false,
              subtitle: '${r.items.length} artículo(s) · recibido ${fmtDate(r.date)}',
              trailing: const AppBadge('Pendiente de ubicar', tone: Tone.warn),
              expanded: _expanded.contains(r.id),
              onToggle: () => setState(() => _expanded.contains(r.id) ? _expanded.remove(r.id) : _expanded.add(r.id)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final it in r.items) _itemBlock(context, r, it),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _itemBlock(BuildContext context, Receipt r, ReceiptItem it) {
    final s = ref.read(appProvider);
    final p = s.product(it.productId);
    final key = '${r.id}|${it.productId}';
    final open = _panels.contains(key) && it.pending > 0;
    final c = context.c;

    Widget metric(String label, int v, {Color? color}) => Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(), style: T.th(context)),
            const SizedBox(height: 2),
            Text('$v', style: T.mono(context, size: 16, weight: FontWeight.w600, color: color)),
          ],
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: open ? c.borderStrong : c.border),
        borderRadius: BorderRadius.circular(R.tile),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 10,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.code, style: T.mono(context, size: 13.5, weight: FontWeight.w600)),
                    Text(p.desc, style: T.muted(context, size: 12.5)),
                  ],
                ),
              ),
              Wrap(
                spacing: 22,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  metric('Recibido', it.qtyReceived),
                  metric('Ubicado', it.qtyAllocated, color: c.good),
                  metric('Pendiente', it.pending, color: it.pending > 0 ? c.warn : c.inkMuted),
                  if (it.pending == 0)
                    const AppBadge('Completo', tone: Tone.good)
                  else
                    (open
                        ? OutlinedButton(
                            style: compactOutlined(),
                            onPressed: () => setState(() => _panels.remove(key)),
                            child: const Text('Cerrar'),
                          )
                        : FilledButton(
                            style: compactFilled(),
                            onPressed: () => setState(() => _panels.add(key)),
                            child: const Text('Ubicar'),
                          )),
                ],
              ),
            ],
          ),
          if (open) ...[
            const SizedBox(height: 12),
            _AllocationPanel(
              key: ValueKey('alloc-$key'),
              receiptId: r.id,
              productId: it.productId,
              pending: it.pending,
              onDone: () => setState(() => _panels.remove(key)),
            ),
          ],
        ],
      ),
    );
  }
}

class _AllocRow {
  _AllocRow(this.bin, int qty) : ctl = TextEditingController(text: qty > 0 ? '$qty' : '');
  String bin;
  final TextEditingController ctl;
}

class _AllocationPanel extends ConsumerStatefulWidget {
  const _AllocationPanel({
    super.key,
    required this.receiptId,
    required this.productId,
    required this.pending,
    required this.onDone,
  });

  final String receiptId;
  final String productId;
  final int pending;
  final VoidCallback onDone;

  @override
  ConsumerState<_AllocationPanel> createState() => _AllocationPanelState();
}

class _AllocationPanelState extends ConsumerState<_AllocationPanel> {
  late final List<_AllocRow> _rows = [_AllocRow(kAllBins.first, widget.pending)];

  @override
  void dispose() {
    for (final r in _rows) {
      r.ctl.dispose();
    }
    super.dispose();
  }

  int get _sum => _rows.fold(0, (a, r) => a + parseInt(r.ctl.text));

  void _add() {
    final used = _rows.map((r) => r.bin).toSet();
    final next = kAllBins.firstWhere((b) => !used.contains(b), orElse: () => kAllBins.first);
    final remaining = widget.pending - _sum;
    setState(() => _rows.add(_AllocRow(next, remaining > 0 ? remaining : 0)));
  }

  void _remove(int i) {
    final r = _rows.removeAt(i);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => r.ctl.dispose());
  }

  void _confirm() {
    final st = ref.read(appProvider);
    final code = st.product(widget.productId).code;
    final rows = [for (final r in _rows) (r.bin, parseInt(r.ctl.text))];
    final valid = rows.where((r) => r.$2 > 0).toList();
    final err = ref.read(appProvider.notifier).allocateReceiptItem(widget.receiptId, widget.productId, rows);
    if (err != null) {
      showToast(ref, err);
      return;
    }
    final sum = valid.fold(0, (a, r) => a + r.$2);
    showToast(ref, 'Ubicadas $sum unidades de $code en ${valid.length} canasta(s) · ${widget.receiptId}');
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(R.input + 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ASIGNAR A CANASTAS', style: T.th(context)),
          const SizedBox(height: 10),
          for (var i = 0; i < _rows.length; i++)
            Padding(
              key: ObjectKey(_rows[i]),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: AppDropdown<String>(
                      value: _rows[i].bin,
                      mono: true,
                      items: [for (final b in kAllBins) ddItem(context, b, b, mono: true)],
                      onChanged: (v) => setState(() => _rows[i].bin = v ?? _rows[i].bin),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: NumField(controller: _rows[i].ctl, hint: 'Cant.')),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Quitar canasta',
                    onPressed: _rows.length > 1 ? () => _remove(i) : null,
                    icon: const Text('✕'),
                    color: c.inkMuted,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          ListenableBuilder(
            listenable: Listenable.merge([for (final r in _rows) r.ctl]),
            builder: (context, _) {
              final sum = _sum;
              final over = sum > widget.pending;
              final valid = _rows.any((r) => parseInt(r.ctl.text) > 0);
              return Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: [
                  Text(
                    'Asignado $sum de ${widget.pending} pendientes${over ? ' — excede lo pendiente' : ''}',
                    style: T.body(context,
                        size: 13, weight: FontWeight.w600, color: over ? c.crit : (sum == widget.pending ? c.good : c.inkMuted)),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(style: compactOutlined(), onPressed: _add, child: const Text('+ Agregar canasta')),
                      FilledButton(
                        style: compactFilled(),
                        onPressed: !over && valid ? _confirm : null,
                        child: const Text('Confirmar ubicación'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
