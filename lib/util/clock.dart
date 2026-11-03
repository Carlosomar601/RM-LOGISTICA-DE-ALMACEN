/// Modo demostración (desarrollo y pruebas): la fecha "hoy" es fija y los datos de ejemplo
/// tienen edades estables. En un PC instalado (hay config.json) `main` lo apaga y se usa
/// la fecha real.
bool demoMode = true;

final _demoToday = DateTime(2026, 9, 15, 9, 0);

/// Fecha "hoy": fija en modo demostración; la real en un PC instalado.
/// Toda edad y fecha se calcula contra este valor.
DateTime get kToday => demoMode ? _demoToday : DateTime.now();

/// Devuelve kToday menos [n] días (a la hora indicada, por defecto 09:00).
DateTime daysAgo(int n, {int hour = 9, int minute = 0}) {
  final t = kToday;
  return DateTime(t.year, t.month, t.day - n, hour, minute);
}

/// Días completos transcurridos entre [d] y kToday (por fecha calendario).
int ageDays(DateTime d) {
  final t = kToday;
  final a = DateTime.utc(t.year, t.month, t.day);
  final b = DateTime.utc(d.year, d.month, d.day);
  return a.difference(b).inDays;
}
