import 'package:flutter/material.dart';

import 'package:rm_core/models/tone.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Badge (radio 6): fondo suave + texto en color.
class AppBadge extends StatelessWidget {
  const AppBadge(this.text, {super.key, this.tone = Tone.neutral, this.strong = false});

  final String text;
  final Tone tone;

  /// Variante sólida (fondo en color, texto claro).
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bg = strong ? c.fg(tone) : c.soft(tone);
    final fg = strong ? c.accentInk : c.fg(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(R.badge)),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: T.body(context, size: 11.5, weight: FontWeight.w700, color: fg, height: 1.2),
      ),
    );
  }
}

/// Pill (radio 20) para contadores y estados de encabezado.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.tone = Tone.neutral, this.mono = false});

  final String text;
  final Tone tone;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = c.fg(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.soft(tone),
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: mono
            ? T.mono(context, size: 11.5, weight: FontWeight.w600, color: fg)
            : T.body(context, size: 12, weight: FontWeight.w600, color: fg, height: 1.2),
      ),
    );
  }
}

/// Badge de antigüedad: ≥45 crit, 20–44 warn, <20 good. Texto "{n} días".
class AgeBadge extends StatelessWidget {
  const AgeBadge(this.days, {super.key});
  final int days;

  @override
  Widget build(BuildContext context) => AppBadge('$days días', tone: ageTone(days));
}
