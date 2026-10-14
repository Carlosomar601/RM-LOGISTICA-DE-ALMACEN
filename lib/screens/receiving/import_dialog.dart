import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/rm_api.dart';
import '../../models/tone.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/badge.dart';
import '../../widgets/common.dart';
import '../../widgets/toast.dart';

/// Importa recibos desde la API de una tienda (RecReceiptsByDate).
Future<void> showImportReceiptsDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _ImportDialog());

class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog();

  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  late final TextEditingController _from;
  late final TextEditingController _to;
  String? _storeId;
  bool _loading = false;
  String? _error;
  List<RmReceiptLine>? _lines;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = TextEditingController(text: fmtApiDate(now.subtract(const Duration(days: 1))));
    _to = TextEditingController(text: fmtApiDate(now));
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  DateTime? _parse(String v) {
    final t = v.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t)) return null;
    return DateTime.tryParse(t);
  }

  Future<void> _search(String storeId) async {
    final from = _parse(_from.text), to = _parse(_to.text);
    String? err;
    if (from == null || to == null) {
      err = 'Usa fechas con formato aaaa-mm-dd.';
    } else if (from.isAfter(to)) {
      err = 'La fecha inicial no puede ser posterior a la final.';
    } else if (to.difference(from).inDays >= 366) {
      err = 'El rango máximo es de 366 días.';
    }
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _lines = null;
    });
    try {
      final lines = await ref.read(appProvider.notifier).fetchReceiptLines(storeId, from!, to!);
      if (!mounted) return;
      setState(() {
        _lines = lines;
        _loading = false;
      });
    } on RmApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _import(String storeId) {
    final res = ref.read(appProvider.notifier).importReceiptLines(storeId, _lines!);
    final parts = <String>[
      '${res.lines} línea(s) importada(s) en ${res.receiptsCreated + res.receiptsUpdated} recibo(s)',
      if (res.productsCreated > 0) '${res.productsCreated} producto(s) nuevo(s)',
      if (res.duplicates > 0) '${res.duplicates} ya importada(s)',
      if (res.skipped > 0) '${res.skipped} omitida(s)',
      if (res.fractional > 0) '${res.fractional} con cantidad decimal redondeada',
    ];
    Navigator.pop(context);
    showToast(ref, parts.join(' · '));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final n = ref.read(appProvider.notifier);
    final c = context.c;
    final stores = s.activeStores.where((x) => x.apiUrl.trim().isNotEmpty).toList();
    final store = stores.firstWhereOrNull((x) => x.id == _storeId) ?? stores.firstOrNull;
    final lines = _lines;
    final fresh = store == null || lines == null ? <RmReceiptLine>[] : lines.where((l) => !n.isLineImported(store.id, l) && AppNotifier.skipReason(l) == null).toList();
    final byReceipt = groupBy(lines ?? <RmReceiptLine>[], (RmReceiptLine l) => l.receiptNumber);

    return AlertDialog(
      title: const Text('Importar recibos desde RM'),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: store == null
              ? Text(
                  'Ninguna tienda tiene dirección API. Configúrala en Administración → Tiendas.',
                  style: T.muted(context, size: 13.5),
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          LabeledField(
                            label: 'Tienda (API)',
                            width: 240,
                            child: AppDropdown<String>(
                              value: store.id,
                              items: [for (final x in stores) ddItem(context, x.id, x.name)],
                              onChanged: (v) => setState(() {
                                _storeId = v;
                                _lines = null;
                              }),
                            ),
                          ),
                          LabeledField(label: 'Desde', width: 130, child: AppTextField(controller: _from, mono: true)),
                          LabeledField(label: 'Hasta', width: 130, child: AppTextField(controller: _to, mono: true)),
                          FilledButton(
                            onPressed: _loading ? null : () => _search(store.id),
                            child: Text(_loading ? 'Buscando…' : 'Buscar'),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: T.body(context, size: 12.5, color: c.crit)),
                      ],
                      if (lines != null) ...[
                        const SizedBox(height: 16),
                        if (lines.isEmpty)
                          Text('No hay recibos en ese rango.', style: T.muted(context, size: 13.5))
                        else ...[
                          Text(
                            '${lines.length} línea(s) en ${byReceipt.length} recibo(s) · ${fresh.length} nueva(s)',
                            style: T.th(context),
                          ),
                          const SizedBox(height: 8),
                          for (final e in byReceipt.entries) _receiptBlock(context, n, store.id, e.value),
                        ],
                      ],
                    ],
                  ),
                ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        if (store != null)
          FilledButton(
            onPressed: fresh.isEmpty ? null : () => _import(store.id),
            child: Text(fresh.isEmpty ? 'Importar' : 'Importar ${fresh.length} línea(s)'),
          ),
      ],
    );
  }

  Widget _receiptBlock(BuildContext context, AppNotifier n, String storeId, List<RmReceiptLine> ls) {
    final c = context.c;
    final first = ls.first;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(R.tile),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${first.receiptNumber} — ${first.supplierName}',
            style: T.body(context, size: 13.5, weight: FontWeight.w600),
          ),
          Text(
            '${fmtApiDate(first.receiptDate)}${first.orderNumber.isEmpty ? '' : ' · OC ${first.orderNumber}'}'
            '${first.invoiceNumber.isEmpty ? '' : ' · Fact. ${first.invoiceNumber}'}',
            style: T.muted(context, size: 12),
          ),
          const SizedBox(height: 6),
          for (final l in ls)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${l.itemCode} · ${l.description}',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: T.body(context, size: 12.5)),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${_qty(l.quantityReceived)}${l.unit.isEmpty ? '' : ' ${l.unit}'}',
                          style: T.mono(context, size: 12.5, weight: FontWeight.w600)),
                      if (n.isLineImported(storeId, l))
                        const AppBadge('Ya importada', tone: Tone.neutral)
                      else if (AppNotifier.skipReason(l) != null)
                        AppBadge('Se omitirá: ${AppNotifier.skipReason(l)}', tone: Tone.warn),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _qty(double q) => q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toString();
}
