import 'json_util.dart';

class OrderItem {
  OrderItem({required this.productId, required this.qty, this.delivered = 0});

  final String productId;

  /// Mutable: una orden de RM aún sin piquear se actualiza si cambia en RM.
  int qty;

  /// Unidades ya despachadas en piqueos anteriores (órdenes parciales).
  int delivered;

  int get remaining => (qty - delivered).clamp(0, qty);

  Map<String, dynamic> toJson() => {'productId': productId, 'qty': qty, 'delivered': delivered};

  factory OrderItem.fromJson(Map j) =>
      OrderItem(productId: jStr(j, 'productId'), qty: jInt(j, 'qty'), delivered: jInt(j, 'delivered'));
}

/// Origen de la orden.
abstract final class OrderSource {
  static const demo = 'demo';
  static const rmOrder = 'rm-order';
  static const rmInvoice = 'rm-invoice';
}

class Order {
  Order({
    required this.id,
    required this.customer,
    required this.store,
    required this.date,
    required this.status,
    required this.items,
    this.source = OrderSource.demo,
    this.rmStore,
    this.rmNumber,
    this.syncNote,
    List<String>? invoices,
  }) : invoices = invoices ?? [];

  final String id;
  final String customer;

  final String store;
  final DateTime date;

  /// pendiente | parcial | completada
  String status;
  final List<OrderItem> items;

  /// demo | rm-order | rm-invoice
  final String source;

  /// Tienda (id) y número de orden/factura en RM.
  final String? rmStore;
  final String? rmNumber;

  /// Aviso de sincronización (p. ej. "Cambió en RM", "Facturada en RM · FAC 123").
  String? syncNote;

  /// Facturas de RM enlazadas a esta orden.
  final List<String> invoices;

  bool get isOpen => status != 'completada';
  bool get isRm => source != OrderSource.demo;

  Map<String, dynamic> toJson() => {
        'id': id,
        'customer': customer,
        'store': store,
        'date': date.toIso8601String(),
        'status': status,
        'items': [for (final i in items) i.toJson()],
        'source': source,
        if (rmStore != null) 'rmStore': rmStore,
        if (rmNumber != null) 'rmNumber': rmNumber,
        if (syncNote != null) 'syncNote': syncNote,
        'invoices': invoices,
      };

  factory Order.fromJson(Map j) => Order(
        id: jStr(j, 'id'),
        customer: jStr(j, 'customer'),
        store: jStr(j, 'store'),
        date: jDate(j, 'date'),
        status: jStr(j, 'status'),
        items: [for (final i in jList(j, 'items')) OrderItem.fromJson(i)],
        source: jStrOrNull(j, 'source') ?? OrderSource.demo,
        rmStore: jStrOrNull(j, 'rmStore'),
        rmNumber: jStrOrNull(j, 'rmNumber'),
        syncNote: jStrOrNull(j, 'syncNote'),
        invoices: jStrings(j, 'invoices'),
      );
}
