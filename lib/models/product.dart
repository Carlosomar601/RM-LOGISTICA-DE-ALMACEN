class Product {
  Product({required this.id, required this.code, required this.desc, this.committed = 0});

  final String id;
  final String code;
  final String desc;
  int committed;
}
