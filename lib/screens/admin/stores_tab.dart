import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/admin_config.dart';
import '../../models/tone.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/badge.dart';
import '../../widgets/common.dart';
import '../../widgets/expandable_card.dart';
import '../../widgets/pick_step_row.dart';
import '../../widgets/toast.dart';

class StoresTab extends ConsumerStatefulWidget {
  const StoresTab({super.key});

  @override
  ConsumerState<StoresTab> createState() => _StoresTabState();
}

class _StoresTabState extends ConsumerState<StoresTab> {
  final _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Text(
                'Almacén central y sucursales disponibles para transferencias y órdenes. '
                'La dirección API se guarda para conectar cada tienda.',
                style: T.muted(context),
              ),
            ),
            FilledButton(
              onPressed: () {
                final id = ref.read(appProvider.notifier).addStore();
                setState(() => _expanded.add(id));
                showToast(ref, 'Tienda creada — completa su nombre y dirección API.');
              },
              child: const Text('+ Nueva tienda'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (final st in s.stores)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ExpandableCard(
              key: ValueKey(st.id),
              title: st.name,
              monoTitle: false,
              subtitle: st.apiUrl.isEmpty ? 'Sin dirección API' : st.apiUrl,
              monoSubtitle: true,
              leading: AppBadge(st.code, tone: Tone.accent),
              trailing: Wrap(spacing: 6, children: [
                if (st.isCentral) const AppBadge('Central', tone: Tone.neutral),
                AppBadge(st.active ? 'Activa' : 'Inactiva', tone: st.active ? Tone.good : Tone.neutral),
              ]),
              expanded: _expanded.contains(st.id),
              onToggle: () => setState(() => _expanded.contains(st.id) ? _expanded.remove(st.id) : _expanded.add(st.id)),
              child: _StoreEditor(
                key: ValueKey('ed-${st.id}'),
                store: st,
                onClose: () => setState(() => _expanded.remove(st.id)),
              ),
            ),
          ),
      ],
    );
  }
}

class _StoreEditor extends ConsumerStatefulWidget {
  const _StoreEditor({super.key, required this.store, required this.onClose});
  final Store store;
  final VoidCallback onClose;

  @override
  ConsumerState<_StoreEditor> createState() => _StoreEditorState();
}

class _StoreEditorState extends ConsumerState<_StoreEditor> {
  late final _name = TextEditingController(text: widget.store.name);
  late final _code = TextEditingController(text: widget.store.code);
  late final _url = TextEditingController(text: widget.store.apiUrl);
  late final _key = TextEditingController(text: widget.store.apiKey);
  String? _error;
  bool _testing = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  /// Aplica un cambio y muestra el error (si lo hay) bajo el formulario.
  void _apply(String? err) => setState(() => _error = err);

  Future<void> _test() async {
    final n = ref.read(appProvider.notifier);
    setState(() => _testing = true);
    final res = await n.testStoreConnection(widget.store.id);
    if (!mounted) return;
    setState(() => _testing = false);
    showToast(ref, res);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appProvider);
    final n = ref.read(appProvider.notifier);
    final st = widget.store;
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            LabeledField(
              label: 'Nombre',
              width: 260,
              child: AppTextField(
                controller: _name,
                onChanged: (v) {
                  if (st.isCentral) return;
                  final err = n.updateStore(st.id, name: v);
                  _apply(err);
                },
              ),
            ),
            LabeledField(
              label: 'Código',
              width: 120,
              child: AppTextField(controller: _code, mono: true, onChanged: (v) => _apply(n.updateStore(st.id, code: v))),
            ),
            LabeledField(
              label: 'Bin de recepción',
              width: 150,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(R.input),
                ),
                child: Text(st.receiveBin, style: T.mono(context, size: 13.5)),
              ),
            ),
            LabeledField(
              label: 'Estado',
              width: 150,
              child: AppDropdown<bool>(
                value: st.active,
                items: [ddItem(context, true, 'Activa'), ddItem(context, false, 'Inactiva')],
                onChanged: (v) => _apply(n.updateStore(st.id, active: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            LabeledField(
              label: 'Dirección API',
              width: 420,
              child: AppTextField(
                controller: _url,
                mono: true,
                hint: 'http://servidor:8180/cse.api.v1',
                onChanged: (v) => _apply(n.updateStore(st.id, apiUrl: v)),
              ),
            ),
            LabeledField(
              label: 'Clave API (opcional)',
              width: 260,
              child: AppTextField(controller: _key, mono: true, onChanged: (v) => n.updateStore(st.id, apiKey: v)),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: T.body(context, size: 12.5, color: c.crit)),
        ],
        if (st.lastCheck != null) ...[
          const SizedBox(height: 10),
          Text('Última prueba: ${st.lastCheck}', style: T.muted(context, size: 12.5)),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton(
              style: compactFilled(),
              onPressed: _testing ? null : _test,
              child: Text(_testing ? 'Probando…' : 'Probar conexión'),
            ),
            if (!st.isCentral)
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: c.crit, side: BorderSide(color: c.crit.withValues(alpha: 0.5))),
                onPressed: () {
                  final name = st.name;
                  final err = n.deleteStore(st.id);
                  showToast(ref, err ?? 'Tienda $name eliminada');
                },
                child: const Text('Eliminar tienda'),
              ),
            OutlinedButton(onPressed: widget.onClose, child: const Text('Cerrar')),
          ],
        ),
      ],
    );
  }
}
