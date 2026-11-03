import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rm_core/backup/backup_service.dart';
import 'package:rm_core/backup/backup_settings.dart';
import 'package:rm_core/models/tone.dart';
import 'package:rm_core/state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'package:rm_core/util/format.dart';
import '../../widgets/badge.dart';
import '../../widgets/common.dart';
import '../../widgets/toast.dart';

/// Administración → Respaldos: programación, respaldo manual, lista y restauración.
class BackupsTab extends ConsumerStatefulWidget {
  const BackupsTab({super.key});

  @override
  ConsumerState<BackupsTab> createState() => _BackupsTabState();
}

class _BackupsTabState extends ConsumerState<BackupsTab> {
  late final TextEditingController _folder;
  late final TextEditingController _keep;
  late final TextEditingController _day;
  String? _folderMsg;
  bool _folderOk = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(backupProvider).settings;
    _folder = TextEditingController(text: s.folder);
    _keep = TextEditingController(text: '${s.keep}');
    _day = TextEditingController(text: '${s.dayOfMonth}');
  }

  @override
  void dispose() {
    _folder.dispose();
    _keep.dispose();
    _day.dispose();
    super.dispose();
  }

  BackupService get _svc => ref.read(backupProvider.notifier);

  Future<void> _backupNow() async {
    final r = await _svc.backupNow();
    if (!mounted) return;
    showToast(ref, r.ok ? 'Respaldo creado: ${r.file!.uri.pathSegments.last}' : r.error!);
    setState(() {});
  }

  Future<void> _pickTime(BackupSettings s) async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: s.hour, minute: s.minute));
    if (t == null) return;
    _svc.update((x) => x
      ..hour = t.hour
      ..minute = t.minute);
  }

  void _tapDay(BackupSettings s, int d) {
    if (s.frequency == BackupFrequency.weekly) {
      _svc.update((x) => x.weekdays = [d]);
    } else if (!s.activeWeekdays.contains(d)) {
      // Dos veces por semana: siempre dos días; el día nuevo reemplaza al elegido primero.
      final keep = s.weekdays.where(s.activeWeekdays.contains).toList();
      _svc.update((x) => x.weekdays = [keep.isEmpty ? s.activeWeekdays.last : keep.last, d]);
    }
  }

  Future<void> _testFolder() async {
    final err = await _svc.testFolderAsync(_folder.text);
    if (!mounted) return;
    setState(() {
      _folderOk = err == null;
      _folderMsg = err ?? 'Carpeta OK: se puede escribir.';
    });
  }

  Future<void> _startFresh() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Empezar con un almacén vacío'),
        content: const SizedBox(
          width: 420,
          child: Text('El archivo dañado se aparta (no se borra) y la app empieza sin inventario, recibos ni '
              'órdenes. Los usuarios y PIN se conservan. Si tienes un respaldo, mejor restáuralo.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Empezar vacío')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    ref.read(appProvider.notifier).startFresh();
    showToast(ref, 'Se empezó con un almacén vacío');
  }

  Future<void> _restore(BackupInfo b) async {
    final BackupContents contents;
    try {
      contents = await _svc.inspectAsync(b);
    } on FormatException catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('No se puede restaurar'),
          content: SizedBox(width: 420, child: Text('${b.name}: ${e.message}')),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
        ),
      );
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (_) => _RestoreDialog(info: b, contents: contents));
    if (ok != true || !mounted) return;
    final err = await _svc.restore(b.file);
    if (!mounted) return;
    if (err != null) {
      showToast(ref, err);
      setState(() {});
    }
    // Si salió bien, la sesión se cerró: aparece la pantalla de PIN.
  }

  @override
  Widget build(BuildContext context) {
    final backup = ref.watch(backupProvider);
    final app = ref.watch(appProvider);
    final s = backup.settings;
    final c = context.c;
    final now = ref.read(clockProvider)();
    final next = s.nextScheduled(now);
    final folder = _svc.folder;
    final list = _svc.list();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (app.dataStoreError != null) ...[
          NoteBox(
            '',
            tone: Tone.crit,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Los datos del almacén no se pudieron leer', style: T.body(context, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${app.dataStoreError}\nNo se guarda nada hasta que restaures un respaldo de la lista o empieces vacío.',
                    style: T.body(context, size: 12.5)),
                const SizedBox(height: 10),
                OutlinedButton(onPressed: _startFresh, child: const Text('Empezar vacío')),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        SectionCard(
          title: 'Programación de respaldos',
          subtitle: 'Copia los datos del almacén, usuarios (PIN cifrado), auditoría y configuración en un archivo .zip. '
              'Corre mientras la app está abierta; si a la hora programada estaba cerrada, respalda al abrirla.',
          trailing: backup.running ? const AppBadge('Respaldando…', tone: Tone.accent) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 14,
                runSpacing: 14,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  LabeledField(
                    label: 'Frecuencia',
                    width: 230,
                    child: AppDropdown<BackupFrequency>(
                      value: s.frequency,
                      items: [for (final v in BackupFrequency.values) ddItem(context, v, v.label)],
                      onChanged: (v) {
                        if (v == null) return;
                        _svc.update((x) => x.frequency = v);
                        showToast(ref, 'Respaldos: ${v.label}');
                      },
                    ),
                  ),
                  if (s.frequency != BackupFrequency.manual)
                    LabeledField(
                      label: 'Hora',
                      width: 150,
                      child: OutlinedButton.icon(
                        key: const ValueKey('backup-time'),
                        onPressed: () => _pickTime(s),
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text(fmtTime(s.hour, s.minute)),
                      ),
                    ),
                  if (s.frequency == BackupFrequency.monthly)
                    LabeledField(
                      label: 'Día del mes (1–28)',
                      width: 150,
                      child: NumField(
                        controller: _day,
                        onChanged: (v) {
                          final d = parseInt(v);
                          if (d >= 1 && d <= 28) _svc.update((x) => x.dayOfMonth = d);
                        },
                      ),
                    ),
                  LabeledField(
                    label: 'Conservar los últimos',
                    width: 160,
                    child: NumField(
                      controller: _keep,
                      onChanged: (v) {
                        final k = parseInt(v);
                        if (k >= 1 && k <= 365) _svc.update((x) => x.keep = k);
                      },
                    ),
                  ),
                ],
              ),
              if (s.frequency.weekdayCount > 0) ...[
                const SizedBox(height: 14),
                Text(s.frequency.weekdayCount == 1 ? 'Día de la semana' : 'Dos días de la semana',
                    style: T.muted(context, size: 12.5)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in kWeekdayShort.keys)
                      ChoiceChip(
                        key: ValueKey('backup-day-$d'),
                        label: Text(kWeekdayShort[d]!),
                        tooltip: kWeekdayNames[d],
                        selected: s.activeWeekdays.contains(d),
                        onSelected: (_) => _tapDay(s, d),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  LabeledField(
                    label: 'Carpeta de respaldos (vacío = predeterminada)',
                    width: 420,
                    child: AppTextField(
                      controller: _folder,
                      mono: true,
                      hint: folder?.path ?? r'D:\Respaldos o \\servidor\carpeta',
                      onChanged: (v) {
                        _svc.update((x) => x.folder = v.trim());
                        setState(() => _folderMsg = null);
                      },
                    ),
                  ),
                  OutlinedButton(onPressed: _testFolder, child: const Text('Probar carpeta')),
                ],
              ),
              if (_folderMsg != null) ...[
                const SizedBox(height: 6),
                Text(_folderMsg!, style: T.body(context, size: 12, color: _folderOk ? c.good : c.crit)),
              ],
              const SizedBox(height: 16),
              Text(s.describe(), style: T.body(context, size: 13, weight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                next == null ? 'Sin respaldos automáticos.' : 'Próximo respaldo: ${fmtWeekdayDateTime(next)}',
                style: T.muted(context, size: 12.5),
              ),
              const SizedBox(height: 4),
              Text(
                s.lastBackup == null ? 'Aún no se ha hecho ningún respaldo.' : 'Último respaldo: ${fmtDateTime(s.lastBackup!)}',
                style: T.muted(context, size: 12.5),
              ),
              if (s.lastError != null) ...[
                const SizedBox(height: 4),
                Text('Último intento falló${s.lastAttempt == null ? '' : ' (${fmtDateTime(s.lastAttempt!)})'}: ${s.lastError}',
                    style: T.body(context, size: 12.5, color: c.crit)),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: backup.running || app.dataStoreError != null ? null : _backupNow,
                  icon: backup.running
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.backup_outlined, size: 18),
                  label: Text(backup.running ? 'Respaldando…' : 'Respaldar ahora'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionCard(
          title: 'Respaldos guardados',
          subtitle: folder == null ? 'Sin carpeta de respaldos.' : folder.path,
          // En un cliente la carpeta está en el servidor: no se puede abrir desde aquí.
          trailing: folder == null || !_svc.isLocal || !Platform.isWindows
              ? null
              : TextButton.icon(
                  onPressed: () {
                    folder.createSync(recursive: true);
                    Process.run('explorer.exe', [folder.path]);
                  },
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('Abrir carpeta'),
                ),
          child: list.isEmpty
              ? Text('No hay respaldos en la carpeta.', style: T.muted(context, size: 13))
              : Column(
                  children: [
                    for (final b in list)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(fmtWeekdayDateTime(b.createdAt),
                                          style: T.body(context, size: 13.5, weight: FontWeight.w600)),
                                      if (b.isSafety) const AppBadge('Antes de restaurar', tone: Tone.warn),
                                    ],
                                  ),
                                  Text('${b.name} · ${fmtBytes(b.size)}',
                                      style: T.mono(context, size: 11.5, color: c.inkMuted),
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: backup.running ? null : () => _restore(b),
                              child: const Text('Restaurar'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Confirmación de restauración: muestra el contenido y pide el PIN del administrador.
class _RestoreDialog extends ConsumerStatefulWidget {
  const _RestoreDialog({required this.info, required this.contents});
  final BackupInfo info;
  final BackupContents contents;

  @override
  ConsumerState<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends ConsumerState<_RestoreDialog> {
  final _pin = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    // En un cliente el PIN se comprueba en el servidor.
    final ok = await ref.read(appProvider.notifier).confirmPin(_pin.text);
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = 'PIN incorrecto.');
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.contents;
    final c = context.c;
    final counts = k.counts;
    final at = k.createdAt;
    return AlertDialog(
      title: const Text('Restaurar respaldo'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Respaldo del ${at == null ? fmtWeekdayDateTime(widget.info.createdAt) : fmtWeekdayDateTime(at)}'
                ' · hecho por ${k.createdBy} en ${k.machine}',
                style: T.body(context, size: 13, weight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                '${counts['productos'] ?? k.data.products.length} productos · '
                '${fmtInt((counts['unidades'] as num?)?.toInt() ?? k.data.totalUnits)} unidades · '
                '${counts['ordenes'] ?? k.data.orders.length} órdenes · '
                '${counts['recibos'] ?? k.data.receipts.length} recibos · '
                '${counts['usuarios'] ?? k.users.users.length} usuarios',
                style: T.muted(context, size: 12.5),
              ),
              const SizedBox(height: 12),
              const NoteBox(
                'Se reemplazan inventario, recibos, órdenes, transferencias, historial, tiendas, canastas, '
                'parámetros, usuarios y PIN por los del respaldo. Antes se guarda un respaldo de seguridad de lo '
                'actual. La dirección API de este PC y la auditoría no cambian. La sesión se cierra.',
                tone: Tone.warn,
              ),
              const SizedBox(height: 12),
              LabeledField(
                label: 'Tu PIN para confirmar',
                child: TextField(
                  key: const ValueKey('restore-pin'),
                  controller: _pin,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                  style: T.mono(context, size: 20),
                  onSubmitted: (_) => _confirm(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: T.body(context, size: 12.5, color: c.crit)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _confirm, child: const Text('Restaurar')),
      ],
    );
  }
}
