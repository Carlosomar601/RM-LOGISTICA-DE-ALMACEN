import 'package:flutter/material.dart';

import 'tokens.dart';

const kDisplayFont = 'Barlow Condensed';
const kBodyFont = 'IBM Plex Sans';
const kMonoFont = 'IBM Plex Mono';

const _tabular = [FontFeature.tabularFigures()];

/// Estilos tipográficos del sistema.
class T {
  static TextStyle display(BuildContext context, {double size = 32, Color? color}) => TextStyle(
        fontFamily: kDisplayFont,
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: 1.05,
        letterSpacing: 0.3,
        color: color ?? context.c.ink,
      );

  static TextStyle h(BuildContext context, double size, {FontWeight weight = FontWeight.w600, Color? color}) =>
      TextStyle(
        fontFamily: kDisplayFont,
        fontSize: size,
        fontWeight: weight,
        height: 1.1,
        letterSpacing: 0.4,
        color: color ?? context.c.ink,
      );

  static TextStyle body(BuildContext context,
          {double size = 13.5, FontWeight weight = FontWeight.w400, Color? color, double? height}) =>
      TextStyle(
        fontFamily: kBodyFont,
        fontSize: size,
        fontWeight: weight,
        height: height ?? 1.4,
        color: color ?? context.c.ink,
      );

  static TextStyle muted(BuildContext context, {double size = 12.5, FontWeight weight = FontWeight.w400}) =>
      body(context, size: size, weight: weight, color: context.c.inkMuted);

  static TextStyle mono(BuildContext context,
          {double size = 12.5, FontWeight weight = FontWeight.w500, Color? color, TextDecoration? decoration}) =>
      TextStyle(
        fontFamily: kMonoFont,
        fontSize: size,
        fontWeight: weight,
        height: 1.3,
        color: color ?? context.c.ink,
        fontFeatures: _tabular,
        decoration: decoration,
        decorationColor: color ?? context.c.ink,
      );

  /// Encabezado de tabla: 10.5px, mayúsculas, tracking 0.04em, inkMuted.
  static TextStyle th(BuildContext context) => TextStyle(
        fontFamily: kBodyFont,
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.42,
        color: context.c.inkMuted,
      );
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.accentInk,
    secondary: c.accent,
    onSecondary: c.accentInk,
    error: c.crit,
    onError: c.critInk,
    surface: c.surface,
    onSurface: c.ink,
    outline: c.borderStrong,
    outlineVariant: c.border,
    surfaceContainerHighest: c.surfaceSunken,
  );

  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(R.input),
    borderSide: BorderSide(color: c.borderStrong),
  );

  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.input));
  const buttonText = TextStyle(fontFamily: kBodyFont, fontSize: 13, fontWeight: FontWeight.w600);
  const buttonPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: kBodyFont,
  );

  return base.copyWith(
    extensions: [c],
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.surface,
    cardColor: c.surface,
    dividerColor: c.border,
    focusColor: c.focus.withValues(alpha: 0.18),
    hoverColor: c.ink.withValues(alpha: 0.04),
    splashColor: c.accent.withValues(alpha: 0.08),
    highlightColor: c.accent.withValues(alpha: 0.05),
    textTheme: base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink, fontFamily: kBodyFont),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: inputBorder,
      enabledBorder: inputBorder,
      disabledBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.border)),
      focusedBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.focus, width: 2)),
      errorBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.crit)),
      focusedErrorBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.crit, width: 2)),
      hintStyle: TextStyle(color: c.inkFaint, fontSize: 13.5),
      labelStyle: TextStyle(color: c.inkMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(buttonShape),
        padding: const WidgetStatePropertyAll(buttonPadding),
        textStyle: const WidgetStatePropertyAll(buttonText),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.surfaceSunken : c.accent),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.inkFaint : c.accentInk),
        side: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? BorderSide(color: c.border) : BorderSide.none),
        overlayColor: WidgetStatePropertyAll(c.accentInk.withValues(alpha: 0.10)),
        mouseCursor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.disabled) ? SystemMouseCursors.forbidden : SystemMouseCursors.click),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(buttonShape),
        padding: const WidgetStatePropertyAll(buttonPadding),
        textStyle: const WidgetStatePropertyAll(buttonText),
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.surfaceSunken : c.surface),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.inkFaint : c.ink),
        side: WidgetStateProperty.resolveWith(
            (s) => BorderSide(color: s.contains(WidgetState.disabled) ? c.border : c.borderStrong)),
        overlayColor: WidgetStatePropertyAll(c.ink.withValues(alpha: 0.05)),
        mouseCursor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.disabled) ? SystemMouseCursors.forbidden : SystemMouseCursors.click),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(buttonShape),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        textStyle: const WidgetStatePropertyAll(buttonText),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? c.inkFaint : c.accent),
        overlayColor: WidgetStatePropertyAll(c.accent.withValues(alpha: 0.08)),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : null),
      checkColor: WidgetStatePropertyAll(c.accentInk),
      side: BorderSide(color: c.borderStrong, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: c.accent,
      unselectedLabelColor: c.inkMuted,
      indicatorColor: c.accent,
      dividerColor: c.border,
      labelStyle: const TextStyle(fontFamily: kBodyFont, fontSize: 13.5, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontFamily: kBodyFont, fontSize: 13.5, fontWeight: FontWeight.w500),
      tabAlignment: TabAlignment.start,
      indicatorSize: TabBarIndicatorSize.label,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(6)),
      textStyle: TextStyle(color: c.bg, fontSize: 12),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(c.borderStrong),
      radius: const Radius.circular(8),
    ),
    popupMenuTheme: PopupMenuThemeData(color: c.surface),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.focus,
      selectionColor: c.focus.withValues(alpha: 0.25),
    ),
  );
}
