/// Abreviaturas es_PR (fijas para que el demo sea determinista).
const _months = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sept', 'oct', 'nov', 'dic',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// "15 sept 2026"
String fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// "15 sept · 09:00"
String fmtDateTime(DateTime d) =>
    '${d.day} ${_months[d.month - 1]} · ${_two(d.hour)}:${_two(d.minute)}';

/// "11:00 p. m." (reloj de 12 horas, como se usa en Puerto Rico).
String fmtTime(int hour, int minute) {
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$h12:${_two(minute)} ${hour < 12 ? 'a. m.' : 'p. m.'}';
}

const _weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

/// "jueves 15 oct, 11:00 p. m."
String fmtWeekdayDateTime(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}, ${fmtTime(d.hour, d.minute)}';

/// "1.2 MB" / "340 KB"
String fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Número con separador de miles.
String fmtInt(int n) {
  final neg = n < 0;
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return neg ? '-$buf' : buf.toString();
}

/// Iniciales para avatar.
String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}

/// Quita acentos comunes del español.
String stripAccents(String s) {
  const from = 'ÁÉÍÓÚÜÑáéíóúüñ';
  const to = 'AEIOUUNaeiouun';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}
