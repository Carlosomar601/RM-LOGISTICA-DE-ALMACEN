/// Fecha "hoy" estática del demo. Toda edad y fecha se calcula contra este
/// valor, nunca contra DateTime.now().
final kToday = DateTime(2026, 9, 15, 9, 0);

/// Devuelve kToday menos [n] días (a la hora indicada, por defecto 09:00).
DateTime daysAgo(int n, {int hour = 9, int minute = 0}) =>
    DateTime(kToday.year, kToday.month, kToday.day - n, hour, minute);

/// Días completos transcurridos entre [d] y kToday (por fecha calendario).
int ageDays(DateTime d) {
  final a = DateTime.utc(kToday.year, kToday.month, kToday.day);
  final b = DateTime.utc(d.year, d.month, d.day);
  return a.difference(b).inDays;
}
