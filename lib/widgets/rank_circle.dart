import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Círculo de prioridad FIFO (20px). El rango 1 va en color sólido.
class RankCircle extends StatelessWidget {
  const RankCircle(this.rank, {super.key});
  final int rank;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final first = rank == 1;
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: first ? c.accent : c.accentSoft,
      ),
      child: Text(
        '$rank',
        style: T.mono(context, size: 10.5, weight: FontWeight.w600, color: first ? c.accentInk : c.accent),
      ),
    );
  }
}
