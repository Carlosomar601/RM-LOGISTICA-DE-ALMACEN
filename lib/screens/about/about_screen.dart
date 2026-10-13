import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';

const _tiles = <(String, String)>[
  ('Inventario por bin', 'Un producto puede vivir en varios bins y cada bin puede contener varios productos; el total es la suma de todas sus localizaciones.'),
  ('Piqueo FIFO', 'El sistema indica qué recoger, de qué bin y cuánto, empezando siempre por el recibo más antiguo y continuando con el siguiente.'),
  ('Localizaciones automáticas', 'Cuando un bin llega a 0 deja de mostrarse en búsquedas, piqueo e inventario; vuelve a aparecer al recibir mercancía.'),
  ('Transferencias', 'Movimientos entre bins con cantidades parciales y entre sucursales con confirmación de recepción en la tienda destino.'),
  ('Historial completo', 'Entradas, piqueos, transferencias, recepciones, ajustes y discrepancias con documento, usuario, fecha y hora.'),
  ('Dashboard de inventario', 'Distribución por producto y bin con antigüedad, prioridad FIFO e inventario estancado de más de 6 meses.'),
  ('Usuarios y permisos', 'Acceso por rol a cada sección, con vista previa para ver el sistema como lo vería cada usuario.'),
];

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScreenHeader(
          eyebrow: 'Centeno Tire · Retail Manager',
          title: 'Resumen del proyecto',
          subtitle:
              'Módulo de logística de almacén y piqueo de órdenes: inventario por localización, rotación FIFO y control completo de transferencias.',
        ),
        LayoutBuilder(builder: (context, box) {
          final cols = box.maxWidth >= 1000 ? 3 : (box.maxWidth >= 600 ? 2 : 1);
          const gap = 14.0;
          final w = ((box.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < _tiles.length; i++)
                SizedBox(
                  width: w,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 150),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: c.surface,
                      border: Border.all(color: c.border),
                      borderRadius: BorderRadius.circular(R.card),
                      boxShadow: cardShadow(context),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((i + 1).toString().padLeft(2, '0'),
                            style: T.mono(context, size: 22, weight: FontWeight.w600, color: c.accent)),
                        const SizedBox(height: 8),
                        Text(_tiles[i].$1.toUpperCase(), style: T.h(context, 19, weight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(_tiles[i].$2, style: T.muted(context, size: 13)),
                      ],
                    ),
                  ),
                ),
            ],
          );
        }),
        const SizedBox(height: 22),
        const NoteBox(
          'Esta pantalla es un prototipo interactivo con datos de ejemplo de Centeno Tire. Todo el estado vive en memoria: '
          'los recibos, órdenes, piqueos y transferencias que realices se reinician al recargar la aplicación.',
        ),
      ],
    );
  }
}
