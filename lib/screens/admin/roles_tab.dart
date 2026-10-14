import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/pick_step_row.dart';
import '../../widgets/toast.dart';
import '../users/users_screen.dart' show permLabel;

/// Permisos por defecto de cada rol. Se aplican a usuarios nuevos o con
/// «Aplicar permisos por defecto del rol»; no cambian usuarios existentes.
class RolesTab extends ConsumerWidget {
  const RolesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final n = ref.read(appProvider.notifier);
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final role in kRoles)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SectionCard(
              title: role,
              subtitle: role == 'Administrador'
                  ? 'El administrador siempre conserva acceso a Administración.'
                  : null,
              trailing: OutlinedButton(
                style: compactOutlined(),
                onPressed: () {
                  n.resetRolePreset(role);
                  showToast(ref, 'Permisos de «$role» restablecidos');
                },
                child: const Text('Restablecer'),
              ),
              child: LayoutBuilder(builder: (context, box) {
                final cols = box.maxWidth >= 820 ? 4 : (box.maxWidth >= 520 ? 2 : 1);
                final w = ((box.maxWidth - 10 * (cols - 1)) / cols).floorToDouble();
                final preset = s.presetFor(role);
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final a in Area.values)
                      SizedBox(
                        width: w,
                        child: Material(
                          color: preset[a] == true ? c.accentSoft.withValues(alpha: 0.5) : c.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(R.input),
                            side: BorderSide(
                                color: preset[a] == true ? c.accent.withValues(alpha: 0.4) : c.border),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(R.input),
                            onTap: () => n.setRolePerm(role, a, !(preset[a] ?? false)),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(4, 2, 10, 2),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: preset[a] ?? false,
                                    onChanged: (v) => n.setRolePerm(role, a, v ?? false),
                                  ),
                                  Expanded(
                                    child: Text(permLabel(a),
                                        style: T.body(context, size: 13, weight: FontWeight.w500)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              }),
            ),
          ),
      ],
    );
  }
}
