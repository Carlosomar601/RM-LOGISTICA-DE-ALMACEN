import 'json_util.dart';

enum StepStatus { pending, picked, missingHere }

enum ShortfallStatus { unresolved, missing }

T _enum<T extends Enum>(List<T> values, Map j, String key) {
  final name = jStr(j, key);
  return values.firstWhere((v) => v.name == name, orElse: () => throw FormatException('campo "$key" inválido: $name'));
}

class PickStep {
  PickStep({
    required this.id,
    required this.invId,
    required this.bin,
    required this.receipt,
    required this.entryDate,
    required this.available,
    required this.take,
    this.status = StepStatus.pending,
  });

  final String id;
  final String invId;
  final String bin;
  final String receipt;
  final DateTime entryDate;
  final int available;
  final int take;
  StepStatus status;

  Map<String, dynamic> toJson() => {
        'id': id,
        'invId': invId,
        'bin': bin,
        'receipt': receipt,
        'entryDate': entryDate.toIso8601String(),
        'available': available,
        'take': take,
        'status': status.name,
      };

  factory PickStep.fromJson(Map j) => PickStep(
        id: jStr(j, 'id'),
        invId: jStr(j, 'invId'),
        bin: jStr(j, 'bin'),
        receipt: jStr(j, 'receipt'),
        entryDate: jDate(j, 'entryDate'),
        available: jInt(j, 'available'),
        take: jInt(j, 'take'),
        status: _enum(StepStatus.values, j, 'status'),
      );
}

class Shortfall {
  Shortfall({required this.id, required this.take, this.status = ShortfallStatus.unresolved});

  final String id;
  int take;
  ShortfallStatus status;

  Map<String, dynamic> toJson() => {'id': id, 'take': take, 'status': status.name};

  factory Shortfall.fromJson(Map j) =>
      Shortfall(id: jStr(j, 'id'), take: jInt(j, 'take'), status: _enum(ShortfallStatus.values, j, 'status'));
}

class PickSession {
  PickSession({
    required this.key,
    required this.productId,
    required this.qtyRequested,
    required this.doc,
    required this.steps,
    this.shortfall,
  });

  final String key;
  final String productId;
  final int qtyRequested;
  final String doc;
  final List<PickStep> steps;
  Shortfall? shortfall;

  Map<String, dynamic> toJson() => {
        'key': key,
        'productId': productId,
        'qtyRequested': qtyRequested,
        'doc': doc,
        'steps': [for (final s in steps) s.toJson()],
        if (shortfall != null) 'shortfall': shortfall!.toJson(),
      };

  factory PickSession.fromJson(Map j) => PickSession(
        key: jStr(j, 'key'),
        productId: jStr(j, 'productId'),
        qtyRequested: jInt(j, 'qtyRequested'),
        doc: jStr(j, 'doc'),
        steps: [for (final s in jList(j, 'steps')) PickStep.fromJson(s)],
        shortfall: j['shortfall'] is Map ? Shortfall.fromJson(j['shortfall'] as Map) : null,
      );
}
