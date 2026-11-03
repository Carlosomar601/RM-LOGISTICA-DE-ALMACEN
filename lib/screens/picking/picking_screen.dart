import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/pick_session.dart';
import '../../models/tone.dart';
import '../../state/app_state.dart';
import '../../state/pick_engine.dart';
import '../../util/clock.dart';
import '../../widgets/badge.dart';
import '../../widgets/common.dart';
import '../../widgets/pick_step_row.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/toast.dart';

/// Pill de estado de una sesión, en orden de prioridad.
Widget sessionStatusPill(PickSession s) {
  final pending = pendingCount(s);
  final sf = s.shortfall;
  if (pending > 0) return Pill('$pending por verificar', tone: Tone.warn);
  if (sf != null && sf.status == ShortfallStatus.unresolved) {
    return Pill('Faltan ${sf.take} unidades', tone: Tone.crit);
  }
  if (sf != null && sf.status == ShortfallStatus.missing) {
    return const Pill('Completo con faltante declarado', tone: Tone.warn);
  }
  final picked = s.steps.where((st) => st.status == StepStatus.picked).length;
  return Pill('Todo verificado · $picked canastas', tone: Tone.good);
}

String sessionNote(PickSession s) {
  final sf = s.shortfall;
  if (pendingCount(s) > 0) {
    return 'Recoge cada canasta en el orden FIFO indicado. Si una canasta no tiene la mercancía, márcala como «No está aquí» y el sistema buscará automáticamente la siguiente ubicación más antigua.';
  }
  if (sf != null && sf.status == ShortfallStatus.unresolved) {
    return 'No hay suficiente existencia en Almacén Central. Trae unidades desde otra tienda o declara el faltante para poder confirmar.';
  }
  if (sf != null && sf.status == ShortfallStatus.missing) {
    return 'El faltante quedó declarado. Al confirmar se descontará lo recogido y el faltante se registrará como «No encontrado» en el Historial.';
  }
  return 'Todas las canastas están verificadas. Confirma el piqueo para descontar el inventario de cada localización.';
}

class PickingScreen extends ConsumerStatefulWidget {
  const PickingScreen({super.key});

  @override
  ConsumerState<PickingScreen> createState() => _PickingScreenState();
}

class _PickingScreenState extends ConsumerState<PickingScreen> {
  late String _productId = _firstProduct();
  final _qty = TextEditingController(text: demoMode ? '40' : '');
  final _doc = TextEditingController(text: demoMode ? 'OV-10482' : '');

  String _firstProduct() {
    final ps = ref.read(appProvider).products;
    return ps.any((p) => p.id == 'p1') ? 'p1' : (ps.isEmpty ? '' : ps.first.id);
  }

  @override
  void initState() {
    super.initState();
    final existing = ref.read(appProvider).pickSessions[kSingleSessionKey];
    if (existing != null) {
      _productId = existing.productId;
      _qty.text = '${existing.qtyRequested}';
      _doc.text = existing.doc;
    }
  }

  @override
  void dispose() {
    _qty.dispose();
    _doc.dispose();
    super.dispose();
  }

  void _suggest() {
    final qty = parseInt(_qty.text);
    if (qty <= 0) {
      showToast(ref, 'Ingresa una cantidad a piquear mayor que 0.');
      return;
    }
    final doc = _doc.text.trim().isEmpty ? '—' : _doc.text.trim();
    ref.read(appProvider.notifier).suggestSingle(_productId, qty, doc);
  }

