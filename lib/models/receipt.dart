class ReceiptItem {
  ReceiptItem({required this.productId, required this.qtyReceived, this.qtyAllocated = 0});

  final String productId;
  final int qtyReceived;
  int qtyAllocated;

  int get pending => qtyReceived - qtyAllocated;
}

class Receipt {
  Receipt({required this.id, required this.supplier, required this.date, required this.items});

  final String id;
  final String supplier;
  final DateTime date;
  final List<ReceiptItem> items;

  bool get isPending => items.any((i) => i.pending > 0);
}
