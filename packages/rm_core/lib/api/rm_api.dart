import 'dart:async';
import 'dart:convert';

import 'package:riverpod/riverpod.dart';
import 'package:http/http.dart' as http;

/// Error de comunicación o error lógico devuelto por la API de RM.
class RmApiException implements Exception {
  RmApiException(this.message, {this.notAvailable = false});
  final String message;

  /// El endpoint aún no existe en esa API (HTTP 404 sin cuerpo).
  final bool notAvailable;

  @override
  String toString() => message;
}

/// Una línea del log de recibos (`RecReceiptsByDate`).
class RmReceiptLine {
  RmReceiptLine({
    required this.lineId,
    required this.receiptNumber,
    required this.orderNumber,
    required this.receiptDate,
    required this.supplier,
    required this.supplierName,
    required this.itemCode,
    required this.description,
    required this.quantityReceived,
    required this.unit,
    required this.invoiceNumber,
    required this.userId,
    required this.cost,
  });

  final String lineId;
  final String receiptNumber;
  final String orderNumber;
  final DateTime receiptDate;
  final String supplier;
  final String supplierName;
  final String itemCode;
  final String description;
  final double quantityReceived;
  final String unit;
  final String invoiceNumber;
  final String userId;
  final double cost;

  factory RmReceiptLine.fromJson(Map<String, dynamic> j) {
    String str(String k) => (j[k] ?? '').toString().trim();
    double num_(String k) => j[k] is num ? (j[k] as num).toDouble() : double.tryParse(str(k)) ?? 0;
    final date = DateTime.tryParse(str('ReceiptDate').replaceFirst(' ', 'T'));
    if (date == null) throw RmApiException('Fecha de recibo inválida: «${str('ReceiptDate')}»');
    final supplier = str('Supplier');
    return RmReceiptLine(
      lineId: str('LineID'),
      receiptNumber: str('ReceiptNumber'),
      orderNumber: str('OrderNumber'),
      receiptDate: date,
      supplier: supplier,
      supplierName: str('SupplierName').isEmpty ? supplier : str('SupplierName'),
      itemCode: str('ItemCode'),
      description: str('Description'),
      quantityReceived: num_('QuantityReceived'),
      unit: str('Unit'),
      invoiceNumber: str('InvoiceNumber'),
      userId: str('UserID'),
      cost: num_('Cost'),
    );
  }

  /// Mismo formato que la API de RM, para que [RmReceiptLine.fromJson] lo lea de vuelta
  /// (el servidor de la app reenvía las líneas a los clientes).
  Map<String, dynamic> toJson() => {
        'LineID': lineId,
        'ReceiptNumber': receiptNumber,
        'OrderNumber': orderNumber,
        'ReceiptDate': receiptDate.toIso8601String(),
        'Supplier': supplier,
        'SupplierName': supplierName,
        'ItemCode': itemCode,
        'Description': description,
        'QuantityReceived': quantityReceived,
        'Unit': unit,
        'InvoiceNumber': invoiceNumber,
        'UserID': userId,
        'Cost': cost,
      };
}

String _str(Map<String, dynamic> j, String k) => (j[k] ?? '').toString().trim();
double _num(Map<String, dynamic> j, String k) =>
    j[k] is num ? (j[k] as num).toDouble() : double.tryParse(_str(j, k)) ?? 0;
bool _bool(Map<String, dynamic> j, String k) {
  final v = j[k];
  if (v is bool) return v;
  if (v is num) return v != 0;
  return const {'true', '1', 'yes', 'si', 'sí'}.contains(_str(j, k).toLowerCase());
}

