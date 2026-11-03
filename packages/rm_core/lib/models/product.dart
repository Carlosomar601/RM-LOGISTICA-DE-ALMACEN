import 'json_util.dart';

class Product {
  Product({required this.id, required this.code, required this.desc, this.committed = 0});

  final String id;
  final String code;
  final String desc;
  int committed;

  Map<String, dynamic> toJson() => {'id': id, 'code': code, 'desc': desc, 'committed': committed};

  factory Product.fromJson(Map j) =>
      Product(id: jStr(j, 'id'), code: jStr(j, 'code'), desc: jStr(j, 'desc'), committed: jInt(j, 'committed'));
}
