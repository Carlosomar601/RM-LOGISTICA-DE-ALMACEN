import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/tone.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Tarjeta base: radio 14, borde 1px, sombra suave.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.flushBody = false,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  /// Si es true, el cuerpo (p. ej. una tabla) va de borde a borde.
  final bool flushBody;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final hasHeader = title != null || trailing != null;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(R.card),
        boxShadow: cardShadow(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasHeader)
            Padding(
              padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, flushBody ? 14 : 12),
              child: CardHeader(title: title, subtitle: subtitle, trailing: trailing),
            ),
          if (flushBody)
            child
          else
            Padding(
              padding: hasHeader ? EdgeInsets.fromLTRB(padding.left, 0, padding.right, padding.bottom) : padding,
              child: child,
            ),
        ],
      ),
    );
  }
}

class CardHeader extends StatelessWidget {
  const CardHeader({super.key, this.title, this.subtitle, this.trailing});
  final String? title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) Text(title!.toUpperCase(), style: T.h(context, 20, weight: FontWeight.w700)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: T.muted(context, size: 13)),
        ],
      ],
    );
    if (trailing == null) return texts;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [texts, trailing!],
    );
  }
}

/// Encabezado de pantalla (Barlow Condensed, mayúsculas).
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.eyebrow, this.subtitle, this.actions = const []});

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final texts = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (eyebrow != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                eyebrow!.toUpperCase(),
                style: T.body(context, size: 11, weight: FontWeight.w700, color: c.accent)
                    .copyWith(letterSpacing: 1.2),
              ),
            ),
          Text(title.toUpperCase(), style: T.display(context, size: 34)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!, style: T.muted(context, size: 14)),
          ],
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 16,
        runSpacing: 14,
        children: [
          texts,
          if (actions.isNotEmpty) Wrap(spacing: 10, runSpacing: 10, children: actions),
        ],
      ),
    );
  }
}

/// Encabezado de pasos numerados (intro de flujos).
class FlowSteps extends StatelessWidget {
  const FlowSteps({super.key, required this.steps});
  final List<(String, String)> steps;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 900 ? steps.length : (box.maxWidth >= 560 ? 2 : 1);
      const gap = 12.0;
      final w = ((box.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < steps.length; i++)
            SizedBox(
              width: w,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(R.tile),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                      child: Text('${i + 1}',
                          style: T.mono(context, size: 12, weight: FontWeight.w600, color: c.accentInk)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(steps[i].$1.toUpperCase(), style: T.h(context, 15.5, weight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text(steps[i].$2, style: T.muted(context, size: 12.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// Campo con etiqueta superior.
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child, this.width});
  final String label;
  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final col = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: T.body(context, size: 12, weight: FontWeight.w600, color: context.c.inkMuted)),
        const SizedBox(height: 6),
        child,
      ],
    );
    return width == null ? col : SizedBox(width: width, child: col);
  }
}

/// Dropdown temático.
class AppDropdown<V> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.mono = false,
  });

  final V? value;
  final List<DropdownMenuItem<V>> items;
  final ValueChanged<V?>? onChanged;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return DropdownButtonFormField<V>(
      initialValue: value,
      key: ValueKey(value),
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      isDense: true,
      dropdownColor: c.surface,
      borderRadius: BorderRadius.circular(R.input),
      icon: Icon(Icons.expand_more, size: 18, color: c.inkMuted),
      style: mono ? T.mono(context, size: 13) : T.body(context, size: 13.5),
      menuMaxHeight: 420,
    );
  }
}

DropdownMenuItem<V> ddItem<V>(BuildContext context, V value, String label, {bool enabled = true, bool mono = false}) =>
    DropdownMenuItem<V>(
      value: value,
      enabled: enabled,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (mono ? T.mono(context, size: 13) : T.body(context, size: 13.5))
            .copyWith(color: enabled ? null : context.c.inkFaint),
      ),
    );

/// Campo numérico entero.
class NumField extends StatelessWidget {
  const NumField({super.key, required this.controller, this.onChanged, this.hint});
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: T.mono(context, size: 13.5),
        decoration: InputDecoration(hintText: hint),
      );
}

class AppTextField extends StatelessWidget {
  const AppTextField({super.key, required this.controller, this.onChanged, this.hint, this.mono = false});
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String? hint;
  final bool mono;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        style: mono ? T.mono(context, size: 13.5) : T.body(context, size: 13.5),
        decoration: InputDecoration(hintText: hint),
      );
}

int parseInt(String s) => int.tryParse(s.trim()) ?? 0;

/// Nota informativa con borde izquierdo.
class NoteBox extends StatelessWidget {
  const NoteBox(this.text, {super.key, this.tone = Tone.neutral, this.child});
  final String text;
  final Tone tone;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: c.soft(tone),
        borderRadius: BorderRadius.circular(R.input),
        border: Border(left: BorderSide(color: c.fg(tone), width: 3)),
      ),
      child: child ?? Text(text, style: T.body(context, size: 12.5, color: tone == Tone.neutral ? c.inkMuted : c.ink)),
    );
  }
}

/// Logo de Retail Manager, cambia de variante según el brillo. Sin caja de fondo.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.height = 52});
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = context.c;
    return Image.asset(
      dark ? 'assets/logo_on_dark.webp' : 'assets/logo_on_light.webp',
      height: height,
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stack) {
        // Respaldo mientras no estén los archivos del logo en assets/.
        final ink = dark ? Colors.white : const Color(0xFF0B0E21);
        return SizedBox(
          height: height,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final col in [c.accent, const Color(0xFF2E7DD7), c.good])
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(color: col, shape: BoxShape.circle),
                    ),
                ]),
                const SizedBox(height: 3),
                Text('RETAIL', style: T.display(context, size: 22, color: ink).copyWith(height: 0.95)),
                Text('MANAGER', style: T.display(context, size: 22, color: ink).copyWith(height: 0.95)),
                const SizedBox(height: 3),
                Container(width: 64, height: 3, color: const Color(0xFF2E7DD7)),
              ],
            ),
          ),
        );
      },
    );
  }
}
