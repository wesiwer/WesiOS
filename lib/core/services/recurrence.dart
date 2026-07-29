import '../../features/treasury/models/transaction_model.dart';

/// Когда повторяется регулярная операция.
///
/// Вынесено отдельно, потому что ответ нужен в двух местах сразу: календарю —
/// «что происходит в этот день», уведомлениям — «что будет в ближайшие дни».
/// Две копии этой арифметики разошлись бы при первой же правке.
class Recurrence {
  /// Приходится ли операция на день [day].
  static bool occursOn(TransactionModel t, DateTime day) {
    final period = t.recurringPeriod;
    if (!t.isRecurring || period == null) return false;

    final start = _dayOf(t.date);
    final d = _dayOf(day);
    if (d.isBefore(start)) return false;

    switch (period) {
      case RecurringPeriod.daily:
        return true;
      case RecurringPeriod.weekly:
        return _daysBetween(start, d) % 7 == 0;
      case RecurringPeriod.monthly:
        return d.day == clampDay(d.year, d.month, start.day);
      case RecurringPeriod.yearly:
        return d.month == start.month &&
            d.day == clampDay(d.year, d.month, start.day);
    }
  }

  /// Ближайшая дата списания начиная с [from] включительно.
  ///
  /// null — период не задан. Угадывать за пользователя, каждый ли это месяц,
  /// значит однажды напугать его списанием, которого не будет.
  static DateTime? nextOccurrence(TransactionModel t, DateTime from) {
    final period = t.recurringPeriod;
    if (!t.isRecurring || period == null) return null;

    final start = _dayOf(t.date);
    final f = _dayOf(from);
    if (!start.isBefore(f)) return start;

    switch (period) {
      case RecurringPeriod.daily:
        return f;
      case RecurringPeriod.weekly:
        final rem = _daysBetween(start, f) % 7;
        return f.add(Duration(days: (7 - rem) % 7));
      case RecurringPeriod.monthly:
        // Текущий месяц проверяем первым: платёж мог быть ещё впереди в нём.
        for (var i = 0; i <= 2; i++) {
          final date = _clamped(f.year, f.month + i, start.day);
          if (!date.isBefore(f)) return date;
        }
        return _clamped(f.year, f.month + 3, start.day);
      case RecurringPeriod.yearly:
        // Годовой платёж повторяется в свой месяц, а не в любой: перебираем
        // годы, месяц берём из исходной даты.
        for (var i = 0; i <= 1; i++) {
          final date = _clamped(f.year + i, start.month, start.day);
          if (!date.isBefore(f)) return date;
        }
        return _clamped(f.year + 2, start.month, start.day);
    }
  }

  /// День месяца с поправкой на короткие месяцы: платёж 31-го в феврале —
  /// 28-е (или 29-е), а не 3 марта.
  static int clampDay(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return day > lastDay ? lastDay : day;
  }

  static DateTime _clamped(int year, int month, int day) {
    // Нормализуем месяц через конструктор: месяц 13 сам станет январём.
    final normalized = DateTime(year, month, 1);
    return DateTime(
      normalized.year,
      normalized.month,
      clampDay(normalized.year, normalized.month, day),
    );
  }

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Разница в календарных днях.
  ///
  /// Через UTC намеренно: в зоне с переводом часов сутки бывают 23 или 25
  /// часов, и `difference().inDays` на местных датах отсчитал бы шесть дней
  /// вместо семи — недельный платёж начал бы «пропадать» раз в полгода.
  static int _daysBetween(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day)
      .difference(DateTime.utc(a.year, a.month, a.day))
      .inDays;
}
