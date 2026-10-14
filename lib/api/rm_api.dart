import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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

DateTime _date(Map<String, dynamic> j, String k) {
  final d = DateTime.tryParse(_str(j, k).replaceFirst(' ', 'T'));
  if (d == null) throw RmApiException('Fecha inválida en $k: «${_str(j, k)}»');
  return d;
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
      );
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
}

/// Fábrica por URL base; las pruebas la sustituyen por un falso.
final rmApiFactoryProvider = Provider<RmApi Function(String baseUrl)>((ref) => (url) => RmHttpApi(url));
