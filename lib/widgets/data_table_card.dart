import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Columna de tabla: ancho mínimo + factor flex para repartir espacio extra.
class TCol {
  const TCol(this.label, {this.width = 110, this.flex = 1, this.numeric = false});
  final String label;
  final double width;
  final double flex;
  final bool numeric;
}

class TRow {
  const TRow(this.cells, {this.onTap, this.expanded, this.opacity = 1, this.background, this.selected = false});
  final List<Widget> cells;
  final VoidCallback? onTap;
  final Widget? expanded;
  final double opacity;
  final Color? background;
  final bool selected;
}

/// Tabla liviana con desplazamiento horizontal cuando el ancho no alcanza.
class AppTable extends StatelessWidget {
  const AppTable({
    super.key,
    required this.columns,
    required this.rows,
    this.emptyText,
    this.cellPadding = const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    this.headerBackground,
  });

  final List<TCol> columns;
  final List<TRow> rows;
  final String? emptyText;
  final EdgeInsets cellPadding;
  final Color? headerBackground;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(builder: (context, box) {
      final avail = box.maxWidth.isFinite ? box.maxWidth : 900.0;
      final minW = columns.fold<double>(0, (a, col) => a + col.width);
      final totalW = avail > minW ? avail : minW;
      final extra = totalW - minW;
      final flexSum = columns.fold<double>(0, (a, col) => a + col.flex);
      final widths = [
        for (final col in columns) col.width + (flexSum == 0 ? 0 : extra * col.flex / flexSum),
      ];

      Widget cell(int i, Widget child) => Container(
            width: widths[i],
            padding: cellPadding,
            alignment: columns[i].numeric ? Alignment.centerRight : Alignment.centerLeft,
            child: child,
          );

      final header = Container(
        decoration: BoxDecoration(
          color: headerBackground,
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        child: Row(
          children: [
            for (var i = 0; i < columns.length; i++)
              cell(
                i,
                Text(
                  columns[i].label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.th(context),
                ),
              ),
          ],
        ),
      );

      final body = <Widget>[];
      for (var r = 0; r < rows.length; r++) {
        final row = rows[r];
        final last = r == rows.length - 1;
        Widget line = Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < columns.length; i++)
              cell(i, i < row.cells.length ? row.cells[i] : const SizedBox.shrink()),
          ],
        );
        if (row.opacity < 1) line = Opacity(opacity: row.opacity, child: line);
        if (row.onTap != null) {
          line = Material(
            type: MaterialType.transparency,
            child: InkWell(onTap: row.onTap, child: line),
          );
        }
        body.add(Container(
          decoration: BoxDecoration(
            color: row.background ?? (row.selected ? c.accentSoft.withValues(alpha: 0.45) : null),
            border: last && row.expanded == null ? null : Border(bottom: BorderSide(color: c.border)),
          ),
          child: line,
        ));
        if (row.expanded != null) {
          body.add(Container(
            width: totalW,
            decoration: BoxDecoration(
              color: c.surfaceSunken.withValues(alpha: 0.55),
              border: last ? null : Border(bottom: BorderSide(color: c.border)),
            ),
            child: row.expanded,
          ));
        }
      }

      if (rows.isEmpty && emptyText != null) {
        body.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
          child: Text(emptyText!, style: T.muted(context, size: 13)),
        ));
      }

      final content = DefaultTextStyle(
        style: T.body(context, size: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [header, ...body],
        ),
      );

      if (minW <= avail) return content;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: totalW, child: content),
      );
    });
  }
}

/// Celda de texto común.
Widget tText(BuildContext context, String s, {bool muted = false, int maxLines = 2, FontWeight? weight}) => Text(
      s,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: muted
          ? T.muted(context, size: 12.5)
          : T.body(context, size: 13, weight: weight ?? FontWeight.w400),
    );

/// Celda mono (SKUs, cantidades, documentos).
Widget tMono(BuildContext context, String s,
        {bool muted = false, FontWeight weight = FontWeight.w500, Color? color}) =>
    Text(
      s,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.fade,
      style: T.mono(context, size: 12.5, weight: weight, color: color ?? (muted ? context.c.inkMuted : null)),
    );
