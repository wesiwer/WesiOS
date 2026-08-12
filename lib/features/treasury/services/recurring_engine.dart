import 'calendar_days.dart';
import '../models/transaction_model.dart';

/// Общая логика регулярных платежей — используется TreasuryService,
/// SandboxService и ForecastEngine. Единая реализация гарантирует, что
/// Treasury и Sandbox ведут себя идентично.
class RecurringEngine {
  /// Один шаг вперёд на период [period] от даты [date].
  ///
  /// Годится, чтобы спросить «когда следующий раз». Для длинной цепочки
  /// повторов нужен [occurrence]: шаг за шагом месячная дата съезжает
  /// (см. комментарий там).
  static DateTime advance(DateTime date, RecurringPeriod period) =>
      occurrence(date, period, 1);

  /// [index]-е наступление события, считая от якоря [anchor].
  ///
  /// Считается всегда от якоря, а не шагом от предыдущей даты. Разница
  /// видна на коротких месяцах: аренда 31 января шагами превращается в
  /// 28 февраля, оттуда в 28 марта — и остаётся 28-м числом навсегда, хотя
  /// человек платит 31-го. От якоря февраль так же прижмётся к 28-му, но
  /// март вернётся на 31-е, как и должно быть.
  static DateTime occurrence(
    DateTime anchor,
    RecurringPeriod period,
    int index,
  ) {
    final base = dateOnly(anchor);
    switch (period) {
      case RecurringPeriod.daily:
        return addDays(base, index);
      case RecurringPeriod.weekly:
        return addDays(base, 7 * index);
      case RecurringPeriod.monthly:
        return _addMonths(base, index);
      case RecurringPeriod.yearly:
        return _addMonths(base, 12 * index);
    }
  }

  /// Прибавляет календарные месяцы с клампом на короткие месяцы
  /// (31.01 + 1 месяц → 28/29.02, а не перескок в март).
  static DateTime _addMonths(DateTime date, int months) {
    final totalMonths = date.month - 1 + months;
    final year = date.year + (totalMonths ~/ 12);
    final month = totalMonths % 12 + 1;
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    final day = date.day > lastDayOfMonth ? lastDayOfMonth : date.day;
    return DateTime(year, month, day);
  }

  /// Номер первого наступления строго после [from], считая от [anchor].
  ///
  /// Возвращает индекс, а не дату: с ним зовущий сам решает, сколько
  /// повторов брать, и каждое наступление по-прежнему считается от якоря.
  ///
  /// Считается формулой, а не перебором. Перебор с ограничителем на 10 000
  /// шагов на ежедневном платеже с якорем тридцатилетней давности упирался
  /// в ограничитель и возвращал дату, которая всё ещё в прошлом.
  static int firstIndexAfter(
    DateTime anchor,
    RecurringPeriod period,
    DateTime from,
  ) {
    final base = dateOnly(anchor);
    final edge = dateOnly(from);
    if (base.isAfter(edge)) return 0;

    switch (period) {
      case RecurringPeriod.daily:
        return dayDiff(base, edge) + 1;
      case RecurringPeriod.weekly:
        return dayDiff(base, edge) ~/ 7 + 1;
      case RecurringPeriod.monthly:
      case RecurringPeriod.yearly:
        final step = period == RecurringPeriod.monthly ? 1 : 12;
        var months = (edge.year - base.year) * 12 + (edge.month - base.month);
        var index = months ~/ step;
        if (index < 0) index = 0;
        // Кламп коротких месяцев сдвигает дату на день-два назад, поэтому
        // округление по номеру месяца может промахнуться в любую сторону.
        // Досчитываем по факту — это единицы шагов, а не тысячи.
        while (!occurrence(base, period, index).isAfter(edge)) {
          index++;
        }
        while (index > 0 && occurrence(base, period, index - 1).isAfter(edge)) {
          index--;
        }
        return index;
    }
  }

  /// Первое наступление события строго после [from], начиная с [anchor].
  static DateTime nextOccurrenceAfter(
    DateTime anchor,
    RecurringPeriod period,
    DateTime from,
  ) =>
      occurrence(anchor, period, firstIndexAfter(anchor, period, from));

  /// true, если платёж должен был сработать к моменту [now] —
  /// т.е. с даты последнего события прошёл хотя бы один полный период.
  static bool isDue(TransactionModel tx, DateTime now) {
    final period = tx.recurringPeriod;
    if (period == null) return false;
    final due = advance(dateOnly(tx.date), period);
    return !now.isBefore(due);
  }

  /// Все наступления события в окне `(from, from+days]`, по смещению в днях.
  ///
  /// Смещение — это 1..days, где 1 — завтра.
  static void forEachOccurrence(
    DateTime anchor,
    RecurringPeriod period, {
    required DateTime from,
    required int days,
    required void Function(int offset) onOccurrence,
  }) {
    if (days <= 0) return;
    final base = dateOnly(anchor);
    final start = dateOnly(from);
    var index = firstIndexAfter(base, period, start);
    while (true) {
      final date = occurrence(base, period, index);
      final offset = dayDiff(start, date);
      if (offset > days) break;
      if (offset >= 1) onOccurrence(offset);
      index++;
    }
  }

  /// Проецирует регулярные транзакции на дни [from+1 .. from+days] и
  /// возвращает нетто-сумму (доход +, расход −) по смещению в днях (1..days).
  /// Используется прогнозом: известные будущие платежи — не «шум», а факт.
  static Map<int, double> projectFutureContributions(
    List<TransactionModel> recurringTxs, {
    required int days,
    required DateTime from,
  }) {
    final result = <int, double>{};
    if (days <= 0) return result;

    for (final tx in recurringTxs) {
      final period = tx.recurringPeriod;
      if (period == null) continue;
      final net = tx.type == TransactionType.income ? tx.amount : -tx.amount;
      forEachOccurrence(
        // Якорь, а не сдвинутая дата: после проведения платежа date уезжает
        // на дату последнего списания, и прогноз считал бы от неё.
        tx.recurringAnchorDate,
        period,
        from: from,
        days: days,
        onOccurrence: (offset) {
          result[offset] = (result[offset] ?? 0) + net;
        },
      );
    }
    return result;
  }
}
