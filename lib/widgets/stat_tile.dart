import 'package:flutter/material.dart';

import '../models/tone.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.hint, this.tone});

  final String label;
  final String value;
  final String? hint;

  /// Si se indica, el valor se pinta en ese color.
  final Tone? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(R.tile),
        boxShadow: cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.th(context),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.mono(context, size: 26, weight: FontWeight.w600, color: tone == null ? c.ink : c.fg(tone!)),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.muted(context, size: 11.5)),
          ],
        ],
      ),
    );
  }
}

/// Fila de tiles responsiva: reparte en 5/3/2 columnas según el ancho.
class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.tiles, this.maxColumns = 5});

  final List<Widget> tiles;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      var cols = w >= 1000 ? maxColumns : (w >= 640 ? 3 : 2);
      if (cols > tiles.length) cols = tiles.length;
      const gap = 12.0;
      final tileW = (w - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final t in tiles) SizedBox(width: tileW.floorToDouble(), child: t)],
      );
    });
  }
}
