import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rm_core/state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/toast.dart';
import 'sync_card.dart';

class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  late final _company = TextEditingController(text: ref.read(appProvider).settings.companyName);
  late final _warehouse = TextEditingController(text: ref.read(appProvider).settings.warehouseName);
  late final _age = TextEditingController(text: '${ref.read(appProvider).settings.ageAlertDays}');
  late final _stale = TextEditingController(text: '${ref.read(appProvider).settings.staleDays}');
  late final _idle = TextEditingController(text: '${ref.read(appProvider).settings.autoLogoutMinutes}');
  String? _error;

  @override
  void dispose() {
    _idle.dispose();
    _company.dispose();
    _warehouse.dispose();
    _age.dispose();
    _stale.dispose();
    super.dispose();
  }

  void _save() {
    final err = ref.read(appProvider.notifier).updateSettings(
          ageAlertDays: parseInt(_age.text),
          staleDays: parseInt(_stale.text),
          companyName: _company.text.trim().isEmpty ? null : _company.text.trim(),
          warehouseName: _warehouse.text.trim().isEmpty ? null : _warehouse.text.trim(),
        );
    setState(() => _error = err);
    if (err == null) showToast(ref, 'Parámetros guardados');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SyncCard(),
        const SizedBox(height: 20),
        SectionCard(
          title: 'Seguridad',
          subtitle: 'Cierra la sesión si nadie usa la app durante estos minutos (0 = nunca). '
              'Vale para todas las cuentas de este PC.',
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              LabeledField(
                label: 'Cerrar sesión tras (minutos)',
                width: 220,
                child: NumField(
                  controller: _idle,
                  onChanged: (v) {
                    final m = int.tryParse(v.trim());
                    if (m != null) ref.read(appProvider.notifier).setAutoLogoutMinutes(m);
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          title: 'Umbrales de antigüedad',
          subtitle: 'Definen las alertas del dashboard y el inventario sin movimiento.',
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              LabeledField(label: 'Alerta de antigüedad (días)', width: 220, child: NumField(controller: _age)),
              LabeledField(label: 'Sin movimiento (días)', width: 220, child: NumField(controller: _stale)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          title: 'General',
          subtitle: 'Nombre que se muestra al pie de la barra lateral.',
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              LabeledField(label: 'Empresa', width: 260, child: AppTextField(controller: _company)),
              LabeledField(label: 'Almacén', width: 260, child: AppTextField(controller: _warehouse)),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: T.body(context, size: 12.5, color: c.crit)),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(onPressed: _save, child: const Text('Guardar parámetros')),
        ),
      ],
    );
  }
}
