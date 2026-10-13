enum StepStatus { pending, picked, missingHere }

enum ShortfallStatus { unresolved, missing }

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
}

class Shortfall {
  Shortfall({required this.id, required this.take, this.status = ShortfallStatus.unresolved});

  final String id;
  int take;
  ShortfallStatus status;
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
}
