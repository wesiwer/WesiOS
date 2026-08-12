import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/calendar_days.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';

/// Если доходы сходятся с расходами, прогноз обязан идти ровно.
///
/// Это то, что человек проверяет первым: три месяца выходил в ноль — значит
/// и вперёд должно быть примерно так же. Раньше график всё равно полз вниз,
/// причём по двум независимым причинам, и обе видны только на таких данных.
void main() {
  final today = DateTime(2026, 3, 1);
  const start = 100000.0;

  TransactionModel tx(String id, double amount, TransactionType type, int daysAgo) =>
      TransactionModel(
        id: id,
        title: id,
        amount: amount,
        type: type,
        date: addDays(today, -daysAgo),
      );

  ForecastResult run(List<TransactionModel> txs, {int days = 30}) =>
      ForecastEngine.generate(
        transactions: txs,
        currentBalance: start,
        days: days,
        asOf: today,
      );

  test('доход раз в месяц, траты каждый день — линия ровная', () {
    // Так живёт большинство: зарплата раз в месяц, траты понемногу каждый
    // день. Раньше оценка «по последним дням» видела не средний доход, а
    // расстояние до последней зарплаты, и месяц спустя рисовала минус.
    final txs = <TransactionModel>[
      for (var i = 1; i <= 90; i++) tx('e$i', 1000, TransactionType.expense, i),
      for (final d in [15, 45, 75]) tx('sal$d', 30000, TransactionType.income, d),
    ];
    final r = run(txs);
    expect(r.p50.last, closeTo(start, start * 0.03),
        reason: 'за месяц баланс не должен уехать больше чем на 3%');
  });

  test('фаза месяца ничего не решает', () {
    // Один и тот же расклад, но зарплата была вчера / неделю / три недели
    // назад. Прогноз обязан выглядеть одинаково.
    final results = <double>[];
    for (final last in [1, 8, 22, 29]) {
      final txs = <TransactionModel>[
        for (var i = 1; i <= 90; i++)
          tx('e$i', 1000, TransactionType.expense, i),
        for (var k = 0; k < 3; k++)
          tx('sal$k', 30000, TransactionType.income, last + k * 30),
      ];
      results.add(run(txs).p50.last);
    }
    final spread = results.reduce((a, b) => a > b ? a : b) -
        results.reduce((a, b) => a < b ? a : b);
    expect(spread, lessThan(start * 0.05),
        reason: 'прогноз не должен зависеть от того, какое сегодня число: '
            'получилось ${results.map((v) => v.round()).toList()}');
  });

  test('доход и расход каждый день поровну — линия ровная', () {
    final txs = <TransactionModel>[
      for (var i = 1; i <= 90; i++) ...[
        tx('e$i', 1000, TransactionType.expense, i),
        tx('i$i', 1000, TransactionType.income, i),
      ],
    ];
    expect(run(txs).p50.last, closeTo(start, start * 0.01));
  });

  test('когда денег правда не хватает, прогноз идёт вниз', () {
    // Обратная проверка: движок не стал плоским на всё подряд.
    final txs = <TransactionModel>[
      for (var i = 1; i <= 90; i++) tx('e$i', 1500, TransactionType.expense, i),
      for (final d in [15, 45, 75]) tx('sal$d', 30000, TransactionType.income, d),
    ];
    final r = run(txs);
    // Теряем по 500 в день, за месяц это около 15 000.
    expect(r.p50.last, lessThan(start - 10000));
  });

  test('разовая авария не попадает в «скорее всего», но видна в худшем', () {
    final txs = <TransactionModel>[
      for (var i = 1; i <= 90; i++) ...[
        tx('e$i', 800, TransactionType.expense, i),
        tx('i$i', 1000, TransactionType.income, i),
      ],
      tx('поломка', 18000, TransactionType.expense, 40),
    ];
    final r = run(txs);
    expect(r.p50.last, greaterThan(r.p10.last),
        reason: 'плохой расклад обязан быть хуже вероятного');
  });
}
