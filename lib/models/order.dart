import 'json_util.dart';

class OrderItem {
  OrderItem({required this.productId, required this.qty, this.delivered = 0});

  final String productId;

  /// Mutable: una orden de RM aún sin piquear se actualiza si cambia en RM.
  int qty;

  /// Unidades ya despachadas en piqueos anteriores (órdenes parciales).
  int delivered;

  int get remaining => (qty - delivered).clamp(0, qty);

  Map<String, dynamic> toJson() => {'productId': productId, 'qty': qty, 'delivered': delivered};

  factory OrderItem.fromJson(Map j) =>
      OrderItem(productId: jStr(j, 'productId'), qty: jInt(j, 'qty'), delivered: jInt(j, 'delivered'));
}

/// Origen de la orden.
abstract final class OrderSource {
  static const demo = 'demo';
  static const rmOrder = 'rm-order';
  static const rmInvoice = 'rm-invoice';
}

class Order {
  Order({
    required this.id,
    required this.customer,
    required this.store,
    required this.date,
    required this.status,
    required this.items,
    this.source = OrderSource.demo,
    this.rmStore,
    this.rmNumber,
    this.syncNote,
    this.customerId,
    this.categoryId,
    this.categoryName,
    this.priceLevelId,
    this.priceLevelName,
    List<String>? invoices,
  }) : invoices = invoices ?? [];

  final String id;
  final String customer;

  /// Código del cliente en RM (`Clientes.Numero`) y su categoría vigente
  /// (`Clientes.Categoria` → `CategoriasClientes`). La categoría se lee en vivo:
  /// se refresca en cada sincronización con RM. `categoryId == null` = cliente sin categoría.
  String? customerId;
  int? categoryId;
  String? categoryName;

  /// Nivel de precio vigente del cliente (`Clientes.PriceLevel` → `PriceLevels`), también en vivo.
  /// `priceLevelId == null` = sin nivel (RM manda null si es 0 o no hay cliente).
  int? priceLevelId;
  String? priceLevelName;

  final String store;
  final DateTime date;

  /// pendiente | parcial | completada
  String status;
  final List<OrderItem> items;

  /// demo | rm-order | rm-invoice
  final String source;

  /// Tienda (id) y número de orden/factura en RM.
  final String? rmStore;
  final String? rmNumber;

  /// Aviso de sincronización (p. ej. "Cambió en RM", "Facturada en RM · FAC 123").
  String? syncNote;

  /// Facturas de RM enlazadas a esta orden.
  final List<String> invoices;

  bool get isOpen => status != 'completada';
  bool get isRm => source != OrderSource.demo;

  /// Clave de categoría para filtros y conteos: el nombre normalizado ([categoryKeyOf]).
  /// Se agrupa por nombre y no por ID porque cada compañía es una base distinta y el mismo ID
  /// puede ser otra categoría en otra tienda.
  String get categoryKey => categoryKeyOf(categoryLabel);

  String get categoryLabel => categoryName ?? kNoCategoryLabel;

  String get priceLevelLabel => priceLevelName ?? kNoPriceLevelLabel;

  Map<String, dynamic> toJson() => {
        'id': id,
        'customer': customer,
        if (customerId != null) 'customerId': customerId,
        if (categoryId != null) 'categoryId': categoryId,
        if (categoryName != null) 'categoryName': categoryName,
        if (priceLevelId != null) 'priceLevelId': priceLevelId,
        if (priceLevelName != null) 'priceLevelName': priceLevelName,
        'store': store,
        'date': date.toIso8601String(),
        'status': status,
        'items': [for (final i in items) i.toJson()],
        'source': source,
        if (rmStore != null) 'rmStore': rmStore,
        if (rmNumber != null) 'rmNumber': rmNumber,
        if (syncNote != null) 'syncNote': syncNote,
        'invoices': invoices,
      };

  factory Order.fromJson(Map j) => Order(
        id: jStr(j, 'id'),
        customer: jStr(j, 'customer'),
        customerId: jStrOrNull(j, 'customerId'),
        categoryId: jIntOrNull(j, 'categoryId'),
        categoryName: jStrOrNull(j, 'categoryName'),
        priceLevelId: jIntOrNull(j, 'priceLevelId'),
        priceLevelName: jStrOrNull(j, 'priceLevelName'),
        store: jStr(j, 'store'),
        date: jDate(j, 'date'),
        status: jStr(j, 'status'),
        items: [for (final i in jList(j, 'items')) OrderItem.fromJson(i)],
        source: jStrOrNull(j, 'source') ?? OrderSource.demo,
        rmStore: jStrOrNull(j, 'rmStore'),
        rmNumber: jStrOrNull(j, 'rmNumber'),
        syncNote: jStrOrNull(j, 'syncNote'),
        invoices: jStrings(j, 'invoices'),
      );
}