int? _intOrNull(Map<String, dynamic> j, String k) {
  final v = j[k];
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

DateTime _date(Map<String, dynamic> j, String k) {
  final d = DateTime.tryParse(_str(j, k).replaceFirst(' ', 'T'));
  if (d == null) throw RmApiException('Fecha inválida en $k: «${_str(j, k)}»');
  return d;
}

DateTime? _dateOrNull(Map<String, dynamic> j, String k) {
  final s = _str(j, k);
  return s.isEmpty ? null : DateTime.tryParse(s.replaceFirst(' ', 'T'));
}

/// Una línea de una orden abierta (`OrdOpenOrders`, solicitado al equipo de la API).
class RmOrderLine {
  RmOrderLine({
    required this.orderNumber,
    required this.orderDate,
    required this.customer,
    required this.customerName,
    required this.lineId,
    required this.itemCode,
    required this.description,
    required this.quantityOrdered,
    required this.pending,
    this.unit = '',
    this.isService = false,
    this.isFuel = false,
    this.categoryId,
    this.categoryName = '',
    this.priceLevelId,
    this.priceLevelName = '',
  });

  final String orderNumber;
  final DateTime orderDate;
  final String customer;
  final String customerName;
  final String lineId;
  final String itemCode;
  final String description;
  final double quantityOrdered;
  final double pending;
  final String unit;
  final bool isService;
  final bool isFuel;

  /// Categoría vigente del cliente (`Clientes.Categoria`; null = sin categoría) y su descripción
  /// (`CategoriasClientes.Descripcion`). La API las lee en vivo con un JOIN de solo lectura.
  final int? categoryId;
  final String categoryName;

  /// Nivel de precio vigente del cliente (`Clientes.PriceLevel`, null si es 0) y su nombre
  /// (`PriceLevels.Nombre`). RM API 1.14.0+.
  final int? priceLevelId;
  final String priceLevelName;

  factory RmOrderLine.fromJson(Map<String, dynamic> j) => RmOrderLine(
        orderNumber: _str(j, 'OrderNumber'),
        orderDate: _date(j, 'OrderDate'),
        customer: _str(j, 'Cliente'),
        customerName: _str(j, 'ClienteNombre').isEmpty ? _str(j, 'Cliente') : _str(j, 'ClienteNombre'),
        lineId: _str(j, 'LineID'),
        itemCode: _str(j, 'ItemCode'),
        description: _str(j, 'Description'),
        quantityOrdered: _num(j, 'QuantityOrdered'),
        pending: _num(j, 'Pending'),
        unit: _str(j, 'Unit'),
        isService: _bool(j, 'IsService'),
        isFuel: _bool(j, 'IsFuel') || _str(j, 'ItemCode').toLowerCase() == 'gasolina',
        categoryId: _intOrNull(j, 'ClienteCategoriaID'),
        categoryName: _str(j, 'ClienteCategoria'),
        priceLevelId: _intOrNull(j, 'ClientePriceLevelID'),
        priceLevelName: _str(j, 'ClientePriceLevel'),
      );
}

/// Una línea de factura de venta (`SalesInvoicesByDate`, solicitado al equipo de la API).
class RmInvoiceLine {
  RmInvoiceLine({
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.customer,
    required this.customerName,
    required this.orderNumber,
    required this.lineId,
    required this.itemCode,
    required this.description,
    required this.quantity,
    this.voidedQuantity = 0,
    this.unit = '',
    this.transaction = 50,
    this.isService = false,
    this.originalInvoice = '',
    this.originalInvoiceDate,
    this.returnReason = '',
    this.categoryId,
    this.categoryName = '',
    this.priceLevelId,
    this.priceLevelName = '',
  });

  final String invoiceNumber;
  final DateTime invoiceDate;
  final String customer;
  final String customerName;

  /// Orden de la que salió la factura ('' = venta directa).
  final String orderNumber;
  final String lineId;
  final String itemCode;
  final String description;
  /// Cantidad vendida (`CantidadDespachada` en RM).
  final double quantity;

  /// Parte anulada después (`VoidParcial`); no se despacha.
  final double voidedQuantity;
  final String unit;
  final int transaction;
  final bool isService;

  /// En una anulación, la factura original.
  final String originalInvoice;

  /// Fecha de la factura original, si la API la entrega (solicitado; null = no viene).
  final DateTime? originalInvoiceDate;

  /// Motivo de la devolución, si la API lo entrega (solicitado).
  final String returnReason;

  /// Categoría y nivel de precio vigentes del cliente (ver [RmOrderLine.categoryId]).
  final int? categoryId;
  final String categoryName;
  final int? priceLevelId;
  final String priceLevelName;

  /// Lo que hay que despachar: vendido menos anulado.
  double get toShip => quantity - voidedQuantity;

  /// Devoluciones (70) y anulaciones parciales (71) no se despachan.
  bool get isReturnOrVoid => transaction == 70 || transaction == 71;

  static DateTime _withTime(Map<String, dynamic> j) {
    final d = _date(j, 'InvoiceDate');
    final t = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(_str(j, 'InvoiceTime'));
    if (t == null || d.hour != 0 || d.minute != 0) return d;
    return DateTime(d.year, d.month, d.day, int.parse(t[1]!), int.parse(t[2]!), int.parse(t[3] ?? '0'));
  }

  factory RmInvoiceLine.fromJson(Map<String, dynamic> j) => RmInvoiceLine(
        invoiceNumber: _str(j, 'InvoiceNumber'),
        invoiceDate: _withTime(j),
        voidedQuantity: _num(j, 'VoidedQuantity'),
        originalInvoice: _str(j, 'OriginalInvoice'),
        originalInvoiceDate: _dateOrNull(j, 'OriginalInvoiceDate'),
        returnReason: _str(j, 'ReturnReason'),
        customer: _str(j, 'Cliente'),
        customerName: _str(j, 'ClienteNombre').isEmpty ? _str(j, 'Cliente') : _str(j, 'ClienteNombre'),
        orderNumber: _str(j, 'OrderNumber'),
        lineId: _str(j, 'LineID'),
        itemCode: _str(j, 'ItemCode'),
        description: _str(j, 'Description'),
        quantity: _num(j, 'Quantity'),
        unit: _str(j, 'Unit'),
        transaction: _num(j, 'Transaccion').toInt() == 0 ? 50 : _num(j, 'Transaccion').toInt(),
        isService: _bool(j, 'IsService'),
        categoryId: _intOrNull(j, 'ClienteCategoriaID'),
        categoryName: _str(j, 'ClienteCategoria'),
        priceLevelId: _intOrNull(j, 'ClientePriceLevelID'),
        priceLevelName: _str(j, 'ClientePriceLevel'),
      );
}

/// Una línea de mercancía devuelta o anulada (`SalesReturnsByDate`, solicitado al equipo de la
/// API; ver docs/SOLICITUD_API_DEVOLUCIONES.md). Mientras no exista se arma desde
/// `SalesInvoicesByDate` con [RmReturnLine.fromInvoiceLine].
class RmReturnLine {
  RmReturnLine({
    required this.returnNumber,
    required this.returnType,
    required this.returnDate,
    required this.lineId,
    required this.itemCode,
    required this.description,
    required this.quantity,
    this.originalInvoice = '',
    this.originalInvoiceDate,
    this.customer = '',
    this.customerName = '',
    this.reason = '',
    this.isService = false,
    this.isFuel = false,
  });

  /// `V78`, `VP232-1`…
  final String returnNumber;

  /// 70 devolución / void completo · 71 anulación parcial.
  final int returnType;
  final DateTime returnDate;
  final String lineId;
  final String itemCode;
  final String description;

  /// Unidades que regresan (siempre positiva).
  final double quantity;
  final String originalInvoice;
  final DateTime? originalInvoiceDate;
  final String customer;
  final String customerName;
  final String reason;
  final bool isService;
  final bool isFuel;

  static const returnTypes = {70, 71};

  factory RmReturnLine.fromJson(Map<String, dynamic> j) {
    final d = _date(j, 'ReturnDate');
    final t = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(_str(j, 'ReturnTime'));
    final date = (t == null || d.hour != 0 || d.minute != 0)
        ? d
        : DateTime(d.year, d.month, d.day, int.parse(t[1]!), int.parse(t[2]!), int.parse(t[3] ?? '0'));
    return RmReturnLine(
      returnNumber: _str(j, 'ReturnNumber'),
      returnType: _num(j, 'ReturnType').toInt(),
      returnDate: date,
      lineId: _str(j, 'LineID'),
      itemCode: _str(j, 'ItemCode'),
      description: _str(j, 'Description'),
      quantity: _num(j, 'Quantity').abs(),
      originalInvoice: _str(j, 'OriginalInvoice'),
      originalInvoiceDate: _dateOrNull(j, 'OriginalInvoiceDate'),
      customer: _str(j, 'Customer'),
      customerName: _str(j, 'CustomerName').isEmpty ? _str(j, 'Customer') : _str(j, 'CustomerName'),
      reason: _str(j, 'Reason'),
      isService: _bool(j, 'IsService'),
      isFuel: _bool(j, 'IsFuel'),
    );
  }

  /// Fuente provisional: una línea de `SalesInvoicesByDate` con Transaccion 70/71 (null si no
  /// es devolución). La cantidad se toma en valor absoluto (el signo en RM está por verificar);
  /// si viene en 0 se usa la anulada. El `VoidParcial` de la línea de la factura original
  /// NUNCA se usa: la anulación se cuenta solo desde su documento VP (sin doble conteo).
  static RmReturnLine? fromInvoiceLine(RmInvoiceLine l) {
    if (!returnTypes.contains(l.transaction)) return null;
    final q = l.quantity.abs() > 0 ? l.quantity.abs() : l.voidedQuantity.abs();
    return RmReturnLine(
      returnNumber: l.invoiceNumber,
      returnType: l.transaction,
      returnDate: l.invoiceDate,
      lineId: l.lineId,
      itemCode: l.itemCode,
      description: l.description,
      quantity: q,
      originalInvoice: l.originalInvoice,
      originalInvoiceDate: l.originalInvoiceDate,
      customer: l.customer,
      customerName: l.customerName,
      reason: l.returnReason,
      isService: l.isService,
    );
  }
}

/// Contrato de la API de una tienda. Se separa de HTTP para poder probar sin red.
abstract class RmApi {
  /// Prueba de salud. Devuelve un mensaje legible o lanza [RmApiException].
  Future<String> healthCheck();

  /// Líneas recibidas entre dos fechas (ambas incluidas).
  Future<List<RmReceiptLine>> receiptsByDate(DateTime from, DateTime to, {String? supplier});

  /// Foto de todas las órdenes abiertas (una fila por línea).
  Future<List<RmOrderLine>> openOrders();

  /// Facturas de venta entre dos fechas (ambas incluidas).
  Future<List<RmInvoiceLine>> invoicesByDate(DateTime from, DateTime to);

  /// Devoluciones y anulaciones entre dos fechas (ambas incluidas). Lanza [RmApiException]
  /// con `notAvailable` si la API aún no tiene `SalesReturnsByDate`.
  Future<List<RmReturnLine>> returnsByDate(DateTime from, DateTime to);
}

/// Agrega `/cse.api.v1` si el usuario solo escribió host:puerto.
String normalizeRmBase(String url) {
  var u = url.trim();
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  if (!u.toLowerCase().contains('/cse.api.v1')) u = '$u/cse.api.v1';
  return u;
}

/// Parte [from, to] (días completos, ambos incluidos) en tramos de como máximo [maxDays] días.
List<(DateTime, DateTime)> dateChunks(DateTime from, DateTime to, int maxDays) {
  var a = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day);
  final out = <(DateTime, DateTime)>[];
  while (!a.isAfter(end)) {
    var b = DateTime(a.year, a.month, a.day + maxDays - 1);
    if (b.isAfter(end)) b = end;
    out.add((a, b));
    a = DateTime(b.year, b.month, b.day + 1);
  }
  return out;
}

String fmtApiDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class RmHttpApi implements RmApi {
  RmHttpApi(String baseUrl, {http.Client? client, this.timeout = const Duration(seconds: 20)})
      : base = normalizeRmBase(baseUrl),
        _client = client ?? http.Client();

  final String base;
  final Duration timeout;
  final http.Client _client;

  Future<http.Response> _get(String path, [Map<String, String>? query]) async {
    final uri = Uri.parse('$base/$path').replace(queryParameters: query);
    try {
      return await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw RmApiException('Tiempo de espera agotado al conectar con ${uri.host}.');
    } catch (e) {
      throw RmApiException('No se pudo conectar con ${uri.host}${uri.hasPort ? ':${uri.port}' : ''}: $e');
    }
  }

  dynamic _decode(http.Response r) {
    try {
      return jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      throw RmApiException('Respuesta no válida de la API (HTTP ${r.statusCode}).');
    }
  }

  @override
  Future<String> healthCheck() async {
    final r = await _get('HealthCheck');
    final body = _decode(r);
    if (r.statusCode == 200) {
      final ms = body is Map ? (body['database'] is Map ? body['database']['response_time_ms'] : null) : null;
      return 'Conexión OK${ms != null ? ' · base de datos ${ms}ms' : ''}.';
    }
    if (r.statusCode == 503) throw RmApiException('La API responde, pero no alcanza su base de datos.');
    throw RmApiException('HealthCheck devolvió HTTP ${r.statusCode}.');
  }

  /// GET de un endpoint de lista: `[]` / filas, o `{success:false, message}` con HTTP 200.
  Future<List<T>> _list<T>(String path, Map<String, String> query, T Function(Map<String, dynamic>) parse) async {
    final r = await _get(path, query);
    // Ruta inexistente: Kestrel responde 404 sin el sobre JSON {success,message}.
    if (r.statusCode == 404 && !utf8.decode(r.bodyBytes, allowMalformed: true).contains('"success"')) {
      throw RmApiException('$path no existe todavía en esta API.', notAvailable: true);
    }
    if (r.statusCode != 200) throw RmApiException('$path devolvió HTTP ${r.statusCode}.');
    final body = _decode(r);
    if (body is Map) {
      throw RmApiException((body['message'] ?? 'Error desconocido de la API').toString());
    }
    if (body is! List) throw RmApiException('Formato inesperado en $path.');
    return [for (final row in body) parse(Map<String, dynamic>.from(row as Map))];
  }

  @override
  Future<List<RmReceiptLine>> receiptsByDate(DateTime from, DateTime to, {String? supplier}) => _list(
        'RecReceiptsByDate',
        {
          'DateFrom': fmtApiDate(from),
          'DateTo': fmtApiDate(to),
          if (supplier != null && supplier.trim().isNotEmpty) 'SupNum': supplier.trim(),
        },
        RmReceiptLine.fromJson,
      );

  @override
  Future<List<RmOrderLine>> openOrders() => _list('OrdOpenOrders', {}, RmOrderLine.fromJson);

  /// La API acepta como máximo 31 días por llamada: se pide por tramos.
  static const invoiceMaxDays = 31;

  @override
  Future<List<RmInvoiceLine>> invoicesByDate(DateTime from, DateTime to) async {
    final out = <RmInvoiceLine>[];
    for (final (a, b) in dateChunks(from, to, invoiceMaxDays)) {
      out.addAll(await _list(
        'SalesInvoicesByDate',
        {'DateFrom': fmtApiDate(a), 'DateTo': fmtApiDate(b)},
        RmInvoiceLine.fromJson,
      ));
    }
    return out;
  }

  @override
  Future<List<RmReturnLine>> returnsByDate(DateTime from, DateTime to) async {
    final out = <RmReturnLine>[];
    for (final (a, b) in dateChunks(from, to, invoiceMaxDays)) {
      out.addAll(await _list(
        'SalesReturnsByDate',
        {'DateFrom': fmtApiDate(a), 'DateTo': fmtApiDate(b)},
        RmReturnLine.fromJson,
      ));
    }
    return out;
  }
}

/// Fábrica por URL base; las pruebas la sustituyen por un falso.
final rmApiFactoryProvider = Provider<RmApi Function(String baseUrl)>((ref) => (url) => RmHttpApi(url));
