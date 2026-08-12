import 'calendar_days.dart';
import '../models/transaction_model.dart';

/// Один день фактической истории баланса.
class HistoryDay {
  /// Смещение от начала окна: 0 — самый левый день, [window] — сегодня.
  final int offset;
  final DateTime date;
  final double balance;

  const HistoryDay({
    required this.offset,
    required this.date,
    required this.balance,
  });
}

/// Фактический баланс по дням — левая, «уже случившаяся» часть графика.
///
/// Вынесено из экрана: это арифметика, а не оформление, и проверять её надо
/// отдельно от виджетов. Раньше она жила внутри `_loadData`, и ошибку в ней
/// нельзя было увидеть иначе как глазами на графике.
///
/// Два правила, из-за нарушения которых история расходилась с балансом:
///
/// 1. Граница окна — календарный день. Когда «до окна» отбиралось сравнением
///    с точностью до секунды, а дни внутри окна сравнивались по календарю,
///    операция первого дня окна, совершённая раньше текущего времени суток,
///    попадала и туда, и туда — и учитывалась дважды.
///
/// 2. История заканчивается сегодняшним днём. Операции, датированные
///    будущим, в неё не входят: это ещё не факт, а план, и его место в
///    прогнозе, на своей дате.
List<HistoryDay> buildHistorySeries({
  required List<TransactionModel> transactions,
  required DateTime now,
  required int windowDays,
}) {
  final today = dateOnly(now);
  final windowStart = addDays(today, -windowDays);

  double running = 0;
  for (final tx in transactions) {
    if (dateOnly(tx.date).isBefore(windowStart)) {
      running += tx.type == TransactionType.income ? tx.amount : -tx.amount;
    }
  }

  final byOffset = List<double>.filled(windowDays + 1, 0);
  for (final tx in transactions) {
    final day = dateOnly(tx.date);
    if (day.isBefore(windowStart) || day.isAfter(today)) continue;
    final idx = dayDiff(windowStart, day);
    byOffset[idx] += tx.type == TransactionType.income ? tx.amount : -tx.amount;
  }

  final out = <HistoryDay>[];
  for (var i = 0; i <= windowDays; i++) {
    running += byOffset[i];
    out.add(HistoryDay(
      offset: i,
      date: addDays(windowStart, i),
      balance: running,
    ));
  }
  return out;
}
