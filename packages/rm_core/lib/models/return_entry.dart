import 'json_util.dart';

enum ReturnStatus { porRevisar, aceptada, baja, descartada }

const kReturnStatusLabels = <ReturnStatus, String>{
  ReturnStatus.porRevisar: 'Por revisar',
  ReturnStatus.aceptada: 'Aceptada',
  ReturnStatus.baja: 'Dada de baja',
  ReturnStatus.descartada: 'Descartada',
};

/// Tipo de documento de RM (`Facturas.Transaccion`).
const kReturnDocTypeLabels = <int, String>{70: 'Devolución', 71: 'Anulación parcial'};

/// Motivos al descartar una devolución (no llegó físicamente al almacén).
const kReturnDiscardReasons = <String>[
  'No llegó al almacén',
  'No salió del almacén (venta en caja o anulada antes de piquear)',
  'Duplicada en RM',
  'Otro',
];

/// Motivo que se pone a la parte no aceptada cuando llegan menos unidades.
const kReturnShortReason = 'No llegó al almacén';

/// Motivos al dar de baja una devolución que llegó dañada.
const kReturnWriteOffReasons = <String>['Dañada', 'Defectuosa', 'Incompleta', 'Otro'];

/// Condición de la mercancía al aceptarla.
const kReturnConditions = <String>['Buena', 'Caja abierta', 'Empaque dañado'];

/// Línea de devolución o anulación detectada en RM (almacén central). No entra a inventario
/// hasta que alguien con permiso «revisar devoluciones» la acepta: entonces se crea un recibo
/// [id] tipo devolución en «Recibido sin ubicar».
class ReturnEntry {
  ReturnEntry({
    required this.id,
    required this.key,
    required this.docNumber,
    required this.docType,
    required this.docDate,
    required this.productId,
    required this.itemCode,
    required this.qty,
    required this.entryDate,
    required this.createdAt,
    this.originalInvoice = '',
    this.originalDate,
    this.customer = '',
    this.customerName = '',
    this.shipped,
    this.shipNote,
    this.rmReason = '',
    this.status = ReturnStatus.porRevisar,
    this.reviewedAt,
    this.reviewedBy,
    this.reason,
    this.note,
    this.receiptId,
  });

  /// DEV-n. El recibo que se crea al aceptarla lleva el mismo id.
  final String id;

  /// `tienda|documento|LineID`: evita importarla dos veces.
  final String key;
  final String docNumber;

  /// 70 devolución · 71 anulación parcial.
  final int docType;
  final DateTime docDate;
  final String productId;
  final String itemCode;
  int qty;

  final String originalInvoice;
  final DateTime? originalDate;
  final String customer;
  final String customerName;

  /// Unidades que el almacén piqueó para la factura original (libro de despachos).
  /// null = no se sabe (venta fuera del almacén, o anterior a los registros).
  final int? shipped;

  /// Explicación de [shipped] para la revisión.
  final String? shipNote;

  /// Motivo que trae RM, si lo guarda.
  final String rmReason;

  /// Fecha FIFO con que entrará: la de la venta original si se conoce; si no, la del documento.
  DateTime entryDate;
  final DateTime createdAt;

  ReturnStatus status;
  DateTime? reviewedAt;
  String? reviewedBy;
  String? reason;
  String? note;
  String? receiptId;

  bool get isOpen => status == ReturnStatus.porRevisar;

  String get docTypeLabel => kReturnDocTypeLabels[docType] ?? 'Transacción $docType';

  /// El libro de despachos dice que el almacén no despachó esta mercancía.
  bool get notShipped => shipped != null && shipped! <= 0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'key': key,
    'docNumber': docNumber,
    'docType': docType,
    'docDate': docDate.toIso8601String(),
    'productId': productId,
    'itemCode': itemCode,
    'qty': qty,
    'entryDate': entryDate.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    if (originalInvoice.isNotEmpty) 'originalInvoice': originalInvoice,
    if (originalDate != null) 'originalDate': originalDate!.toIso8601String(),
    if (customer.isNotEmpty) 'customer': customer,
    if (customerName.isNotEmpty) 'customerName': customerName,
    if (shipped != null) 'shipped': shipped,
    if (shipNote != null) 'shipNote': shipNote,
    if (rmReason.isNotEmpty) 'rmReason': rmReason,
    'status': status.name,
    if (reviewedAt != null) 'reviewedAt': reviewedAt!.toIso8601String(),
    if (reviewedBy != null) 'reviewedBy': reviewedBy,
    if (reason != null) 'reason': reason,
    if (note != null) 'note': note,
    if (receiptId != null) 'receiptId': receiptId,
  };

  factory ReturnEntry.fromJson(Map j) {
    final st = jStr(j, 'status');
    return ReturnEntry(
      id: jStr(j, 'id'),
      key: jStr(j, 'key'),
      docNumber: jStr(j, 'docNumber'),
      docType: jInt(j, 'docType'),
      docDate: jDate(j, 'docDate'),
      productId: jStr(j, 'productId'),
      itemCode: jStr(j, 'itemCode'),
      qty: jInt(j, 'qty'),
      entryDate: jDate(j, 'entryDate'),
      createdAt: jDate(j, 'createdAt'),
      originalInvoice: jStrOrNull(j, 'originalInvoice') ?? '',
      originalDate: jDateOrNull(j, 'originalDate'),
      customer: jStrOrNull(j, 'customer') ?? '',
      customerName: jStrOrNull(j, 'customerName') ?? '',
      shipped: jIntOrNull(j, 'shipped'),
      shipNote: jStrOrNull(j, 'shipNote'),
      rmReason: jStrOrNull(j, 'rmReason') ?? '',
      status: ReturnStatus.values.firstWhere(
        (v) => v.name == st,
        orElse: () => throw FormatException('campo "status" inválido: $st'),
      ),
      reviewedAt: jDateOrNull(j, 'reviewedAt'),
      reviewedBy: jStrOrNull(j, 'reviewedBy'),
      reason: jStrOrNull(j, 'reason'),
      note: jStrOrNull(j, 'note'),
      receiptId: jStrOrNull(j, 'receiptId'),
    );
  }
}
