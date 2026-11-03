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

class Receipt {
  Receipt({required this.id, required this.supplier, required this.date, required this.items});

  final String id;
  final String supplier;
  final DateTime date;
  final List<ReceiptItem> items;

  bool get isPending => items.any((i) => i.pending > 0);

  Map<String, dynamic> toJson() => {
        'id': id,
        'supplier': supplier,
        'date': date.toIso8601String(),
        'items': [for (final i in items) i.toJson()],
      };

  factory Receipt.fromJson(Map j) => Receipt(
        id: jStr(j, 'id'),
        supplier: jStr(j, 'supplier'),
        date: jDate(j, 'date'),
        items: [for (final i in jList(j, 'items')) ReceiptItem.fromJson(i)],
      );
}
