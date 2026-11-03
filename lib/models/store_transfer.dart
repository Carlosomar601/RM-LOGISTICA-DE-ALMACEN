import 'json_util.dart';

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'qty': qty,
        'fromStore': fromStore,
        'toStore': toStore,
        'sentAt': sentAt.toIso8601String(),
        'status': status,
        if (receivedAt != null) 'receivedAt': receivedAt!.toIso8601String(),
      };

  factory StoreTransfer.fromJson(Map j) => StoreTransfer(
        id: jStr(j, 'id'),
        productId: jStr(j, 'productId'),
        qty: jInt(j, 'qty'),
        fromStore: jStr(j, 'fromStore'),
        toStore: jStr(j, 'toStore'),
        sentAt: jDate(j, 'sentAt'),
        status: jStr(j, 'status'),
        receivedAt: jDateOrNull(j, 'receivedAt'),
      );
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'qty': qty,
        'from': from,
        'to': to,
        'user': user,
        'dateTime': dateTime.toIso8601String(),
        'obs': obs,
      };

  factory BinTransfer.fromJson(Map j) => BinTransfer(
        id: jStr(j, 'id'),
        productId: jStr(j, 'productId'),
        qty: jInt(j, 'qty'),
        from: jStr(j, 'from'),
        to: jStr(j, 'to'),
        user: jStr(j, 'user'),
        dateTime: jDate(j, 'dateTime'),
        obs: jStr(j, 'obs'),
      );
}
