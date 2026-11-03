import 'json_util.dart';

/// Auditoría de canastas: el supervisor la crea (una canasta, varias o una zona),
/// el auditor cuenta a ciegas y al cerrar cada línea queda con un resultado.

enum AuditStatus { abierta, enCurso, cerrada, cancelada }

enum AuditBinStatus { pendiente, contando, contada, cerrada, cancelada }

enum AuditResult { ok, faltante, noEsta, sobrante, noRegistrado }

const kAuditResultLabels = <AuditResult, String>{
  AuditResult.ok: 'OK',
  AuditResult.faltante: 'FALTANTE',
  AuditResult.noEsta: 'NO ESTÁ',
  AuditResult.sobrante: 'SOBRANTE',
  AuditResult.noRegistrado: 'NO REGISTRADO',
};

const kAuditStatusLabels = <AuditStatus, String>{
  AuditStatus.abierta: 'Abierta',
  AuditStatus.enCurso: 'En curso',
  AuditStatus.cerrada: 'Cerrada',
  AuditStatus.cancelada: 'Cancelada',
};

const kAuditBinStatusLabels = <AuditBinStatus, String>{
  AuditBinStatus.pendiente: 'Por contar',
  AuditBinStatus.contando: 'Contando',
  AuditBinStatus.contada: 'Contada',
  AuditBinStatus.cerrada: 'Cerrada',
  AuditBinStatus.cancelada: 'Cancelada',
};

/// Motivos de una diferencia. «Otro» exige una nota.
const kReasonOther = 'Otro';
const kAuditReasons = <String>[
  'Error de piqueo',
  'Dañado',
  'Perdido',
  'En otra canasta',
  'Error de recibo',
  kReasonOther,
];

/// Motivos para dar de baja un pendiente.
const kWriteOffReasons = <String>['Dañado', 'Perdido', 'Robo', 'Vencido', kReasonOther];

T _enum<T extends Enum>(List<T> values, Map j, String key) {
  final name = jStr(j, key);
  return values.firstWhere((v) => v.name == name, orElse: () => throw FormatException('campo "$key" inválido: $name'));
}

Map<String, int> _intMap(Map j, String key) {
  final v = j[key];
  if (v == null) return {};
  if (v is! Map) throw FormatException('campo "$key" inválido: $v');
  return {
    for (final e in v.entries)
      '${e.key}': e.value is num ? (e.value as num).toInt() : throw FormatException('campo "$key" inválido'),
  };
}

Map<String, String> _strMap(Map j, String key) {
  final v = j[key];
  if (v == null) return {};
  if (v is! Map) throw FormatException('campo "$key" inválido: $v');
  return {
    for (final e in v.entries) '${e.key}': e.value is String ? e.value as String : throw FormatException('campo "$key" inválido'),
  };
}

/// Lo que el sistema tenía en la canasta al escanearla (foto).
class AuditExpected {
  AuditExpected({
    required this.invId,
    required this.productId,
    required this.qty,
    required this.lot,
    required this.entryDate,
    required this.receipt,
  });

  final String invId;
  final String productId;
  final int qty;
  final String lot;
  final DateTime entryDate;
  final String receipt;

  Map<String, dynamic> toJson() => {
        'invId': invId,
        'productId': productId,
        'qty': qty,
        'lot': lot,
        'entryDate': entryDate.toIso8601String(),
        'receipt': receipt,
      };

  factory AuditExpected.fromJson(Map j) => AuditExpected(
        invId: jStr(j, 'invId'),
        productId: jStr(j, 'productId'),
        qty: jInt(j, 'qty'),
        lot: jStr(j, 'lot'),
        entryDate: jDate(j, 'entryDate'),
        receipt: jStr(j, 'receipt'),
      );
}

/// Resultado de un producto en una canasta.
class AuditLine {
  AuditLine({
    required this.productId,
    required this.expected,
    required this.counted,
    required this.result,
    this.reason,
    this.reasonNote,
    this.matchedPendingId,
    List<String>? pendingIds,
  }) : pendingIds = pendingIds ?? [];

  final String productId;
  final int expected;
  final int counted;
  final AuditResult result;
  String? reason;
  String? reasonNote;

  /// Sobrante identificado como un pendiente abierto (se le devuelve su lote y fecha).
  String? matchedPendingId;

  /// Pendientes generados por el faltante al cerrar.
  final List<String> pendingIds;

  int get diff => counted - expected;
  bool get isOk => result == AuditResult.ok;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'expected': expected,
        'counted': counted,
        'result': result.name,
        if (reason != null) 'reason': reason,
        if (reasonNote != null) 'reasonNote': reasonNote,
        if (matchedPendingId != null) 'matchedPendingId': matchedPendingId,
        if (pendingIds.isNotEmpty) 'pendingIds': pendingIds,
      };

  factory AuditLine.fromJson(Map j) => AuditLine(
        productId: jStr(j, 'productId'),
        expected: jInt(j, 'expected'),
        counted: jInt(j, 'counted'),
        result: _enum(AuditResult.values, j, 'result'),
        reason: jStrOrNull(j, 'reason'),
        reasonNote: jStrOrNull(j, 'reasonNote'),
        matchedPendingId: jStrOrNull(j, 'matchedPendingId'),
        pendingIds: jStrings(j, 'pendingIds'),
      );
}

