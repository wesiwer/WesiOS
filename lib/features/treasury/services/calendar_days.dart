/// Работа с датами по календарю, а не по часам.
///
/// `DateTime` в Dart — местное время, и разница между двумя полуночами
/// измеряется в часах. В стране с переводом часов сутки бывают длиной 23 или
/// 25 часов, поэтому `to.difference(from).inDays` там врёт:
///
/// ```
/// // Europe/Berlin, весенний перевод в ночь на 29 марта
/// DateTime(2026, 3, 30).difference(DateTime(2026, 3, 28)).inDays  // 1, не 2
/// ```
///
/// Для прогноза это не мелочь. Смещение в днях — то, чем адресуются все
/// будущие платежи: один потерянный день сдвигает всю сетку, регулярные
/// списания приезжают на сутки раньше, а два соседних дня истории
/// схлопываются в одну ячейку, оставляя следующую пустой.
///
/// Здесь дни считаются как дни: только год, месяц и число, без часов.
library;

/// Полночь того же дня.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Сколько календарных дней от [from] до [to]. Отрицательно, если [to] раньше.
///
/// Считается через UTC: там сутки всегда ровно 24 часа, а сама дата от
/// перевода часов не зависит — меняется только длина местных суток.
int dayDiff(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// Дата через [days] календарных дней от [d].
///
/// `d.add(Duration(days: n))` прибавляет часы, и в день перевода стрелок
/// возвращает 23:00 предыдущего дня либо 01:00 следующего.
DateTime addDays(DateTime d, int days) {
  final utc = DateTime.utc(d.year, d.month, d.day).add(Duration(days: days));
  return DateTime(utc.year, utc.month, utc.day);
}

/// Тот же календарный день?
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
