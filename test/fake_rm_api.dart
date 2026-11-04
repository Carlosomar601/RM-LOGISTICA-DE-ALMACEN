import 'package:rm_core/api/rm_api.dart';

RmReceiptLine line(
  String id, {
  String receipt = '5001',
  String code = 'MI-20565R15',
  String desc = 'Michelin Primacy 4 · 205/65R15',
  double qty = 10,
  String supplier = 'Michelin PR Distribuidora',
  DateTime? date,
}) =>
    RmReceiptLine(
      lineId: id,
      receiptNumber: receipt,
      orderNumber: '2648',
      receiptDate: date ?? DateTime(2026, 10, 12, 9, 30),
      supplier: '17160',
      supplierName: supplier,
      itemCode: code,
      description: desc,
      quantityReceived: qty,
      unit: 'UN',
      invoiceNumber: 'INV-1',
      userId: '2',
      cost: 1,
    );

RmOrderLine oline(
  String order,
  String code,
  double pending, {
  String id = '',
  String customer = 'Ferretería Cliente',
  bool service = false,
  bool fuel = false,
  int? category,
  String categoryName = '',
  int? priceLevel,
  String priceLevelName = '',
}) =>
    RmOrderLine(
      orderNumber: order,
      orderDate: DateTime(2026, 10, 13, 10),
      customer: 'C1',
      customerName: customer,
      lineId: id.isEmpty ? '$order-$code' : id,
      itemCode: code,
      description: 'Desc $code',
      quantityOrdered: pending,
      pending: pending,
      isService: service,
      isFuel: fuel,
      categoryId: category,
      categoryName: categoryName,
      priceLevelId: priceLevel,
      priceLevelName: priceLevelName,
    );

RmInvoiceLine iline(
  String invoice,
  String code,
  double qty, {
  String order = '',
  int transaction = 50,
  String customer = 'Ferretería Cliente',
  double voided = 0,
  int? category,
  String categoryName = '',
  int? priceLevel,
  String priceLevelName = '',
  String lineId = '',
  DateTime? date,
  String original = '',
  DateTime? originalDate,
  bool service = false,
}) =>
    RmInvoiceLine(
      voidedQuantity: voided,
      invoiceNumber: invoice,
      invoiceDate: date ?? DateTime(2026, 10, 13, 15),
      customer: 'C1',
      customerName: customer,
      orderNumber: order,
      lineId: lineId.isEmpty ? '$invoice-$code' : lineId,
      originalInvoice: original,
      originalInvoiceDate: originalDate,
      isService: service,
      itemCode: code,
      description: 'Desc $code',
      quantity: qty,
      transaction: transaction,
      categoryId: category,
      categoryName: categoryName,
      priceLevelId: priceLevel,
      priceLevelName: priceLevelName,
    );

RmReturnLine rline(
  String doc,
  String code,
  double qty, {
  int type = 70,
  String lineId = '',
  DateTime? date,
  String original = '',
  DateTime? originalDate,
  bool service = false,
  bool fuel = false,
}) =>
    RmReturnLine(
      returnNumber: doc,
      returnType: type,
      returnDate: date ?? DateTime(2026, 10, 20, 11),
      lineId: lineId.isEmpty ? '$doc-$code' : lineId,
      itemCode: code,
      description: 'Desc $code',
      quantity: qty,
      originalInvoice: original,
      originalInvoiceDate: originalDate,
      customer: 'C1',
      customerName: 'Ferretería Cliente',
      isService: service,
      isFuel: fuel,
    );

/// API falsa para pruebas: `health == null` significa conexión correcta.
/// Las listas son mutables para simular cambios en RM entre sincronizaciones.
class FakeRmApi implements RmApi {
  FakeRmApi({
    this.health,
    this.lines = const [],
    this.error,
    List<RmOrderLine>? orders,
    List<RmInvoiceLine>? invoices,
    this.ordersError,
    this.invoicesError,
    this.returns,
    this.delay = Duration.zero,
  })  : orders = orders ?? [],
        invoices = invoices ?? [];
  final String? health;
  List<RmReceiptLine> lines;
  final String? error;
  List<RmOrderLine> orders;
  List<RmInvoiceLine> invoices;
  RmApiException? ordersError;
  RmApiException? invoicesError;

  /// null = la API aún no tiene `SalesReturnsByDate` (se usa la fuente provisional).
  List<RmReturnLine>? returns;
  final Duration delay;
  int calls = 0;
  DateTime? lastFrom;
  DateTime? lastInvoicesFrom;
  DateTime? lastReturnsFrom;

  @override
  Future<String> healthCheck() async {
    if (health != null) throw RmApiException(health!);
    return 'Conexión OK.';
  }

  @override
  Future<List<RmReceiptLine>> receiptsByDate(DateTime from, DateTime to, {String? supplier}) async {
    calls++;
    lastFrom = from;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (error != null) throw RmApiException(error!);
    return lines;
  }

  @override
  Future<List<RmOrderLine>> openOrders() async {
    if (ordersError != null) throw ordersError!;
    return orders;
  }

  @override
  Future<List<RmInvoiceLine>> invoicesByDate(DateTime from, DateTime to) async {
    lastInvoicesFrom = from;
    if (invoicesError != null) throw invoicesError!;
    return invoices;
  }

  @override
  Future<List<RmReturnLine>> returnsByDate(DateTime from, DateTime to) async {
    lastReturnsFrom = from;
    final r = returns;
    if (r == null) throw RmApiException('SalesReturnsByDate no existe todavía en esta API.', notAvailable: true);
    return r;
  }
}
