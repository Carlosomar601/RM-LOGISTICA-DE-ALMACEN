/// Un registro de inventario: un producto en una localización (bin) de una tienda.
class InvRow {
  InvRow({
    required this.id,
    required this.productId,
    required this.store,
    required this.bin,
    required this.qty,
    required this.entryDate,
    required this.receipt,
    required this.lot,
    required this.user,
  });

  final String id;
  final String productId;
  String store;
  String bin;
  int qty;
  DateTime entryDate;
  String receipt;
  String lot;
  String user;

  InvRow copy() => InvRow(
        id: id,
        productId: productId,
        store: store,
        bin: bin,
        qty: qty,
        entryDate: entryDate,
        receipt: receipt,
        lot: lot,
        user: user,
      );
}
