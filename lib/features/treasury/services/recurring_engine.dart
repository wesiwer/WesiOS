import '../models/transaction_model.dart';

/// Общая логика регулярных платежей — используется TreasuryService,
/// SandboxService и ForecastEngine. Единая реализация гарантирует, что
/// Treasury и Sandbox ведут себя идентично.
class RecurringEngine {
  /// Один шаг вперёд на период [period] от даты [date].
  static DateTime advance(DateTime date, RecurringPeriod period) {
    switch (period) {
      case RecurringPeriod.daily:
        return date.add(const Duration(days: 1));
      case RecurringPeriod.weekly:
        return date.add(const Duration(days: 7));
      case RecurringPeriod.monthly:
        return _addMonths(date, 1);
      case RecurringPeriod.yearly:
        return _addMonths(date, 12);
    }
  }

  /// Прибавляет календарные месяцы с клампом на короткие месяцы
  /// (31.01 + 1 месяц → 28/29.02, а не перескок в март).
  static DateTime _addMonths(DateTime date, int months) {
    final totalMonths = date.month - 1 + months;
    final year = date.year + totalMonths ~/ 12;
    final month = totalMonths % 12 + 1;
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    final day = date.day > lastDayOfMonth ? lastDayOfMonth : date.day;
    return DateTime(year, month, day);
  }

  /// Первое наступление события строго после [from], начиная с [anchor].
  static DateTime nextOccurrenceAfter(
    DateTime anchor,
    RecurringPeriod period,
    DateTime from,
  ) {
    var next = anchor;
    var guard = 0;
    while (!next.isAfter(from) && guard < 10000) {
      next = advance(next, period);
      guard++;
    }
    return next;
  }

  /// true, если платёж должен был сработать к моменту [now] —
  /// т.е. с даты последнего события прошёл хотя бы один полный период.
  static bool isDue(TransactionModel tx, DateTime now) {
    final period = tx.recurringPeriod;
    if (period == null) return false;
    final due = advance(_dateOnly(tx.date), period);
    return !now.isBefore(due);
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
    final horizon = from.add(Duration(days: days));

    for (final tx in recurringTxs) {
      final period = tx.recurringPeriod;
      if (period == null) continue;
      final net = tx.type == TransactionType.income ? tx.amount : -tx.amount;

      var occurrence =
          nextOccurrenceAfter(_dateOnly(tx.date), period, from);
      var guard = 0;
      while (!occurrence.isAfter(horizon) && guard < 10000) {
        final offset = occurrence.difference(from).inDays;
        if (offset >= 1 && offset <= days) {
          result[offset] = (result[offset] ?? 0) + net;
        }
        occurrence = advance(occurrence, period);
        guard++;
      }
    }
    return result;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
