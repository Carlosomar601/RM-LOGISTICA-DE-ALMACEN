class OrderItem {
  OrderItem({required this.productId, required this.qty, this.delivered = 0});

  final String productId;
  final int qty;

  /// Unidades ya despachadas en piqueos anteriores (órdenes parciales).
  int delivered;

  int get remaining => (qty - delivered).clamp(0, qty);
}

class Order {
  Order({
    required this.id,
    required this.customer,
    required this.store,
    required this.date,
    required this.status,
    required this.items,
  });

  final String id;
  final String customer;
  final String store;
  final DateTime date;

  /// pendiente | parcial | completada
  String status;
  final List<OrderItem> items;

  bool get isOpen => status != 'completada';
}
