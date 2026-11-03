import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/tone.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../util/format.dart';
import '../../widgets/badge.dart';
import '../../widgets/bin_tag.dart';
import '../../widgets/common.dart';
import '../../widgets/data_table_card.dart';
import '../../widgets/pick_step_row.dart';
import '../../widgets/toast.dart';

class TransfersScreen extends ConsumerStatefulWidget {
  const TransfersScreen({super.key});

  @override
  ConsumerState<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends ConsumerState<TransfersScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() {
      if (mounted) setState(() {});
    });

  // Entre bins
  String _binProduct = 'p1';
  String? _srcRowId;
  String? _destBinSel;
  final _binQty = TextEditingController(text: '10');
  final _obs = TextEditingController();

  // Entre tiendas
  String _stProduct = 'p1';
  String? _fromSel;
  String? _toSel;

  List<String> get _storeNames => ref.read(appProvider).activeStores.map((s) => s.name).toList();

  String get _destBin {
    final bins = ref.read(appProvider).centralBinCodes;
    if (_destBinSel != null && bins.contains(_destBinSel)) return _destBinSel!;
    return bins.contains('C-01-01') ? 'C-01-01' : bins.first;
  }

  String get _fromStore {
    final n = _storeNames;
    return _fromSel != null && n.contains(_fromSel) ? _fromSel! : n.first;
  }

  String get _toStore {
    final n = _storeNames;
    if (_toSel != null && n.contains(_toSel)) return _toSel!;
    return n.firstWhere((x) => x != _fromStore, orElse: () => n.first);
  }
  final _stQty = TextEditingController(text: '8');

  @override
  void initState() {
    super.initState();
    _srcRowId = _defaultSrc(_binProduct);
    final pre = ref.read(appProvider).transferPrefill;
    if (pre != null) _applyPrefill(pre);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _binQty.dispose();
    _obs.dispose();
    _stQty.dispose();
    super.dispose();
  }

  String? _defaultSrc(String pid) {
    final rows = ref.read(appProvider).centralFifoRowsOf(pid);
    return rows.isEmpty ? null : rows.first.id;
  }

  void _applyPrefill(StoreTransferPrefill p) {
    _stProduct = p.productId;
    _fromSel = p.fromStore;
    _toSel = p.toStore;
    _stQty.text = '${p.qty}';
    _tabs.index = 1;
    ref.read(appProvider.notifier).consumePrefill();
  }

  void _doBinTransfer() {
    final st = ref.read(appProvider);
    final src = st.inventory.where((r) => r.id == _srcRowId).firstOrNull;
    final qty = parseInt(_binQty.text);
    final err = ref.read(appProvider.notifier).binTransfer(
          productId: _binProduct,
          srcRowId: _srcRowId,
          destBin: _destBin,
          qty: qty,
          obs: _obs.text,
        );
    if (err != null) {
      showToast(ref, err);
      return;
    }
    showToast(ref, 'Transferidas $qty unidades de ${st.product(_binProduct).code}: ${src?.bin} → $_destBin');
    setState(() {
      _obs.clear();
      final still = ref.read(appProvider).inventory.any((r) => r.id == _srcRowId && r.qty > 0);
      if (!still) _srcRowId = _defaultSrc(_binProduct);
    });
  }

  void _doStoreSend() {
    final qty = parseInt(_stQty.text);
    final res = ref.read(appProvider.notifier).storeTransferSend(
          productId: _stProduct,
          fromStore: _fromStore,
          toStore: _toStore,
          qty: qty,
        );
    if (res.error != null) {
      showToast(ref, res.error!);
      return;
    }
    showToast(ref, 'Transferencia ${res.id} enviada — pendiente de confirmación en $_toStore');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppState>(appProvider, (prev, next) {
      final pre = next.transferPrefill;
      if (pre != null) setState(() => _applyPrefill(pre));
    });
    final st = ref.watch(appProvider);
    // Los productos llegan con los recibos de RM: si el elegido no existe, el primero.
    if (st.products.isNotEmpty) {
      if (st.products.every((p) => p.id != _binProduct)) {
        _binProduct = st.products.first.id;
        _srcRowId = _defaultSrc(_binProduct);
      }
      if (st.products.every((p) => p.id != _stProduct)) _stProduct = st.products.first.id;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScreenHeader(
          eyebrow: 'Movimientos',
          title: 'Transferencias',
          subtitle:
              'Mueve inventario entre localizaciones del almacén o entre sucursales. Cada movimiento queda registrado con usuario, fecha y hora.',
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [Tab(text: 'Entre bins'), Tab(text: 'Entre tiendas')],
        ),
        const SizedBox(height: 16),
        if (st.products.isEmpty)
          const NoteBox('Aún no hay productos. Llegan al importar recibos de RM en «Recibido sin ubicar».')
        else if (_tabs.index == 0)
          _binsTab(context)
        else
          _storesTab(context),
      ],
    );
  }

  Widget _binsTab(BuildContext context) {
    final s = ref.read(appProvider);
    final srcRows = s.centralFifoRowsOf(_binProduct);
    final srcValid = srcRows.any((r) => r.id == _srcRowId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Transferencia entre bins',
          subtitle: 'Desde el inventario general (RECIBO) o entre canastas de Almacén Central. Se permiten cantidades parciales.',
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              LabeledField(
                label: 'Producto',
                width: 340,
                child: AppDropdown<String>(
                  value: _binProduct,
                  items: [for (final p in s.products) ddItem(context, p.id, '${p.code} — ${p.desc}')],
                  onChanged: (v) => setState(() {
                    _binProduct = v ?? _binProduct;
                    _srcRowId = _defaultSrc(_binProduct);
                  }),
                ),
              ),
              LabeledField(
                label: 'Bin origen',
                width: 290,
                child: AppDropdown<String>(
                  value: srcValid ? _srcRowId : null,
                  mono: true,
                  items: [
                    for (final r in srcRows)
                      ddItem(context, r.id, '${r.bin} — disp. ${r.qty} (${fmtDate(r.entryDate)})', mono: true),
                  ],
                  onChanged: (v) => setState(() => _srcRowId = v),
                ),
              ),
              LabeledField(
                label: 'Bin destino',
                width: 150,
                child: AppDropdown<String>(
                  value: _destBin,
                  mono: true,
                  items: [for (final b in ref.watch(appProvider).centralBinCodes) ddItem(context, b, b, mono: true)],
                  onChanged: (v) => setState(() => _destBinSel = v ?? _destBin),
                ),
              ),
              LabeledField(label: 'Cantidad', width: 110, child: NumField(controller: _binQty)),
              LabeledField(
                label: 'Observaciones',
                width: 300,
                child: AppTextField(controller: _obs, hint: 'Opcional'),
              ),
              FilledButton(onPressed: _doBinTransfer, child: const Text('Transferir')),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          title: 'Transferencias recientes',
          trailing: Pill('${s.binTransfers.length}', mono: true),
          flushBody: true,
          child: AppTable(
            columns: const [
              TCol('Producto', width: 140, flex: 0.6),
              TCol('Origen', width: 100, flex: 0.3),
              TCol('Destino', width: 100, flex: 0.3),
              TCol('Cant.', width: 64, flex: 0.2, numeric: true),
              TCol('Usuario', width: 100, flex: 0.4),
              TCol('Fecha', width: 128, flex: 0.4),
              TCol('Obs.', width: 180, flex: 1.5),
            ],
            emptyText: 'Aún no hay transferencias entre bins.',
            rows: [
              for (final t in s.binTransfers)
                TRow([
                  tMono(context, s.product(t.productId).code, weight: FontWeight.w600),
                  BinTag(t.from),
                  BinTag(t.to),
                  tMono(context, '${t.qty}', weight: FontWeight.w600),
                  tText(context, t.user, maxLines: 1),
                  tText(context, fmtDateTime(t.dateTime), maxLines: 1),
                  tText(context, t.obs, muted: true),
                ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _storesTab(BuildContext context) {
    final s = ref.read(appProvider);
    final c = context.c;
    final avail = s.storeQty(_stProduct, _fromStore);
    final pending = s.storeTransfers.where((t) => t.status == 'pendiente').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Transferencia entre tiendas',
          subtitle: 'Envía inventario a otra sucursal. Se descuenta del origen en orden FIFO.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 14,
                runSpacing: 14,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  LabeledField(
                    label: 'Producto',
                    width: 340,
                    child: AppDropdown<String>(
                      value: _stProduct,
                      items: [for (final p in s.products) ddItem(context, p.id, '${p.code} — ${p.desc}')],
                      onChanged: (v) => setState(() => _stProduct = v ?? _stProduct),
                    ),
                  ),
                  LabeledField(
                    label: 'Tienda origen',
                    width: 210,
                    child: AppDropdown<String>(
                      value: _fromStore,
                      items: [for (final st in s.activeStores) ddItem(context, st.name, st.name)],
                      onChanged: (v) => setState(() => _fromSel = v ?? _fromStore),
                    ),
                  ),
                  LabeledField(
                    label: 'Tienda destino',
                    width: 210,
                    child: AppDropdown<String>(
                      value: _toStore,
                      items: [for (final st in s.activeStores) ddItem(context, st.name, st.name)],
                      onChanged: (v) => setState(() => _toSel = v ?? _toStore),
                    ),
                  ),
                  LabeledField(label: 'Cantidad', width: 110, child: NumField(controller: _stQty)),
                  FilledButton(onPressed: _doStoreSend, child: const Text('Enviar transferencia')),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Disponible en $_fromStore: $avail unidad(es)',
                style: T.muted(context, size: 12.5).copyWith(color: avail == 0 ? c.crit : null),
              ),
              const SizedBox(height: 12),
              const NoteBox('La tienda destino debe confirmar la recepción antes de que el inventario quede disponible allí.'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          title: 'Pendientes de confirmación',
          trailing: Pill('${pending.length}', tone: pending.isEmpty ? Tone.neutral : Tone.warn, mono: true),
          flushBody: true,
          child: AppTable(
            columns: const [
              TCol('Producto', width: 140, flex: 0.6),
              TCol('Origen', width: 170, flex: 1),
              TCol('Destino', width: 170, flex: 1),
              TCol('Cant.', width: 64, flex: 0.2, numeric: true),
              TCol('Enviado', width: 128, flex: 0.4),
              TCol('', width: 190, flex: 0.4),
            ],
            emptyText: 'No hay transferencias pendientes de confirmar.',
            rows: [
              for (final t in pending)
                TRow([
                  tMono(context, s.product(t.productId).code, weight: FontWeight.w600),
                  tText(context, t.fromStore, maxLines: 1),
                  tText(context, t.toStore, maxLines: 1),
                  tMono(context, '${t.qty}', weight: FontWeight.w600),
                  tText(context, fmtDateTime(t.sentAt), maxLines: 1),
                  FilledButton(
                    style: compactFilled(),
                    onPressed: () {
                      ref.read(appProvider.notifier).storeTransferConfirm(t.id);
                      showToast(ref, 'Recepción de ${t.id} confirmada en ${t.toStore} (bin ${ref.read(appProvider).receiveBinOf(t.toStore)})');
                    },
                    child: const Text('Confirmar recepción'),
                  ),
                ]),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          title: 'Historial de transferencias entre tiendas',
          flushBody: true,
          child: AppTable(
            columns: const [
              TCol('Documento', width: 96, flex: 0.3),
              TCol('Producto', width: 140, flex: 0.6),
              TCol('Origen', width: 170, flex: 1),
              TCol('Destino', width: 170, flex: 1),
              TCol('Cant.', width: 64, flex: 0.2, numeric: true),
              TCol('Estado', width: 110, flex: 0.3),
              TCol('Fecha', width: 128, flex: 0.4),
            ],
            rows: [
              for (final t in s.storeTransfers)
                TRow([
                  tMono(context, t.id, muted: true),
                  tMono(context, s.product(t.productId).code, weight: FontWeight.w600),
                  tText(context, t.fromStore, maxLines: 1),
                  tText(context, t.toStore, maxLines: 1),
                  tMono(context, '${t.qty}', weight: FontWeight.w600),
                  t.status == 'recibido'
                      ? const AppBadge('Recibido', tone: Tone.good)
                      : const AppBadge('Pendiente', tone: Tone.warn),
                  tText(context, fmtDateTime(t.receivedAt ?? t.sentAt), maxLines: 1),
                ]),
            ],
          ),
        ),
      ],
    );
  }
}
