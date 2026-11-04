import 'json_util.dart';

class ReceiptItem {
  ReceiptItem({required this.productId, required this.qtyReceived, this.qtyAllocated = 0});

  final String productId;
  int qtyReceived;
  int qtyAllocated;

  int get pending => qtyReceived - qtyAllocated;

  Map<String, dynamic> toJson() => {'productId': productId, 'qtyReceived': qtyReceived, 'qtyAllocated': qtyAllocated};

  factory ReceiptItem.fromJson(Map j) => ReceiptItem(
      productId: jStr(j, 'productId'), qtyReceived: jInt(j, 'qtyReceived'), qtyAllocated: jInt(j, 'qtyAllocated'));
}

/// Tipo de recibo: mercancía de suplidor (por defecto) o devolución aceptada en la revisión.
abstract final class ReceiptKind {
  static const recibo = 'recibo';
  static const devolucion = 'devolucion';
}

class Receipt {
  Receipt({
    required this.id,
    required this.supplier,
    required this.date,
    required this.items,
    this.kind = ReceiptKind.recibo,
    this.refDoc,
  });

  final String id;
  final String supplier;

  /// Fecha de entrada: la fila de inventario que se crea al ubicar la toma (FIFO).
  final DateTime date;
  final List<ReceiptItem> items;

  /// [ReceiptKind.recibo] o [ReceiptKind.devolucion].
  final String kind;

  /// Devolución: factura original de la venta (null si RM no la indica).
  final String? refDoc;

  bool get isPending => items.any((i) => i.pending > 0);

  bool get isReturn => kind == ReceiptKind.devolucion;

  Map<String, dynamic> toJson() => {
        'id': id,
        'supplier': supplier,
        'date': date.toIso8601String(),
        'items': [for (final i in items) i.toJson()],
        if (kind != ReceiptKind.recibo) 'kind': kind,
        if (refDoc != null) 'refDoc': refDoc,
      };

  factory Receipt.fromJson(Map j) => Receipt(
        id: jStr(j, 'id'),
        supplier: jStr(j, 'supplier'),
        date: jDate(j, 'date'),
        items: [for (final i in jList(j, 'items')) ReceiptItem.fromJson(i)],
        kind: jStrOrNull(j, 'kind') ?? ReceiptKind.recibo,
        refDoc: jStrOrNull(j, 'refDoc'),
      );
}
