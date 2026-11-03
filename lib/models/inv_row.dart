import 'json_util.dart';

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'store': store,
        'bin': bin,
        'qty': qty,
        'entryDate': entryDate.toIso8601String(),
        'receipt': receipt,
        'lot': lot,
        'user': user,
      };

  factory InvRow.fromJson(Map j) => InvRow(
        id: jStr(j, 'id'),
        productId: jStr(j, 'productId'),
        store: jStr(j, 'store'),
        bin: jStr(j, 'bin'),
        qty: jInt(j, 'qty'),
        entryDate: jDate(j, 'entryDate'),
        receipt: jStr(j, 'receipt'),
        lot: jStr(j, 'lot'),
        user: jStr(j, 'user'),
      );
}
