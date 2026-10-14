import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/admin_config.dart';
import '../../models/tone.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/badge.dart';
import '../../widgets/common.dart';
import '../../widgets/data_table_card.dart';
import '../../widgets/pick_step_row.dart';
import '../../widgets/toast.dart';

class BinsTab extends ConsumerStatefulWidget {
  const BinsTab({super.key});

  @override
  ConsumerState<BinsTab> createState() => _BinsTabState();
}

class _BinsTabState extends ConsumerState<BinsTab> {
  String? _storeId;
  final _code = TextEditingController();
  final _zone = TextEditingController();
  final _cap = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    _zone.dispose();
    _cap.dispose();
    super.dispose();
  }

  void _add(String storeId) {
    final cap = parseInt(_cap.text);
    final err = ref.read(appProvider.notifier).addBin(
          storeId,
          _code.text,
          zone: _zone.text,
          capacity: cap > 0 ? cap : null,
        );
    if (err != null) {
      showToast(ref, err);
      return;
    }
    showToast(ref, 'Canasta ${_code.text.trim().toUpperCase()} agregada');
    setState(() {
      _code.clear();
      _zone.clear();
      _cap.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final n = ref.read(appProvider.notifier);
    final store = s.stores.where((x) => x.id == _storeId).firstOrNull ?? s.centralStore;
    final bins = s.bins.where((b) => b.storeId == store.id).toList()
      ..sort((a, b) => a.code.compareTo(b.code));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Canastas por almacén',
          subtitle: 'Las canastas activas del almacén central aparecen al ubicar recibos y al transferir entre bins. '
              'Las de recepción (RECIBO, ${store.receiveBin}) son fijas.',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              LabeledField(
                label: 'Almacén / tienda',
                width: 280,
                child: AppDropdown<String>(
                  value: store.id,
                  items: [for (final st in s.stores) ddItem(context, st.id, st.name)],
                  onChanged: (v) => setState(() => _storeId = v),
                ),
              ),
              LabeledField(
                label: 'Código',
                width: 130,
                child: AppTextField(controller: _code, mono: true, hint: 'A-04-01'),
              ),
              LabeledField(
                label: 'Zona',
                width: 150,
                child: AppTextField(controller: _zone, hint: 'Zona A'),
              ),
              LabeledField(
                label: 'Capacidad',
                width: 110,
                child: NumField(controller: _cap, hint: 'Opcional'),
              ),
              FilledButton(onPressed: () => _add(store.id), child: const Text('+ Agregar canasta')),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          title: 'Canastas de ${store.name}',
          trailing: AppBadge('${bins.length}'),
          flushBody: true,
          child: AppTable(
            emptyText: 'Este almacén aún no tiene canastas.',
            columns: const [
              TCol('Código', width: 110),
              TCol('Zona', width: 130),
              TCol('Capacidad', width: 100, numeric: true),
              TCol('Inventario', width: 100, numeric: true),
              TCol('Estado', width: 110),
              TCol('', width: 230, flex: 0),
            ],
            rows: [
              for (final b in bins)
                TRow(
                  [
                    tMono(context, b.code),
                    tText(context, b.zone.isEmpty ? '—' : b.zone, muted: b.zone.isEmpty),
                    tMono(context, b.capacity?.toString() ?? '—'),
                    tMono(context, '${_stock(s, store, b)}'),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: b.special
                          ? const AppBadge('Recepción', tone: Tone.neutral)
                          : AppBadge(b.active ? 'Activa' : 'Inactiva', tone: b.active ? Tone.good : Tone.neutral),
                    ),
                    Wrap(spacing: 6, children: [
                      OutlinedButton(
                        style: compactOutlined(),
                        onPressed: () => _edit(context, b),
                        child: const Text('Editar'),
                      ),
                      if (!b.special)
                        OutlinedButton(
                          style: compactOutlined(),
                          onPressed: () {
                            final err = n.updateBin(b.id, active: !b.active);
                            if (err != null) showToast(ref, err);
                          },
                          child: Text(b.active ? 'Desactivar' : 'Activar'),
                        ),
                      if (!b.special)
                        OutlinedButton(
                          style: compactOutlined(),
                          onPressed: () {
                            final err = n.deleteBin(b.id);
                            showToast(ref, err ?? 'Canasta ${b.code} eliminada');
                          },
                          child: const Text('Eliminar'),
                        ),
                    ]),
                  ],
                  opacity: b.active ? 1 : 0.55,
                ),
            ],
          ),
        ),
      ],
    );
  }

  int _stock(AppState s, Store store, Bin b) => s.inventory
      .where((r) => r.store == store.name && r.bin == b.code && r.qty > 0)
      .fold(0, (a, r) => a + r.qty);

  Future<void> _edit(BuildContext context, Bin b) async {
    final zone = TextEditingController(text: b.zone);
    final code = TextEditingController(text: b.code);
    final cap = TextEditingController(text: b.capacity?.toString() ?? '');
    final n = ref.read(appProvider.notifier);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar canasta ${b.code}'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabeledField(
                label: 'Código',
                child: b.special
                    ? Text(b.code, style: T.mono(ctx, size: 13.5))
                    : AppTextField(controller: code, mono: true),
              ),
              const SizedBox(height: 12),
              LabeledField(label: 'Zona', child: AppTextField(controller: zone)),
              const SizedBox(height: 12),
              LabeledField(label: 'Capacidad', child: NumField(controller: cap, hint: 'Opcional')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final c = parseInt(cap.text);
              final err = n.updateBin(
                b.id,
                code: b.special ? null : code.text,
                zone: zone.text.trim(),
                capacity: c > 0 ? c : null,
                clearCapacity: c <= 0,
              );
              if (err != null) {
                showToast(ref, err);
                return;
              }
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    zone.dispose();
    code.dispose();
    cap.dispose();
  }
}
