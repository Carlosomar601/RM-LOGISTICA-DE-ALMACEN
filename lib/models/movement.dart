import 'tone.dart';

class Movement {
  Movement({
    required this.id,
    required this.type,
    required this.productId,
    required this.qty,
    required this.doc,
    required this.user,
    required this.dateTime,
    required this.from,
    required this.to,
  });

  final String id; // "MV-1000+"
  final String type;
  final String productId;
  final int qty;
  final String doc;
  final String user;
  final DateTime dateTime;
  final String from;
  final String to;
}

class MovementType {
  const MovementType(this.key, this.tone, this.label);
  final String key;
  final Tone tone;
  final String label;
}

const kMovementTypes = <String, MovementType>{
  'entrada': MovementType('entrada', Tone.good, 'Entrada'),
  'piqueo': MovementType('piqueo', Tone.warn, 'Piqueo'),
  'transfer-bin': MovementType('transfer-bin', Tone.neutral, 'Transf. bin'),
  'transfer-store-out': MovementType('transfer-store-out', Tone.crit, 'Salida transf.'),
  'transfer-store-in': MovementType('transfer-store-in', Tone.good, 'Recepción transf.'),
  'discrepancia': MovementType('discrepancia', Tone.crit, 'Discrepancia'),
  'no-encontrado': MovementType('no-encontrado', Tone.crit, 'No encontrado'),
  'ajuste': MovementType('ajuste', Tone.neutral, 'Ajuste'),
};

/// Filtros del Historial (key null = todos).
const kHistoryFilters = <(String?, String)>[
  (null, 'Todos los movimientos'),
  ('entrada', 'Entradas de mercancía'),
  ('piqueo', 'Piqueos'),
  ('transfer-bin', 'Transferencias entre bins'),
  ('transfer-store-out', 'Salida por transferencia'),
  ('transfer-store-in', 'Recepción por transferencia'),
  ('discrepancia', 'Discrepancias en piqueo'),
  ('no-encontrado', 'No encontrado en almacén'),
  ('ajuste', 'Ajustes'),
];