class AuditBin {
  AuditBin({
    required this.bin,
    required this.zone,
    this.status = AuditBinStatus.pendiente,
    this.auditor,
    this.startedAt,
    this.countedAt,
    this.closedAt,
    List<AuditExpected>? expected,
    Map<String, int>? counts,
    this.recounts,
    this.recountIds,
    Map<String, String>? notes,
    List<AuditLine>? lines,
  })  : expected = expected ?? [],
        counts = counts ?? {},
        notes = notes ?? {},
        lines = lines ?? [];

  final String bin;
  final String zone;
  AuditBinStatus status;
  String? auditor;
  DateTime? startedAt;
  DateTime? countedAt;
  DateTime? closedAt;
  List<AuditExpected> expected;

  /// Primer conteo por producto (productId → unidades).
  final Map<String, int> counts;

  /// Reconteo de las líneas que difieren (solo uno; null = no se ha hecho).
  Map<String, int>? recounts;

  /// Productos que el auditor debe recontar (se fija al terminar el primer conteo;
  /// desde ahí el primer conteo ya no se edita). null = todavía en el primer conteo.
  List<String>? recountIds;
  final Map<String, String> notes;

  /// Resultado por producto. Se calcula al terminar el conteo y se fija al cerrar.
  List<AuditLine> lines;

  /// Bloqueada para piqueo, transferencias y recibo.
  bool get locked => status == AuditBinStatus.contando || status == AuditBinStatus.contada;

  Map<String, dynamic> toJson() => {
        'bin': bin,
        'zone': zone,
        'status': status.name,
        if (auditor != null) 'auditor': auditor,
        if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
        if (countedAt != null) 'countedAt': countedAt!.toIso8601String(),
        if (closedAt != null) 'closedAt': closedAt!.toIso8601String(),
        'expected': [for (final e in expected) e.toJson()],
        'counts': counts,
        if (recounts != null) 'recounts': recounts,
        if (recountIds != null) 'recountIds': recountIds,
        if (notes.isNotEmpty) 'notes': notes,
        'lines': [for (final l in lines) l.toJson()],
      };

  factory AuditBin.fromJson(Map j) => AuditBin(
        bin: jStr(j, 'bin'),
        zone: jStrOrNull(j, 'zone') ?? '',
        status: _enum(AuditBinStatus.values, j, 'status'),
        auditor: jStrOrNull(j, 'auditor'),
        startedAt: jDateOrNull(j, 'startedAt'),
        countedAt: jDateOrNull(j, 'countedAt'),
        closedAt: jDateOrNull(j, 'closedAt'),
        expected: [for (final x in jList(j, 'expected')) AuditExpected.fromJson(x)],
        counts: _intMap(j, 'counts'),
        recounts: j['recounts'] == null ? null : _intMap(j, 'recounts'),
        recountIds: j['recountIds'] == null ? null : jStrings(j, 'recountIds'),
        notes: _strMap(j, 'notes'),
        lines: [for (final x in jList(j, 'lines')) AuditLine.fromJson(x)],
      );
}

class Audit {
  Audit({
    required this.id,
    required this.scopeLabel,
    required this.createdBy,
    required this.createdAt,
    required this.bins,
    this.assignedTo,
    this.status = AuditStatus.abierta,
    this.closedAt,
    this.closedBy,
  });

  final String id;
  final String scopeLabel;
  final String createdBy;
  final DateTime createdAt;

  /// Usuario asignado (id); null = cualquier auditor.
  String? assignedTo;
  AuditStatus status;
  DateTime? closedAt;
  String? closedBy;
  final List<AuditBin> bins;

  bool get isOpen => status == AuditStatus.abierta || status == AuditStatus.enCurso;

  AuditBin? binOf(String code) {
    for (final b in bins) {
      if (b.bin == code) return b;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'scopeLabel': scopeLabel,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        if (assignedTo != null) 'assignedTo': assignedTo,
        'status': status.name,
        if (closedAt != null) 'closedAt': closedAt!.toIso8601String(),
        if (closedBy != null) 'closedBy': closedBy,
        'bins': [for (final b in bins) b.toJson()],
      };

  factory Audit.fromJson(Map j) => Audit(
        id: jStr(j, 'id'),
        scopeLabel: jStr(j, 'scopeLabel'),
        createdBy: jStr(j, 'createdBy'),
        createdAt: jDate(j, 'createdAt'),
        assignedTo: jStrOrNull(j, 'assignedTo'),
        status: _enum(AuditStatus.values, j, 'status'),
        closedAt: jDateOrNull(j, 'closedAt'),
        closedBy: jStrOrNull(j, 'closedBy'),
        bins: [for (final x in jList(j, 'bins')) AuditBin.fromJson(x)],
      );
}
