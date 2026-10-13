import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Chip mono 12px para localizaciones (bins).
class BinTag extends StatelessWidget {
  const BinTag(this.bin, {super.key, this.struck = false});

  final String bin;
  final bool struck;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        border: Border.all(color: c.borderStrong),
        borderRadius: BorderRadius.circular(R.badge),
      ),
      child: Text(
        bin,
        maxLines: 1,
        softWrap: false,
        style: T.mono(
          context,
          size: 12,
          weight: FontWeight.w600,
          decoration: struck ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}
