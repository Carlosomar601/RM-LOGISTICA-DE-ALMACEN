import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piqueo_fifo_centeno/main.dart';
import 'package:rm_core/models/app_user.dart';
import 'package:rm_core/models/order.dart';
import 'package:rm_core/state/app_state.dart';
import 'package:rm_core/sync/dispatch_ledger.dart';

import 'fake_rm_api.dart';

const p1 = 'MI-20565R15';

Order mk(String id, {int? cat, String? name, String store = 'Tienda'}) => Order(
      id: id,
      customer: 'Cliente $id',
      store: store,
      date: DateTime(2026, 10, 13),
      status: 'pendiente',
      items: [],
      categoryId: cat,
      categoryName: name,
    );

void main() {
  group('categorías y filtro (lógica)', () {
    final orders = [
      mk('a', cat: 1000, name: 'Cuentas Incobrables'),
      mk('b', cat: 1, name: 'Cliente General'),
      mk('c'),
      mk('d', cat: 999, name: 'Ruta - Vendedor'),
      mk('e', cat: 1, name: 'Cliente General'),
    ];

    test('categorías por nombre en orden alfabético y «Sin categoría» al final, con conteo', () {
      final cats = orderCategories(orders);
      expect([for (final k in cats) k.name], ['Cliente General', 'Cuentas Incobrables', 'Ruta - Vendedor', 'Sin categoría']);
      expect([for (final k in cats) k.count], [2, 1, 1, 1]);
      expect(cats.last.key, kNoCategory);
    });

    test('una categoría del filtro guardado se conserva aunque ya no tenga órdenes', () {
      final cats = orderCategories(orders, alsoKeep: {'Mayoristas'});
      final k = cats.firstWhere((k) => k.name == 'Mayoristas');
      expect(k.count, 0);
      expect(cats.last.key, kNoCategory, reason: '«Sin categoría» sigue al final');
    });

    test('filtrar: vacío = todas; varias categorías a la vez; «Sin categoría» incluida', () {
      expect(filterOrdersByCategory(orders, {}).length, 5);
      expect(filterOrdersByCategory(orders, {'Cliente General'}).map((o) => o.id), ['b', 'e']);
      expect(filterOrdersByCategory(orders, {'Ruta - Vendedor', kNoCategoryLabel}).map((o) => o.id), ['c', 'd']);
      expect(filterOrdersByCategory(orders, {'Otra'}), isEmpty);
      // Sin distinguir mayúsculas ni espacios sobrantes.
      expect(filterOrdersByCategory(orders, {'  cliente   GENERAL '}).map((o) => o.id), ['b', 'e']);
    });

    test('varias compañías: se agrupa por nombre, no por ID', () {
      final multi = [
        mk('a', cat: 1, name: 'Cliente General', store: 'Tienda A'),
        mk('b', cat: 7, name: 'Cliente General', store: 'Tienda B'), // mismo nombre, otro ID
        mk('c', cat: 1, name: 'Mayoristas', store: 'Tienda C'), // mismo ID, otra categoría
      ];
      final cats = orderCategories(multi);
      expect([for (final k in cats) (k.name, k.count)], [('Cliente General', 2), ('Mayoristas', 1)]);
      expect(filterOrdersByCategory(multi, {'Mayoristas'}).map((o) => o.id), ['c']);
    });

    test('nivel de precio: misma lógica de filas, «Sin nivel» al final, y se combina con la categoría', () {
      final withLevels = [
        mk('a', cat: 1, name: 'Cliente General')
          ..priceLevelId = 3
          ..priceLevelName = 'Por Mayor',
        mk('b', cat: 1, name: 'Cliente General')
          ..priceLevelId = 1
          ..priceLevelName = 'Precio Venta',
        mk('c', cat: 999, name: 'Ruta - Vendedor')
          ..priceLevelId = 3
          ..priceLevelName = 'Por Mayor',
        mk('d'),
      ];
      final levels = orderFacetValues(withLevels, OrderFacet.priceLevel);
      expect([for (final k in levels) (k.name, k.count)], [('Por Mayor', 2), ('Precio Venta', 1), ('Sin nivel', 1)]);
      final wholesale = filterOrdersByFacet(withLevels, OrderFacet.priceLevel, {'Por Mayor'});
      expect(wholesale.map((o) => o.id), ['a', 'c']);
      // Combinado: Por Mayor Y Cliente General.
      expect(filterOrdersByCategory(wholesale, {'Cliente General'}).map((o) => o.id), ['a']);
      expect(priceLevelNameOf(4, ''), 'Nivel 4');
      expect(priceLevelNameOf(null, 'X'), isNull);
    });

    test('la orden guarda cliente y categoría en JSON; un JSON viejo sin ellos sigue leyéndose', () {
      final o = mk('x', cat: 999, name: 'Ruta - Vendedor')
        ..customerId = 'C7'
        ..priceLevelId = 3
        ..priceLevelName = 'Por Mayor';
      final back = Order.fromJson(o.toJson());
      expect((back.customerId, back.categoryId, back.categoryName), ('C7', 999, 'Ruta - Vendedor'));
      expect((back.priceLevelId, back.priceLevelName), (3, 'Por Mayor'));
      final legacy = o.toJson()
        ..remove('customerId')
        ..remove('categoryId')
        ..remove('categoryName')
        ..remove('priceLevelId')
        ..remove('priceLevelName');
      final old = Order.fromJson(legacy);
      expect(old.categoryId, isNull);
      expect((old.priceLevelId, old.priceLevelLabel), (null, 'Sin nivel'));
      expect(old.categoryKey, kNoCategory);
      expect(old.categoryLabel, 'Sin categoría');
    });

    test('el usuario recuerda su filtro en JSON; sin el campo, vacío (= todas)', () {
      final u = AppUser(
        id: 'u9',
        name: 'Ana',
        email: '',
        role: 'Piqueador',
        active: true,
        perms: rolePreset('Piqueador'),
        orderCategories: ['Ruta - Vendedor', kNoCategoryLabel],
        orderPriceLevels: ['Por Mayor'],
      );
      expect(AppUser.fromJson(u.toJson()).orderCategories, ['Ruta - Vendedor', kNoCategoryLabel]);
      expect(AppUser.fromJson(u.toJson()).orderPriceLevels, ['Por Mayor']);
      final plain = AppUser.fromJson(u.toJson()
        ..remove('orderCategories')
        ..remove('orderPriceLevels'));
      expect(plain.orderCategories, isEmpty);
      expect(plain.orderPriceLevels, isEmpty);
      // Un filtro guardado por ID (versión anterior) se descarta: vuelve a «Todas».
      final legacy = AppUser.fromJson(u.toJson()..['orderCategories'] = [999, -1]);
      expect(legacy.orderCategories, isEmpty);
    });
  });

  group('sincronización: categoría en vivo', () {
    late Directory tmp;
    late ProviderContainer c;
    AppState s() => c.read(appProvider);
    AppNotifier n() => c.read(appProvider.notifier);
    Order ord(String id) => s().orders.firstWhere((o) => o.id == id);

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('piqueo_cat');
      c = ProviderContainer(overrides: [
        ledgerProvider.overrideWithValue(DispatchLedger.load(File('${tmp.path}/ledger.json'))),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 13, 16)),
      ]);
    });
    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    test('la orden importada trae cliente y categoría', () {
      n().importOpenOrders('s0', [oline('7001', p1, 4, category: 999, categoryName: 'Ruta - Vendedor')]);
      final o = ord('ORD-7001');
      expect(o.customerId, 'C1');
      expect(o.categoryId, 999);
      expect(o.categoryName, 'Ruta - Vendedor');
      expect(o.categoryKey, 'ruta - vendedor');
    });

    test('sin categoría en RM (o API que aún no la envía): «Sin categoría»', () {
      n().importOpenOrders('s0', [oline('7002', p1, 4)]);
      final o = ord('ORD-7002');
      expect(o.categoryId, isNull);
      expect(o.categoryKey, kNoCategory);
      expect(o.categoryLabel, 'Sin categoría');
    });

    test('categoría con ID pero sin descripción: «Categoría n»', () {
      n().importOpenOrders('s0', [oline('7003', p1, 4, category: 5)]);
      expect(ord('ORD-7003').categoryName, 'Categoría 5');
    });

    test('si el cliente cambia de categoría en RM, la orden abierta la sigue en la próxima sincronización', () {
      n().importOpenOrders('s0', [oline('7004', p1, 4, category: 1, categoryName: 'Cliente General')]);
      expect(ord('ORD-7004').categoryId, 1);

      // Mismas cantidades: antes esto no tocaba la orden.
      final r = n().importOpenOrders('s0', [oline('7004', p1, 4, category: 1000, categoryName: 'Cuentas Incobrables')]);
      expect(r.created + r.updated + r.flagged, 0, reason: 'las cantidades no cambiaron');
      expect(ord('ORD-7004').categoryId, 1000);
      expect(ord('ORD-7004').categoryName, 'Cuentas Incobrables');

      // Y si le quitan la categoría, vuelve a «Sin categoría».
      n().importOpenOrders('s0', [oline('7004', p1, 4)]);
      expect(ord('ORD-7004').categoryId, isNull);
    });

    test('las facturas importadas también traen la categoría y la actualizan', () {
      n().importInvoices('s0', [iline('9001', p1, 2, category: 1, categoryName: 'Cliente General')]);
      expect(ord('FAC-9001').categoryId, 1);
      n().importInvoices('s0', [iline('9001', p1, 2, category: 999, categoryName: 'Ruta - Vendedor')]);
      expect(ord('FAC-9001').categoryId, 999);
      expect(ord('FAC-9001').categoryName, 'Ruta - Vendedor');
    });

    test('el nivel de precio se importa y se refresca en vivo (órdenes y facturas)', () {
      n().importOpenOrders('s0', [oline('7010', p1, 4, priceLevel: 1, priceLevelName: 'Precio Venta')]);
      expect((ord('ORD-7010').priceLevelId, ord('ORD-7010').priceLevelName), (1, 'Precio Venta'));
      n().importOpenOrders('s0', [oline('7010', p1, 4, priceLevel: 3, priceLevelName: 'Por Mayor')]);
      expect(ord('ORD-7010').priceLevelName, 'Por Mayor');
      n().importOpenOrders('s0', [oline('7010', p1, 4)]); // API vieja o nivel 0
      expect(ord('ORD-7010').priceLevelLabel, 'Sin nivel');

      n().importInvoices('s0', [iline('9010', p1, 2, priceLevel: 3, priceLevelName: '')]);
      expect(ord('FAC-9010').priceLevelName, 'Nivel 3');
      n().importInvoices('s0', [iline('9010', p1, 2, priceLevel: 1, priceLevelName: 'Precio Venta')]);
      expect(ord('FAC-9010').priceLevelName, 'Precio Venta');
    });

    test('el filtro de nivel se guarda por usuario, aparte del de categoría', () {
      expect(n().login('1111'), isNull);
      n().setOrderPriceLevelFilter({'Por Mayor'});
      expect(s().orderPriceLevelFilter, {'Por Mayor'});
      expect(s().orderCategoryFilter, isEmpty);
      n().logout();
      expect(n().login('2222'), isNull);
      expect(s().orderPriceLevelFilter, isEmpty);
      n().logout();
      expect(n().login('1111'), isNull);
      expect(s().orderPriceLevelFilter, {'Por Mayor'});
      n().logout();
      n().setOrderPriceLevelFilter({'Detal'}); // sin sesión: no guarda
      expect(s().orderPriceLevelFilter, isEmpty);
    });

    test('el filtro se guarda por usuario y vuelve al iniciar sesión', () {
      expect(n().login('1111'), isNull); // administrador demo
      expect(s().orderCategoryFilter, isEmpty);
      n().setOrderCategoryFilter({kNoCategoryLabel, 'Ruta - Vendedor'});
      expect(s().orderCategoryFilter, {'Ruta - Vendedor', kNoCategoryLabel});
      expect(s().currentUser!.orderCategories, ['Ruta - Vendedor', kNoCategoryLabel]);

      n().logout();
      expect(n().login('2222'), isNull); // otro usuario: no hereda el filtro
      expect(s().orderCategoryFilter, isEmpty);

      n().logout();
      expect(n().login('1111'), isNull);
      expect(s().orderCategoryFilter, {'Ruta - Vendedor', kNoCategoryLabel});

      n().setOrderCategoryFilter({}); // «Todas»
      expect(s().orderCategoryFilter, isEmpty);
    });

    test('sin sesión iniciada no se guarda ningún filtro', () {
      n().setOrderCategoryFilter({'Cliente General'});
      expect(s().orderCategoryFilter, isEmpty);
    });
  });

  group('pantalla Órdenes entrantes', () {
    late ProviderContainer container;

    Future<void> pump(WidgetTester t, {Size size = const Size(1440, 1000)}) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(appProvider.notifier).login('1111');
      await t.pumpWidget(UncontrolledProviderScope(container: container, child: const PiqueoApp()));
      await t.pumpAndSettle();
      container.read(appProvider.notifier).navigate(AppView.orders);
      await t.pumpAndSettle();
    }

    Future<void> tapChip(WidgetTester t, String label) async {
      final f = find.text(label);
      expect(f, findsOneWidget, reason: 'no se encontró el chip "$label"');
      await t.ensureVisible(f);
      await t.pumpAndSettle();
      await t.tap(f);
      await t.pumpAndSettle();
    }

    testWidgets('chips con contador, selección múltiple y «Todas» por defecto', (t) async {
      await pump(t);
      expect(find.text('Todas (3)'), findsOneWidget);
      expect(find.text('Cliente General (1)'), findsOneWidget);
      expect(find.text('Ruta - Vendedor (1)'), findsOneWidget);
      expect(find.text('Cuentas Incobrables (1)'), findsOneWidget);
      for (final id in ['OV-10501', 'OV-10502', 'OV-10503']) {
        expect(find.textContaining(id), findsOneWidget);
      }

      await tapChip(t, 'Ruta - Vendedor (1)');
      expect(find.textContaining('OV-10502'), findsOneWidget);
      expect(find.textContaining('OV-10501'), findsNothing);
      expect(find.textContaining('OV-10503'), findsNothing);
      expect(find.text('Pendientes (1 de 3)'), findsOneWidget);
      // El conteo de cada categoría no cambia al elegir una.
      expect(find.text('Cliente General (1)'), findsOneWidget);

      await tapChip(t, 'Cuentas Incobrables (1)'); // se suma
      expect(find.textContaining('OV-10502'), findsOneWidget);
      expect(find.textContaining('OV-10503'), findsOneWidget);
      expect(find.textContaining('OV-10501'), findsNothing);
      expect(find.text('Pendientes (2 de 3)'), findsOneWidget);

      await tapChip(t, 'Todas (3)');
      expect(find.textContaining('OV-10501'), findsOneWidget);
      expect(find.text('Pendientes (3)'), findsOneWidget);
      expect(container.read(appProvider).orderCategoryFilter, isEmpty);
    });

    testWidgets('fila de nivel de precio: «Todos», contadores cruzados y filtro combinado', (t) async {
      await pump(t);
      expect(find.text('Nivel de precio'), findsOneWidget);
      expect(find.text('Todos (3)'), findsOneWidget);
      expect(find.text('Precio Venta (2)'), findsOneWidget);
      expect(find.text('Por Mayor (1)'), findsOneWidget);

      await tapChip(t, 'Por Mayor (1)');
      expect(find.textContaining('OV-10502'), findsOneWidget);
      expect(find.textContaining('OV-10501'), findsNothing);
      expect(find.text('Pendientes (1 de 3)'), findsOneWidget);
      // La fila de categorías cuenta solo las órdenes Por Mayor.
      expect(find.text('Todas (1)'), findsOneWidget);
      expect(find.text('Ruta - Vendedor (1)'), findsOneWidget);
      expect(find.text('Cliente General (1)'), findsNothing);

      // Categoría sin órdenes Por Mayor: la lista queda vacía.
      await tapChip(t, 'Todos (3)');
      await tapChip(t, 'Cliente General (1)');
      expect(find.text('Precio Venta (1)'), findsOneWidget);
      await tapChip(t, 'Precio Venta (1)');
      expect(find.textContaining('OV-10501'), findsOneWidget);
      expect(container.read(appProvider).orderPriceLevelFilter, {'Precio Venta'});
      expect(container.read(appProvider).orderCategoryFilter, {'Cliente General'});
      expect(t.takeException(), isNull);
    });

    testWidgets('una orden nueva sin categoría aparece bajo «Sin categoría»', (t) async {
      await pump(t);
      container.read(appProvider.notifier).importOpenOrders('s0', [oline('7100', p1, 3)]);
      await t.pumpAndSettle();
      expect(find.text('Sin categoría (1)'), findsOneWidget);
      await tapChip(t, 'Sin categoría (1)');
      expect(find.textContaining('ORD-7100'), findsOneWidget);
      expect(find.textContaining('OV-10501'), findsNothing);
    });

    testWidgets('si nadie tiene categoría, la fila de chips no aparece', (t) async {
      await pump(t);
      final n = container.read(appProvider.notifier);
      for (final o in container.read(appProvider).orders) {
        o
          ..categoryId = null
          ..categoryName = null;
      }
      n.navigate(AppView.dashboard);
      await t.pumpAndSettle();
      n.navigate(AppView.orders);
      await t.pumpAndSettle();
      expect(find.text('Categoría de cliente'), findsNothing);
    });

    testWidgets('sin overflow con la fila de chips a 360 px', (t) async {
      await pump(t, size: const Size(360, 800));
      await tapChip(t, 'Cliente General (1)');
      expect(t.takeException(), isNull);
    });
  });
}
