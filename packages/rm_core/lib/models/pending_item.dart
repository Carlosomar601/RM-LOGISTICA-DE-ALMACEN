import 'json_util.dart';

enum PendingStatus { abierto, encontrado, baja }

const kPendingStatusLabels = <PendingStatus, String>{
  PendingStatus.abierto: 'Abierto',
  PendingStatus.encontrado: 'Encontrado',
  PendingStatus.baja: 'Dado de baja',
};

/// Mercancía que no apareció (auditoría o piqueo). No cuenta como existencia:
/// queda en el área PENDIENTES con su lote, fecha y recibo originales hasta que
/// Administración la encuentra (vuelve a una canasta) o la da de baja.
class PendingItem {
  PendingItem({
    required this.id,
    required this.productId,
    required this.qty,
    required this.lot,
    required this.entryDate,
    required this.receipt,
    required this.originBin,
    required this.sourceDoc,
    required this.reason,
    required this.createdAt,
    required this.createdBy,
    this.note,
    this.status = PendingStatus.abierto,
    this.resolvedAt,
    this.resolvedBy,
    this.foundBin,
    this.resolutionReason,
    this.resolutionNote,
  });

  final String id;
  final String productId;
  int qty;
  final String lot;
  final DateTime entryDate;
  final String receipt;
  final String originBin;

  /// AUD-n o el documento del piqueo.
  final String sourceDoc;
  final String reason;
  final String? note;
  final DateTime createdAt;
  final String createdBy;

  PendingStatus status;
  DateTime? resolvedAt;
  String? resolvedBy;
  String? foundBin;
  String? resolutionReason;
  String? resolutionNote;

  bool get isOpen => status == PendingStatus.abierto;

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'qty': qty,
        'lot': lot,
        'entryDate': entryDate.toIso8601String(),
        'receipt': receipt,
        'originBin': originBin,
        'sourceDoc': sourceDoc,
        'reason': reason,
        if (note != null) 'note': note,
        'createdAt': createdAt.toIso8601String(),
        'createdBy': createdBy,
        'status': status.name,
        if (resolvedAt != null) 'resolvedAt': resolvedAt!.toIso8601String(),
        if (resolvedBy != null) 'resolvedBy': resolvedBy,
        if (foundBin != null) 'foundBin': foundBin,
        if (resolutionReason != null) 'resolutionReason': resolutionReason,
        if (resolutionNote != null) 'resolutionNote': resolutionNote,
      };

  factory PendingItem.fromJson(Map j) {
    final st = jStr(j, 'status');
    return PendingItem(
      id: jStr(j, 'id'),
      productId: jStr(j, 'productId'),
      qty: jInt(j, 'qty'),
      lot: jStr(j, 'lot'),
      entryDate: jDate(j, 'entryDate'),
      receipt: jStr(j, 'receipt'),
      originBin: jStr(j, 'originBin'),
      sourceDoc: jStr(j, 'sourceDoc'),
      reason: jStr(j, 'reason'),
      note: jStrOrNull(j, 'note'),
      createdAt: jDate(j, 'createdAt'),
      createdBy: jStr(j, 'createdBy'),
      status: PendingStatus.values.firstWhere((v) => v.name == st,
          orElse: () => throw FormatException('campo "status" inválido: $st')),
      resolvedAt: jDateOrNull(j, 'resolvedAt'),
      resolvedBy: jStrOrNull(j, 'resolvedBy'),
      foundBin: jStrOrNull(j, 'foundBin'),
      resolutionReason: jStrOrNull(j, 'resolutionReason'),
      resolutionNote: jStrOrNull(j, 'resolutionNote'),
    );
  }
}
