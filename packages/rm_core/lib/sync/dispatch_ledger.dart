import 'dart:convert';
import 'dart:io';

import 'package:riverpod/riverpod.dart';

/// Registro de una orden o factura de RM que ya entró al almacén.
class LedgerEntry {
  LedgerEntry({
    required this.created,
    required this.appId,
    Map<String, int>? picked,
    Set<String>? invoices,
  })  : picked = picked ?? {},
        invoices = invoices ?? {};

  final DateTime created;

  /// Id en la app (ORD-… / FAC-…).
  String appId;

  /// Unidades ya piqueadas por código de artículo (estable entre reinicios).
  final Map<String, int> picked;

  /// Facturas de RM enlazadas a esta orden.
  final Set<String> invoices;

  int pickedOf(String itemCode) => picked[itemCode.toLowerCase()] ?? 0;
  bool get anyPicked => picked.values.any((v) => v > 0);

  Map<String, dynamic> toJson() => {
        'created': created.toIso8601String(),
        'appId': appId,
        'picked': picked,
        'invoices': invoices.toList(),
      };

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        created: DateTime.tryParse('${j['created']}') ?? DateTime.now(),
        appId: '${j['appId'] ?? ''}',
        picked: {
          for (final e in (j['picked'] as Map? ?? {}).entries) '${e.key}': (e.value as num?)?.toInt() ?? 0,
        },
        invoices: {for (final i in (j['invoices'] as List? ?? [])) '$i'},
      );
}

/// Libro de despachos: sobrevive reinicios para que una orden ya piqueada no vuelva
/// a despacharse cuando llega su factura. Claves: `tienda|O|número` y `tienda|F|número`.
class DispatchLedger {
  DispatchLedger({this.file, this.retention = const Duration(days: 90)});

  /// null = solo en memoria (pruebas, web).
  final File? file;
  final Duration retention;
  final Map<String, LedgerEntry> _entries = {};

  static String orderKey(String storeId, String number) => '$storeId|O|$number';
  static String invoiceKey(String storeId, String number) => '$storeId|F|$number';

  LedgerEntry? order(String storeId, String number) => _entries[orderKey(storeId, number)];
  LedgerEntry? invoice(String storeId, String number) => _entries[invoiceKey(storeId, number)];

  LedgerEntry recordOrder(String storeId, String number, String appId, DateTime now) =>
      _entries.putIfAbsent(orderKey(storeId, number), () => LedgerEntry(created: now, appId: appId))..appId = appId;

  LedgerEntry recordInvoice(String storeId, String number, String appId, DateTime now) =>
      _entries.putIfAbsent(invoiceKey(storeId, number), () => LedgerEntry(created: now, appId: appId))..appId = appId;

  void addPicked(LedgerEntry e, String itemCode, int qty) {
    if (qty <= 0) return;
    final k = itemCode.toLowerCase();
    e.picked[k] = (e.picked[k] ?? 0) + qty;
  }

  int get length => _entries.length;

  /// Lee el archivo; si falta o está dañado empieza vacío.
  static DispatchLedger load(File? file, {DateTime? now}) => DispatchLedger(file: file)..reload(now: now);

  /// Vuelve a leer el archivo (p. ej. después de restaurar un respaldo).
  void reload({DateTime? now}) {
    _entries.clear();
    final f = file;
    if (f == null) return;
    try {
      if (f.existsSync()) {
        final j = jsonDecode(f.readAsStringSync());
        if (j is Map) {
          for (final e in j.entries) {
            if (e.value is Map) _entries['${e.key}'] = LedgerEntry.fromJson(Map<String, dynamic>.from(e.value as Map));
          }
        }
      }
    } catch (_) {
      _entries.clear();
    }
    prune(now ?? DateTime.now());
  }

  /// Archivo del libro en la carpeta compartida. Antes vivía en `%APPDATA%` (por cuenta de Windows):
  /// si aún no existe el compartido, se copia el anterior una sola vez.
  static File? sharedFile(Directory? sharedDir, Directory? oldUserDir) {
    if (sharedDir == null) return null;
    final f = File('${sharedDir.path}${Platform.pathSeparator}ledger.json');
    if (!f.existsSync() && oldUserDir != null) {
      final old = File('${oldUserDir.path}${Platform.pathSeparator}ledger.json');
      try {
        if (old.existsSync()) {
          sharedDir.createSync(recursive: true);
          old.copySync(f.path);
        }
      } catch (_) {}
    }
    return f;
  }

  void prune(DateTime now) => _entries.removeWhere((_, e) => now.difference(e.created) > retention);

  /// Guarda de inmediato; un error de disco no detiene la operación del almacén.
  void save() {
    final f = file;
    if (f == null) return;
    try {
      f.parent.createSync(recursive: true);
      final tmp = File('${f.path}.tmp')
        ..writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
          for (final e in _entries.entries) e.key: e.value.toJson(),
        }));
      if (f.existsSync()) f.deleteSync();
      tmp.renameSync(f.path);
    } catch (_) {}
  }
}

final ledgerProvider = Provider<DispatchLedger>((ref) => DispatchLedger());
