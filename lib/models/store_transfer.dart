class StoreTransfer {
  StoreTransfer({
    required this.id,
    required this.productId,
    required this.qty,
    required this.fromStore,
    required this.toStore,
    required this.sentAt,
    this.status = 'pendiente',
    this.receivedAt,
  });

  final String id;
  final String productId;
  final int qty;
  final String fromStore;
  final String toStore;
  final DateTime sentAt;

  /// pendiente | recibido
  String status;
  DateTime? receivedAt;
}

class BinTransfer {
  BinTransfer({
    required this.id,
    required this.productId,
    required this.qty,
    required this.from,
    required this.to,
    required this.user,
    required this.dateTime,
    required this.obs,
  });

  final String id;
  final String productId;
  final int qty;
  final String from;
  final String to;
  final String user;
  final DateTime dateTime;
  final String obs;
}
