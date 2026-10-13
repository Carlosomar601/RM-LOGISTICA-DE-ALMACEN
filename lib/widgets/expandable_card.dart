import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Tarjeta expandible controlada (el padre decide si está abierta).
class ExpandableCard extends StatelessWidget {
  const ExpandableCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.monoTitle = true,
    this.monoSubtitle = false,
    this.extra,
  });

  final bool monoSubtitle;

  /// Contenido adicional bajo el subtítulo (p. ej. chips de acceso).
  final Widget? extra;

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;
  final bool monoTitle;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: expanded ? c.borderStrong : c.border),
        borderRadius: BorderRadius.circular(R.card),
        boxShadow: cardShadow(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                child: Row(
                  children: [
                    if (leading != null) ...[leading!, const SizedBox(width: 12)],
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: monoTitle
                                ? T.mono(context, size: 14, weight: FontWeight.w600)
                                : T.body(context, size: 14.5, weight: FontWeight.w600),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              subtitle!,
                              style: monoSubtitle
                                  ? T.mono(context, size: 12, weight: FontWeight.w400, color: c.inkMuted)
                                  : T.muted(context, size: 12.5),
                            ),
                          ],
                          if (extra != null) ...[const SizedBox(height: 8), extra!],
                        ],
                      ),
                    ),
                    if (trailing != null) ...[const SizedBox(width: 10), Flexible(flex: 2, child: Align(alignment: Alignment.centerRight, child: trailing!))],
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(Icons.expand_more, color: c.inkMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Container(
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    child: child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
