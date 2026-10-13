import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
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

String permLabel(Area a) => a == Area.dashboard ? 'Acceso al dashboard' : kAreaLabels[a]!;

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final _expanded = <String>{};
  String? _previewId = 'u3';

  void _newUser() {
    final id = ref.read(appProvider.notifier).addUser();
    setState(() => _expanded.add(id));
    showToast(ref, 'Usuario creado con el rol Piqueador — completa sus datos.');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final n = ref.read(appProvider.notifier);
    final preview = s.users.firstWhereOrNull((u) => u.id == _previewId);
    final previewValid = preview != null && preview.active;
    final simulating = s.simulatedUserId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenHeader(
          eyebrow: 'Administración',
          title: 'Usuarios y permisos',
          subtitle: 'Define quién puede ver y operar cada sección del sistema. Los roles traen permisos por defecto que puedes ajustar.',
          actions: [FilledButton(onPressed: _newUser, child: const Text('+ Nuevo usuario'))],
        ),
        SectionCard(
          title: 'Vista previa de acceso',
          subtitle: 'Simula cómo ve el dashboard un usuario: solo quedan disponibles las secciones permitidas para su rol.',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              LabeledField(
                label: 'Usuario',
                width: 340,
                child: AppDropdown<String>(
                  value: preview?.id,
                  items: [
                    for (final u in s.users)
                      ddItem(context, u.id, '${u.name} — ${u.role}${u.active ? '' : ' (inactivo)'}', enabled: u.active),
                  ],
                  onChanged: (v) => setState(() => _previewId = v),
                ),
              ),
              FilledButton(
                onPressed: previewValid ? () => n.startSimulation(preview.id) : null,
                child: const Text('Ver como este usuario'),
              ),
              OutlinedButton(
                onPressed: simulating ? n.exitSimulation : null,
                child: const Text('Salir de la vista previa'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        for (final u in s.users)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _UserCard(
              key: ValueKey(u.id),
              user: u,
              expanded: _expanded.contains(u.id),
              onToggle: () => setState(() => _expanded.contains(u.id) ? _expanded.remove(u.id) : _expanded.add(u.id)),
              onClose: () => setState(() => _expanded.remove(u.id)),
            ),
          ),
      ],
    );
  }
}

class _UserCard extends ConsumerWidget {
  const _UserCard({super.key, required this.user, required this.expanded, required this.onToggle, required this.onClose});
  final AppUser user;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appProvider);
    final c = context.c;
    final u = user;
    return ExpandableCard(
      title: u.name.isEmpty ? '(sin nombre)' : u.name,
      monoTitle: false,
      subtitle: u.email.isEmpty ? 'sin correo' : u.email,
      monoSubtitle: true,
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: u.active ? c.accentSoft : c.surfaceSunken,
          shape: BoxShape.circle,
        ),
        child: Text(
          initials(u.name),
          style: T.h(context, 16, weight: FontWeight.w700, color: u.active ? c.accent : c.inkMuted),
        ),
      ),
      trailing: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.end,
        children: [
          AppBadge(u.role, tone: Tone.accent),
          u.active ? const AppBadge('Activo', tone: Tone.good) : const AppBadge('Inactivo', tone: Tone.neutral),
        ],
      ),
      extra: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [for (final a in Area.values) _AccessChip(label: kAreaLabels[a]!, on: u.can(a))],
      ),
      expanded: expanded,
      onToggle: onToggle,
      child: _UserEditor(key: ValueKey('ed-${u.id}'), user: u, onClose: onClose),
    );
  }
}

class _AccessChip extends StatelessWidget {
  const _AccessChip({required this.label, required this.on});
  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: on ? c.goodSoft : c.surfaceSunken,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Text(
        label,
        style: T.body(context, size: 11, weight: FontWeight.w600, color: on ? c.good : c.inkFaint).copyWith(
          decoration: on ? null : TextDecoration.lineThrough,
          decorationColor: c.inkFaint,
        ),
      ),
    );
  }
}

class _UserEditor extends ConsumerStatefulWidget {
  const _UserEditor({super.key, required this.user, required this.onClose});
  final AppUser user;
  final VoidCallback onClose;

  @override
  ConsumerState<_UserEditor> createState() => _UserEditorState();
}

class _UserEditorState extends ConsumerState<_UserEditor> {
  late final _name = TextEditingController(text: widget.user.name);
  late final _email = TextEditingController(text: widget.user.email);

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appProvider);
    final n = ref.read(appProvider.notifier);
    final u = widget.user;
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
              child: AppTextField(controller: _name, onChanged: (v) => n.updateUser(u.id, name: v)),
            ),
            LabeledField(
              label: 'Correo',
              width: 280,
              child: AppTextField(controller: _email, mono: true, onChanged: (v) => n.updateUser(u.id, email: v)),
            ),
            LabeledField(
              label: 'Rol',
              width: 220,
              child: AppDropdown<String>(
                value: u.role,
                items: [for (final r in kRoles) ddItem(context, r, r)],
                onChanged: (v) => n.updateUser(u.id, role: v),
              ),
            ),
            LabeledField(
              label: 'Estado',
              width: 150,
              child: AppDropdown<bool>(
                value: u.active,
                items: [ddItem(context, true, 'Activo'), ddItem(context, false, 'Inactivo')],
                onChanged: (v) => n.updateUser(u.id, active: v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text('PERMISOS POR SECCIÓN', style: T.th(context)),
            OutlinedButton(
              style: compactOutlined(),
              onPressed: () {
                n.applyRolePreset(u.id);
                showToast(ref, 'Permisos por defecto de «${u.role}» aplicados a ${u.name}');
              },
              child: const Text('Aplicar permisos por defecto del rol'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, box) {
          final cols = box.maxWidth >= 820 ? 4 : (box.maxWidth >= 520 ? 2 : 1);
          final w = ((box.maxWidth - 10 * (cols - 1)) / cols).floorToDouble();
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final a in Area.values)
                SizedBox(
                  width: w,
                  child: Material(
                    color: u.can(a) ? c.accentSoft.withValues(alpha: 0.5) : c.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(R.input),
                      side: BorderSide(color: u.can(a) ? c.accent.withValues(alpha: 0.4) : c.border),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(R.input),
                      onTap: () => n.setPerm(u.id, a, !u.can(a)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 2, 10, 2),
                        child: Row(
                          children: [
                            Checkbox(value: u.can(a), onChanged: (v) => n.setPerm(u.id, a, v ?? false)),
                            Expanded(child: Text(permLabel(a), style: T.body(context, size: 13, weight: FontWeight.w500))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        }),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: c.crit, side: BorderSide(color: c.crit.withValues(alpha: 0.5))),
              onPressed: () {
                final name = u.name;
                n.deleteUser(u.id);
                showToast(ref, 'Usuario $name eliminado');
              },
              child: const Text('Eliminar usuario'),
            ),
            OutlinedButton(onPressed: widget.onClose, child: const Text('Cerrar')),
          ],
        ),
      ],
    );
  }
}
