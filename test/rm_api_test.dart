import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rm_core/api/rm_api.dart';
import 'package:rm_core/state/app_state.dart';

import 'fake_rm_api.dart';

void main() {
  group('RmHttpApi', () {
    test('normaliza la URL base', () {
      expect(normalizeRmBase('http://srv:8180'), 'http://srv:8180/cse.api.v1');
      expect(normalizeRmBase('http://srv:8180/'), 'http://srv:8180/cse.api.v1');
      expect(normalizeRmBase('http://srv:8180/cse.api.v1/'), 'http://srv:8180/cse.api.v1');
    });

    test('RecReceiptsByDate: parámetros y mapeo de campos', () async {
      late Uri seen;
      final api = RmHttpApi('http://srv:8180', client: MockClient((req) async {
        seen = req.url;
        return http.Response(
          jsonEncode([
            {
              'ReceiptNumber': 'R-1001',
              'OrderNumber': '2648',
              'ReceiptDate': '2026-10-12 09:30:00',
              'Supplier': '17160',
              'SupplierName': 'ALL TOOLS, INC.',
              'ItemCode': 'THH12N',
              'Description': 'THHN #12 NEGRO',
              'QuantityReceived': 500,
              'UnitID': 28,
              'Unit': 'ROLLO',
              'UserID': '2',
              'InvoiceNumber': 'INV-5521',
              'Cost': 0.13,
              'LineID': 9001,
            }
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }));
      final rows = await api.receiptsByDate(DateTime(2026, 10, 12), DateTime(2026, 10, 13), supplier: ' 17160 ');
      expect(seen.path, '/cse.api.v1/RecReceiptsByDate');
      expect(seen.queryParameters, {'DateFrom': '2026-10-12', 'DateTo': '2026-10-13', 'SupNum': '17160'});
      expect(rows.single.lineId, '9001');
      expect(rows.single.supplierName, 'ALL TOOLS, INC.');
      expect(rows.single.quantityReceived, 500);
      expect(rows.single.receiptDate, DateTime(2026, 10, 12, 9, 30));
    });

    test('lista vacía y errores del cuerpo con HTTP 200', () async {
      final empty = RmHttpApi('http://srv', client: MockClient((_) async => http.Response('[]', 200)));
      expect(await empty.receiptsByDate(DateTime(2026), DateTime(2026)), isEmpty);
      final bad = RmHttpApi(
        'http://srv',
        client: MockClient(
            (_) async => http.Response('{"success":false,"message":"Supplier not found","status":404}', 200)),
      );
      expect(
        bad.receiptsByDate(DateTime(2026), DateTime(2026)),
        throwsA(isA<RmApiException>().having((e) => e.message, 'message', 'Supplier not found')),
      );
    });

    test('SalesInvoicesByDate: tramos de 31 días, hora y campos de anulación', () async {
      final seen = <Map<String, String>>[];
      final api = RmHttpApi('http://srv', client: MockClient((req) async {
        seen.add(req.url.queryParameters);
        return http.Response(
          jsonEncode([
            {
              'InvoiceNumber': 'C267377', 'InvoiceDate': '2026-09-30 00:00:00', 'InvoiceTime': '15:58:42',
              'Cliente': '2', 'ClienteNombre': 'SUPER FARMACIA VANGA', 'Transaccion': 61, 'OrderNumber': null,
              'OriginalInvoice': null, 'LineID': 1537684, 'Archived': false, 'ItemCode': '851000002163',
              'Description': '1-2-3 PESCAO VINO 750ML', 'Quantity': 5.0, 'VoidedQuantity': 2.0, 'Unit': 'CALIENTE',
              'UnitConv': 1, 'IsService': false,
            }
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }));
      final rows = await api.invoicesByDate(DateTime(2026, 8, 1), DateTime(2026, 10, 13));
      expect(seen.map((q) => '${q['DateFrom']}..${q['DateTo']}'),
          ['2026-08-01..2026-08-31', '2026-09-01..2026-10-01', '2026-10-02..2026-10-13']);
      expect(rows.length, 3);
      final r = rows.first;
      expect((r.invoiceDate, r.transaction, r.orderNumber, r.toShip), (DateTime(2026, 9, 30, 15, 58, 42), 61, '', 3.0));
    });

    test('OrdOpenOrders: mapeo de campos reales', () async {
      final api = RmHttpApi('http://srv', client: MockClient((_) async => http.Response(
            jsonEncode([
              {
                'OrderNumber': 'LA2', 'OrderDate': '2025-11-12 00:00:00', 'Cliente': '95846', 'ClienteNombre': 'Carlos',
                'Vendedor': 1, 'Comentario': null, 'Station': 207, 'LineID': 37, 'ItemCode': '38000222658',
                'Description': 'POP TARTS', 'QuantityOrdered': 7.0, 'QuantityShipped': 0.0, 'Pending': 7.0,
                'Unit': 'EACH', 'UnitConv': 1, 'IsService': false, 'IsFuel': false,
              }
            ]),
            200,
          )));
      final r = (await api.openOrders()).single;
      expect((r.orderNumber, r.customerName, r.pending, r.isService, r.isFuel), ('LA2', 'Carlos', 7.0, false, false));
      // API que aún no envía la categoría: sin categoría.
      expect((r.categoryId, r.categoryName), (null, ''));
    });

    test('categoría del cliente (solicitud a RM API 1.14): con valor, null y sin descripción', () async {
      Map<String, dynamic> line(String n, Object? id, Object? name) => {
            'OrderNumber': n, 'OrderDate': '2026-11-03 09:00:00', 'Cliente': 'C$n', 'ClienteNombre': 'Cliente $n',
            'LineID': n, 'ItemCode': 'X', 'Description': 'X', 'QuantityOrdered': 1, 'Pending': 1,
            'ClienteCategoriaID': id, 'ClienteCategoria': name,
          };
      final api = RmHttpApi('http://srv', client: MockClient((_) async => http.Response(
            jsonEncode([line('1', 999, 'Ruta - Vendedor'), line('2', null, null), line('3', '5', '')]),
            200,
          )));
      final rows = await api.openOrders();
      expect([for (final r in rows) (r.categoryId, r.categoryName)], [(999, 'Ruta - Vendedor'), (null, ''), (5, '')]);
    });

    test('nivel de precio del cliente (RM API 1.14.0) en órdenes y facturas', () async {
      final api = RmHttpApi('http://srv', client: MockClient((req) async {
        final common = {'Cliente': 'C1', 'ClienteNombre': 'X', 'LineID': 1, 'ItemCode': 'X', 'Description': 'X'};
        final body = req.url.path.endsWith('OrdOpenOrders')
            ? [
                {...common, 'OrderNumber': 'O1', 'OrderDate': '2026-11-03 09:00:00', 'Pending': 1,
                  'ClientePriceLevelID': 3, 'ClientePriceLevel': 'Por Mayor'},
              ]
            : [
                {...common, 'InvoiceNumber': 'F1', 'InvoiceDate': '2026-11-03 00:00:00', 'Quantity': 1,
                  'ClientePriceLevelID': null, 'ClientePriceLevel': null},
              ];
        return http.Response(jsonEncode(body), 200);
      }));
      final o = (await api.openOrders()).single;
      expect((o.priceLevelId, o.priceLevelName), (3, 'Por Mayor'));
      final f = (await api.invoicesByDate(DateTime(2026, 11, 3), DateTime(2026, 11, 3))).single;
      expect((f.priceLevelId, f.priceLevelName), (null, ''));
    });

    test('endpoint inexistente (404 sin sobre JSON) → notAvailable', () async {
      final api = RmHttpApi('http://srv', client: MockClient((_) async => http.Response('', 404)));
      expect(api.openOrders(), throwsA(isA<RmApiException>().having((e) => e.notAvailable, 'notAvailable', isTrue)));
    });

    test('HealthCheck: 200, 503 y red caída', () async {
      final ok = RmHttpApi('http://srv',
          client: MockClient((_) async =>
              http.Response('{"status":"healthy","database":{"connected":true,"response_time_ms":42}}', 200)));
      expect(await ok.healthCheck(), contains('42ms'));
      final down = RmHttpApi('http://srv', client: MockClient((_) async => http.Response('{"status":"unhealthy"}', 503)));
      expect(down.healthCheck(), throwsA(isA<RmApiException>()));
      final dead = RmHttpApi('http://srv', client: MockClient((_) async => throw http.ClientException('sin red')));
      expect(dead.healthCheck(), throwsA(isA<RmApiException>()));
    });
  });

  group('importación de recibos', () {
    late ProviderContainer c;
    AppState s() => c.read(appProvider);
    AppNotifier n() => c.read(appProvider.notifier);
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    test('crea recibo pendiente, producto nuevo y reutiliza existentes', () {
      final res = n().importReceiptLines('s0', [
        line('1', code: 'MI-20565R15', qty: 12),
        line('2', code: 'THH12N', desc: 'THHN #12 NEGRO', qty: 500),
      ]);
      expect((res.lines, res.receiptsCreated, res.productsCreated), (2, 1, 1));
      final rec = s().receipts.first;
      expect(rec.id, 'RM-5001');
      expect(rec.supplier, 'Michelin PR Distribuidora');
      expect(rec.isPending, isTrue);
      expect(rec.items.map((i) => i.qtyReceived), [12, 500]);
      expect(s().product(rec.items.first.productId).code, 'MI-20565R15');
      expect(s().products.length, 11);
      expect(s().products.last.code, 'THH12N');
    });

    test('es idempotente por LineID y suma líneas nuevas al mismo recibo', () {
      n().importReceiptLines('s0', [line('1', qty: 12)]);
      final again = n().importReceiptLines('s0', [line('1', qty: 12), line('2', qty: 8)]);
      expect((again.lines, again.duplicates, again.receiptsUpdated, again.receiptsCreated), (1, 1, 1, 0));
      expect(s().receipts.where((r) => r.id == 'RM-5001').single.items.single.qtyReceived, 20);
    });

    test('omite líneas inválidas y redondea decimales', () {
      final res = n().importReceiptLines('s0', [
        line('1', qty: 0),
        line('', qty: 5),
        line('3', qty: 2.6, code: 'WIRE-1', desc: 'Cable'),
      ]);
      expect((res.lines, res.skipped, res.fractional), (1, 2, 1));
      expect(s().receipts.first.items.single.qtyReceived, 3);
    });

    test('el recibo importado se puede ubicar en canastas', () {
      n().addBin('s0', 'Z-09-09');
      n().importReceiptLines('s0', [line('1', qty: 12, code: 'THH12N', desc: 'THHN #12')]);
      final rec = s().receipts.first;
      final pid = rec.items.single.productId;
      expect(n().allocateReceiptItem(rec.id, pid, [('Z-09-09', 12)]), isNull);
      expect(s().receipts.first.isPending, isFalse);
      final row = s().inventory.firstWhere((r) => r.receipt == rec.id);
      expect(row.entryDate, rec.date);
    });

    test('fetch: exige dirección API y propaga errores', () async {
      c.dispose();
      c = ProviderContainer(overrides: [
        rmApiFactoryProvider.overrideWithValue((_) => FakeRmApi(lines: [line('1')])),
      ]);
      expect(n().fetchReceiptLines('s0', DateTime(2026), DateTime(2026)), throwsA(isA<RmApiException>()));
      n().updateStore('s0', apiUrl: 'http://srv:8180');
      expect((await n().fetchReceiptLines('s0', DateTime(2026), DateTime(2026))).length, 1);
    });
  });
}