const kNoCategoryLabel = 'Sin categoría';

/// Clave de «Sin categoría» en filtros y conteos.
const kNoCategory = 'sin categoría';

/// Clave de agrupación de una categoría: el nombre sin espacios sobrantes y en minúsculas.
String categoryKeyOf(String label) => label.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

const kNoPriceLevelLabel = 'Sin nivel';

/// Nombre de categoría que se guarda en la orden: null si el cliente no tiene categoría;
/// si RM no manda la descripción, «Categoría n».
String? categoryNameOf(int? id, String name) => id == null ? null : (name.trim().isEmpty ? 'Categoría $id' : name.trim());

/// Igual que [categoryNameOf] para el nivel de precio («Nivel n» si falta el nombre).
String? priceLevelNameOf(int? id, String name) => id == null ? null : (name.trim().isEmpty ? 'Nivel $id' : name.trim());

/// Dimensiones por las que se filtran las órdenes entrantes (una fila de chips cada una).
enum OrderFacet {
  category(kNoCategoryLabel),
  priceLevel(kNoPriceLevelLabel);

  const OrderFacet(this.noneLabel);

  /// Etiqueta de las órdenes sin valor («Sin categoría», «Sin nivel»); va al final de la fila.
  final String noneLabel;

  String labelOf(Order o) => switch (this) {
        OrderFacet.category => o.categoryLabel,
        OrderFacet.priceLevel => o.priceLevelLabel,
      };

  String keyOf(Order o) => categoryKeyOf(labelOf(o));
}

/// Una categoría de cliente con cuántas órdenes tiene (para los chips del filtro).
class OrderCategory {
  const OrderCategory(this.key, this.name, this.count);
  final String key;
  final String name;
  final int count;
}

/// Categorías presentes en [orders], con su conteo, agrupadas por nombre: en orden alfabético y
/// «Sin categoría» al final. Las de [alsoKeep] (etiquetas del filtro guardado) se incluyen aunque
/// ya no tengan órdenes.
List<OrderCategory> orderCategories(Iterable<Order> orders, {Set<String> alsoKeep = const {}}) =>
    orderFacetValues(orders, OrderFacet.category, alsoKeep: alsoKeep);

/// Órdenes de las categorías elegidas ([selected] son etiquetas; se comparan por clave); vacío = todas.
List<Order> filterOrdersByCategory(List<Order> orders, Set<String> selected) =>
    filterOrdersByFacet(orders, OrderFacet.category, selected);

/// Valores de [facet] presentes en [orders] con su conteo (ver [orderCategories]).
List<OrderCategory> orderFacetValues(Iterable<Order> orders, OrderFacet facet, {Set<String> alsoKeep = const {}}) {
  final none = categoryKeyOf(facet.noneLabel);
  final count = <String, int>{};
  final names = <String, String>{};
  void name(String key, String label) =>
      names.putIfAbsent(key, () => label.trim().replaceAll(RegExp(r'\s+'), ' '));
  for (final o in orders) {
    final key = facet.keyOf(o);
    count[key] = (count[key] ?? 0) + 1;
    name(key, facet.labelOf(o));
  }
  for (final label in alsoKeep) {
    final key = categoryKeyOf(label);
    count.putIfAbsent(key, () => 0);
    name(key, label);
  }
  final keys = count.keys.toList()
    ..sort((a, b) {
      if (a == none) return b == none ? 0 : 1;
      if (b == none) return -1;
      return a.compareTo(b);
    });
  return [for (final k in keys) OrderCategory(k, names[k]!, count[k]!)];
}

/// Órdenes cuyo valor de [facet] está entre [selected] (etiquetas, comparadas por clave); vacío = todas.
List<Order> filterOrdersByFacet(List<Order> orders, OrderFacet facet, Set<String> selected) {
  if (selected.isEmpty) return orders;
  final keys = {for (final l in selected) categoryKeyOf(l)};
  return [for (final o in orders) if (keys.contains(facet.keyOf(o))) o];
}
