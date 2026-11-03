/// Lectura estricta de data.json: un campo obligatorio que falta o no tiene el tipo esperado
/// lanza [FormatException], para que un archivo dañado se detecte y nunca se sobrescriba.
library;

Never _bad(String key, Object? v) => throw FormatException('campo "$key" inválido: $v');

String jStr(Map j, String key) {
  final v = j[key];
  return v is String ? v : _bad(key, v);
}

String? jStrOrNull(Map j, String key) {
  final v = j[key];
  return v == null || v is String ? v as String? : _bad(key, v);
}

int jInt(Map j, String key) {
  final v = j[key];
  return v is num ? v.toInt() : _bad(key, v);
}

int? jIntOrNull(Map j, String key) {
  final v = j[key];
  return v == null ? null : (v is num ? v.toInt() : _bad(key, v));
}

bool jBool(Map j, String key, {bool fallback = false}) {
  final v = j[key];
  return v == null ? fallback : (v is bool ? v : _bad(key, v));
}

DateTime jDate(Map j, String key) {
  final v = j[key];
  return (v is String ? DateTime.tryParse(v) : null) ?? _bad(key, v);
}

DateTime? jDateOrNull(Map j, String key) => j[key] == null ? null : jDate(j, key);

List<Map<String, dynamic>> jList(Map j, String key) {
  final v = j[key];
  if (v is! List) _bad(key, v);
  return [for (final e in v) e is Map ? Map<String, dynamic>.from(e) : _bad(key, e)];
}

List<String> jStrings(Map j, String key) {
  final v = j[key];
  if (v == null) return [];
  if (v is! List) _bad(key, v);
  return [for (final e in v) e is String ? e : _bad(key, e)];
}
