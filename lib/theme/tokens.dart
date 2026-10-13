import 'package:flutter/material.dart';

import '../models/tone.dart';

/// Tokens de color del sistema visual (claro / oscuro).
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surfaceSunken,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.border,
    required this.borderStrong,
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.good,
    required this.goodSoft,
    required this.warn,
    required this.warnSoft,
    required this.crit,
    required this.critSoft,
    required this.critInk,
    required this.focus,
  });

  final Color bg, surface, surfaceSunken, ink, inkMuted, inkFaint, border, borderStrong;
  final Color accent, accentInk, accentSoft, good, goodSoft, warn, warnSoft, crit, critSoft, critInk, focus;

  static const light = AppColors(
    bg: Color(0xFFF6F3EE),
    surface: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEFE9E0),
    ink: Color(0xFF211C17),
    inkMuted: Color(0xFF75695C),
    inkFaint: Color(0xFFA89B8B),
    border: Color(0xFFE3DBCD),
    borderStrong: Color(0xFFCDC0AC),
    accent: Color(0xFFC85A28),
    accentInk: Color(0xFFFFF8F2),
    accentSoft: Color(0xFFF6E3D5),
    good: Color(0xFF2E7D4F),
    goodSoft: Color(0xFFE2F0E6),
    warn: Color(0xFFA9721B),
    warnSoft: Color(0xFFF6ECD8),
    crit: Color(0xFFB23A2B),
    critSoft: Color(0xFFF8E2DD),
    critInk: Color(0xFFFFF8F2),
    focus: Color(0xFF1C6FB0),
  );

  static const dark = AppColors(
    bg: Color(0xFF171310),
    surface: Color(0xFF211C17),
    surfaceSunken: Color(0xFF2A2420),
    ink: Color(0xFFF3EDE4),
    inkMuted: Color(0xFFB3A595),
    inkFaint: Color(0xFF7C7062),
    border: Color(0xFF3A332B),
    borderStrong: Color(0xFF4D443A),
    accent: Color(0xFFE07A45),
    accentInk: Color(0xFF1A1109),
    accentSoft: Color(0xFF3A2717),
    good: Color(0xFF6CC296),
    goodSoft: Color(0xFF1D3327),
    warn: Color(0xFFE0B355),
    warnSoft: Color(0xFF3A2F16),
    crit: Color(0xFFE88373),
    critSoft: Color(0xFF3D2019),
    critInk: Color(0xFF1A1109),
    focus: Color(0xFF6BB3E8),
  );

  Color fg(Tone t) => switch (t) {
        Tone.good => good,
        Tone.warn => warn,
        Tone.crit => crit,
        Tone.neutral => inkMuted,
        Tone.accent => accent,
      };

  Color soft(Tone t) => switch (t) {
        Tone.good => goodSoft,
        Tone.warn => warnSoft,
        Tone.crit => critSoft,
        Tone.neutral => surfaceSunken,
        Tone.accent => accentSoft,
      };

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return t < 0.5 ? this : other;
  }
}

/// Radios.
class R {
  static const card = 14.0;
  static const tile = 12.0;
  static const input = 8.0;
  static const badge = 6.0;
  static const pill = 20.0;
}

extension AppColorsX on BuildContext {
  AppColors get c => Theme.of(this).extension<AppColors>()!;
}

List<BoxShadow> cardShadow(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return [
    BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.25 : 0.06), blurRadius: 2, offset: const Offset(0, 1)),
    BoxShadow(
      color: Colors.black.withValues(alpha: dark ? 0.35 : 0.12),
      blurRadius: 18,
      spreadRadius: -10,
      offset: const Offset(0, 6),
    ),
  ];
}