  void _confirm() {
    final st = ref.read(appProvider);
    final s = st.pickSessions[kSingleSessionKey];
    if (s == null) return;
    final code = st.product(s.productId).code;
    final res = ref.read(appProvider.notifier).confirmSingle();
    if (res == null) return;
    if (res.shortQty > 0) {
      showToast(ref,
          'Piqueo confirmado con faltante: $code · ${res.delivered}/${s.qtyRequested} unidades · orden ${s.doc}');
    } else {
      showToast(ref, 'Piqueo confirmado: $code · ${res.delivered} unidades · orden ${s.doc}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final s = state.pickSessions[kSingleSessionKey];
    // Los productos llegan con los recibos de RM: si el elegido no existe, el primero.
    if (state.products.isNotEmpty && state.products.every((p) => p.id != _productId)) {
      _productId = state.products.first.id;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScreenHeader(
          eyebrow: 'Piqueo',
          title: 'Piqueo FIFO',
          subtitle:
              'El sistema indica qué producto recoger, de qué localización y cuánto tomar de cada una — siempre del recibo más antiguo primero.',
        ),
        const FlowSteps(steps: [
          ('Producto y cantidad', 'Indica el producto, la cantidad a piquear y la orden o documento.'),
          ('Ruta sugerida', 'Se proponen las canastas de Almacén Central del recibo más antiguo al más reciente.'),
          ('Verificación', 'Marca cada canasta como recogida o «No está aquí»; el sistema reacomoda la ruta.'),
          ('Confirmación', 'Se descuenta cada localización y todo queda registrado en el Historial.'),
        ]),
        const SizedBox(height: 20),
        SectionCard(
          title: 'Nueva ruta de piqueo',
          child: state.products.isEmpty
              ? const NoteBox('Aún no hay productos. Llegan al importar recibos de RM en «Recibido sin ubicar».')
              : Wrap(
            spacing: 14,
            runSpacing: 14,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              LabeledField(
                label: 'Producto',
                width: 360,
                child: AppDropdown<String>(
                  value: _productId,
                  items: [
                    for (final p in state.products)
                      ddItem(context, p.id, '${p.code} — ${p.desc}'),
                  ],
                  onChanged: (v) => setState(() => _productId = v ?? _productId),
                ),
              ),
              LabeledField(label: 'Cantidad a piquear', width: 150, child: NumField(controller: _qty)),
              LabeledField(
                label: 'Orden / documento',
                width: 180,
                child: AppTextField(controller: _doc, mono: true),
              ),
              FilledButton(onPressed: _suggest, child: const Text('Sugerir ruta de piqueo')),
            ],
          ),
        ),
        if (s != null) ...[
          const SizedBox(height: 20),
          SectionCard(
            title: 'Ruta de piqueo — ${state.product(s.productId).code}',
            subtitle: '${state.product(s.productId).desc} · ${s.qtyRequested} unidades · documento ${s.doc}',
            trailing: sessionStatusPill(s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StatRow(tiles: [
                  StatTile(
                    label: 'Canastas en ruta',
                    value: '${s.steps.where((st) => st.status != StepStatus.missingHere).length}',
                  ),
                  StatTile(
                    label: 'Recogidas',
                    value: '${s.steps.where((st) => st.status == StepStatus.picked).length}',
                    tone: Tone.good,
                  ),
                  StatTile(label: 'Por verificar', value: '${pendingCount(s)}', tone: Tone.warn),
                  StatTile(
                    label: 'No encontradas',
                    value: '${s.steps.where((st) => st.status == StepStatus.missingHere).length}',
                    hint: 'en el bin indicado',
                    tone: Tone.crit,
                  ),
                  StatTile(
                    label: 'Sin ubicar en almacén',
                    value: '${s.shortfall?.take ?? 0}',
                    hint: 'unidades',
                    tone: (s.shortfall?.take ?? 0) > 0 ? Tone.crit : null,
                  ),
                ]),
                const SizedBox(height: 16),
                PickStepsView(sessionKey: kSingleSessionKey),
                const SizedBox(height: 14),
                NoteBox(sessionNote(s)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton(
                      onPressed: sessionCanConfirm(s) ? _confirm : null,
                      child: const Text('Confirmar piqueo'),
                    ),
                    OutlinedButton(
                      onPressed: () => ref.read(appProvider.notifier).cancelSingle(),
                      child: const Text('Cancelar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
