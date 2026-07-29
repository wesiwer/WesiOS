import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/anomaly_engine.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';
import 'package:wesios/features/treasury/services/recurring_engine.dart';

TransactionModel _tx({
  required String id,
  required double amount,
  required TransactionType type,
  required DateTime date,
  bool isRecurring = false,
  RecurringPeriod? recurringPeriod,
}) {
  return TransactionModel(
    id: id,
    title: id,
    amount: amount,
    type: type,
    date: date,
    isRecurring: isRecurring,
    recurringPeriod: recurringPeriod,
  );
}

void main() {
  _longHorizonTests();
  group('ForecastEngine', () {
    test('returns insufficientData with fewer than 3 transactions', () {
      final result = ForecastEngine.generate(
        transactions: [
          _tx(
            id: 'a',
            amount: 100,
            type: TransactionType.income,
            date: DateTime.now(),
          ),
        ],
        currentBalance: 1000,
        days: 10,
      );
      expect(result.insufficientData, isTrue);
      expect(result.p50, isEmpty);
    });

    test('refuses to forecast from a single day of one-off transactions '
        '(regression: one day of history produced zero volatility, so all '
        '5000 paths were identical and the chart showed a confident straight '
        'line with p10 == p50 == p90)', () {
      final today = DateTime.now();
      final anchor = DateTime(today.year, today.month, today.day);
      final txs = [
        _tx(id: 'a', amount: 43000, type: TransactionType.income, date: anchor),
        _tx(id: 'b', amount: 1400, type: TransactionType.expense, date: anchor),
        _tx(id: 'c', amount: 1300, type: TransactionType.expense, date: anchor),
      ];

      final result = ForecastEngine.generate(
        transactions: txs,
        currentBalance: 43000,
        days: 30,
      );

      expect(result.insufficientData, isTrue);
      expect(result.p50, isEmpty);
    });

    test('a short history still forecasts when recurring payments carry it — '
        'there the straight line is the correct deterministic answer, not an '
        'artefact of missing data', () {
      final today = DateTime.now();
      final anchor = DateTime(today.year, today.month, today.day);
      final txs = List.generate(
        3,
        (i) => _tx(
          id: 'daily_$i',
          amount: 100,
          type: TransactionType.income,
          date: anchor,
          isRecurring: true,
          recurringPeriod: RecurringPeriod.daily,
        ),
      );

      final result = ForecastEngine.generate(
        transactions: txs,
        currentBalance: 1000,
        days: 5,
      );

      expect(result.insufficientData, isFalse);
      expect(result.p50.first, closeTo(1300, 0.001));
    });

    test('percentiles are ordered (p10 <= p50 <= p90) for every day, '
        'and series length matches the requested horizon', () {
      final now = DateTime.now();
      final txs = <TransactionModel>[];
      for (int i = 0; i < 40; i++) {
        txs.add(_tx(
          id: 'inc_$i',
          amount: 500 + (i % 7) * 37.0,
          type: TransactionType.income,
          date: now.subtract(Duration(days: i)),
        ));
        txs.add(_tx(
          id: 'exp_$i',
          amount: 200 + (i % 5) * 23.0,
          type: TransactionType.expense,
          date: now.subtract(Duration(days: i)),
        ));
      }

      final result = ForecastEngine.generate(
        transactions: txs,
        currentBalance: 10000,
        days: 30,
      );

      expect(result.insufficientData, isFalse);
      expect(result.p10, hasLength(30));
      expect(result.p50, hasLength(30));
      expect(result.p90, hasLength(30));
      for (int i = 0; i < 30; i++) {
        expect(result.p10[i], lessThanOrEqualTo(result.p50[i] + 1e-6));
        expect(result.p50[i], lessThanOrEqualTo(result.p90[i] + 1e-6));
      }
    });

    test('deterministic recurring payments produce an exact, zero-volatility '
        'trajectory when there is no other transaction noise', () {
      final today = DateTime.now();
      final anchor = DateTime(today.year, today.month, today.day);
      // Три одинаковых ежедневных регулярных дохода — единственный источник
      // будущих денег в этом сценарии, поэтому результат обязан быть точным.
      final txs = List.generate(
        3,
        (i) => _tx(
          id: 'daily_$i',
          amount: 100,
          type: TransactionType.income,
          date: anchor,
          isRecurring: true,
          recurringPeriod: RecurringPeriod.daily,
        ),
      );

      final result = ForecastEngine.generate(
        transactions: txs,
        currentBalance: 1000,
        days: 5,
      );

      expect(result.insufficientData, isFalse);
      for (int i = 0; i < 5; i++) {
        final expected = 1000 + 300.0 * (i + 1);
        expect(result.p50[i], closeTo(expected, 0.001));
        expect(result.p10[i], closeTo(expected, 0.001));
        expect(result.p90[i], closeTo(expected, 0.001));
      }
    });

    test('Cash Gap Risk Score: a draining recurring expense trips runway and '
        'the 5% risk alert at the correct day', () {
      final today = DateTime.now();
      final anchor = DateTime(today.year, today.month, today.day);
      // Три РАЗНЫХ ежедневных расхода по 100 (минимум 3 транзакции для
      // движка), суммарно 300/день без дохода — съедают баланс 1000 ровно
      // за 4 дня: 1000 -> 700 -> 400 -> 100 -> -200.
      final txs = List.generate(
        3,
        (i) => _tx(
          id: 'burn_$i',
          amount: 100,
          type: TransactionType.expense,
          date: anchor,
          isRecurring: true,
          recurringPeriod: RecurringPeriod.daily,
        ),
      );

      final result = ForecastEngine.generate(
        transactions: txs,
        currentBalance: 1000,
        days: 10,
      );

      expect(result.runwayDays, 4);
      expect(result.riskAlertDay, 4);
      // Нулевая волатильность здесь => вероятность либо 0, либо 1.
      expect(result.belowZeroProbability[2], 0); // день 3: баланс ещё 100
      expect(result.belowZeroProbability[3], 1); // день 4: баланс -200
    });

    test('What-If: a one-off virtual event shifts the median trajectory only '
        'on and after its day, without touching the real transaction list',
        () {
      final today = DateTime.now();
      final anchor = DateTime(today.year, today.month, today.day);
      final txs = List.generate(
        3,
        (i) => _tx(
          id: 'daily_$i',
          amount: 100,
          type: TransactionType.income,
          date: anchor,
          isRecurring: true,
          recurringPeriod: RecurringPeriod.daily,
        ),
      );

      final baseline = ForecastEngine.generate(
        transactions: txs,
        currentBalance: 1000,
        days: 5,
      );

      final withEvent = ForecastEngine.generate(
        transactions: txs,
        currentBalance: 1000,
        days: 5,
        whatIf: WhatIfScenario(
          events: [
            WhatIfEvent(
              title: 'Оборудование',
              amount: 5000,
              type: TransactionType.expense,
              date: anchor.add(const Duration(days: 3)),
            ),
          ],
        ),
      );

      // До события (дни 1-2) обе траектории идентичны.
      expect(withEvent.p50[0], closeTo(baseline.p50[0], 0.001));
      expect(withEvent.p50[1], closeTo(baseline.p50[1], 0.001));
      // На день события и после — расхождение ровно на сумму события.
      expect(withEvent.p50[2], closeTo(baseline.p50[2] - 5000, 0.001));
      expect(withEvent.p50[4], closeTo(baseline.p50[4] - 5000, 0.001));
      // Реальные транзакции не переданы обратно и не мутировали список.
      expect(txs.length, 3);
    });

    test('What-If: income multiplier scales only the income stream, '
        'expenses stay untouched', () {
      final today = DateTime.now();
      final anchor = DateTime(today.year, today.month, today.day);
      final txs = [
        _tx(
          id: 'salary',
          amount: 1000,
          type: TransactionType.income,
          date: anchor,
          isRecurring: true,
          recurringPeriod: RecurringPeriod.daily,
        ),
        _tx(
          id: 'rent',
          amount: 200,
          type: TransactionType.expense,
          date: anchor,
          isRecurring: true,
          recurringPeriod: RecurringPeriod.daily,
        ),
        // Движку нужно минимум 3 транзакции, чтобы вообще строить прогноз;
        // третья регулярная запись не меняет арифметику теста.
        _tx(
          id: 'subscription',
          amount: 0,
          type: TransactionType.expense,
          date: anchor,
          isRecurring: true,
          recurringPeriod: RecurringPeriod.daily,
        ),
      ];

      final halved = ForecastEngine.generate(
        transactions: txs,
        currentBalance: 0,
        days: 3,
        whatIf: const WhatIfScenario(incomeMultiplier: 0.5),
      );

      // Доход урезан вдвое (500), расход остаётся 200 => чистое +300/день.
      for (int i = 0; i < 3; i++) {
        expect(halved.p50[i], closeTo(300.0 * (i + 1), 0.001));
      }
    });

    test('DCF discounting reduces future balances toward zero at the given '
        'annual rate, does not affect belowZeroProbability', () {
      final today = DateTime.now();
      final anchor = DateTime(today.year, today.month, today.day);
      final txs = List.generate(
        3,
        (i) => _tx(
          id: 'daily_$i',
          amount: 100,
          type: TransactionType.income,
          date: anchor,
          isRecurring: true,
          recurringPeriod: RecurringPeriod.daily,
        ),
      );

      const rate = 0.10;
      final nominal = ForecastEngine.generate(
        transactions: txs,
        currentBalance: 1000,
        days: 365,
      );
      final discounted = ForecastEngine.generate(
        transactions: txs,
        currentBalance: 1000,
        days: 365,
        annualDiscountRate: rate,
      );

      const lastDay = 364;
      const expectedFactor = 1 / (1.0 + rate); // t = 365/365 = 1 год
      expect(
        discounted.p50[lastDay],
        closeTo(nominal.p50[lastDay] * expectedFactor, 0.01),
      );
      // Дисконт не должен трогать вероятностную часть.
      expect(discounted.belowZeroProbability, nominal.belowZeroProbability);
    });
  });

  group('RecurringEngine', () {
    test('advance() clamps to the last valid day of a shorter month', () {
      final jan31 = DateTime(2026, 1, 31);
      final next = RecurringEngine.advance(jan31, RecurringPeriod.monthly);
      expect(next, DateTime(2026, 2, 28)); // 2026 — не високосный
    });

    test('advance() clamps Feb 29 forward across a non-leap year', () {
      final feb29 = DateTime(2024, 2, 29);
      final next = RecurringEngine.advance(feb29, RecurringPeriod.yearly);
      expect(next, DateTime(2025, 2, 28));
    });

    test('isDue no longer perpetually fires once the anchor is advanced '
        '(regression: old _shouldProcess compared against the original '
        'creation date forever and would refire indefinitely)', () {
      final now = DateTime.now();
      final staleAnchor = now.subtract(const Duration(days: 40));
      final tx = _tx(
        id: 't',
        amount: 1,
        type: TransactionType.expense,
        date: staleAnchor,
        isRecurring: true,
        recurringPeriod: RecurringPeriod.daily,
      );
      expect(RecurringEngine.isDue(tx, now), isTrue);

      // То, что делает processRecurringPayments после материализации платежа:
      // сдвигает якорь на дату последнего проведённого события.
      final advanced = tx.copyWith(date: now);
      expect(RecurringEngine.isDue(advanced, now), isFalse);
    });

    test('projectFutureContributions places a weekly payment exactly 7 days '
        'apart within the horizon', () {
      final today = DateTime.now();
      final from = DateTime(today.year, today.month, today.day);
      final tx = _tx(
        id: 'w',
        amount: 50,
        type: TransactionType.expense,
        date: from.subtract(const Duration(days: 3)),
        isRecurring: true,
        recurringPeriod: RecurringPeriod.weekly,
      );

      final projected = RecurringEngine.projectFutureContributions(
        [tx],
        days: 14,
        from: from,
      );

      expect(projected[4], -50); // from-3 + 7 = day offset 4
      expect(projected[11], -50); // + ещё 7 дней
      expect(projected.length, 2);
    });
  });

  group('AnomalyEngine', () {
    test('flags a large one-off expense against a stable baseline', () {
      final now = DateTime.now();
      final normal = List.generate(
        10,
        (i) => _tx(
          id: 'n_$i',
          amount: 100 + (i % 3) * 5.0,
          type: TransactionType.expense,
          date: now.subtract(Duration(days: i)),
        ),
      );
      final spike = _tx(
        id: 'spike',
        amount: 20000,
        type: TransactionType.expense,
        date: now,
      );

      final anomalies = AnomalyEngine.detect([...normal, spike]);

      expect(anomalies.map((a) => a.id), contains('spike'));
      expect(anomalies.length, 1);
    });

    test('returns nothing with fewer than 4 expenses', () {
      final now = DateTime.now();
      final txs = List.generate(
        3,
        (i) => _tx(
          id: 'e_$i',
          amount: 100.0 * (i + 1),
          type: TransactionType.expense,
          date: now.subtract(Duration(days: i)),
        ),
      );
      expect(AnomalyEngine.detect(txs), isEmpty);
    });
  });
}

void _longHorizonTests() {
  group('ForecastEngine long horizons', () {
    test('keeps the full path count on short horizons', () {
      expect(ForecastEngine.pathsForHorizon(30), ForecastEngine.defaultPaths);
      expect(ForecastEngine.pathsForHorizon(120), ForecastEngine.defaultPaths);
    });

    test('scales the path count down on multi-year horizons — cost is '
        'paths x days, and 5000 paths over five years is nine million steps, '
        'which visibly stalls a phone', () {
      final year = ForecastEngine.pathsForHorizon(365);
      final fiveYears = ForecastEngine.pathsForHorizon(1825);
      expect(year, lessThan(ForecastEngine.defaultPaths));
      expect(fiveYears, lessThan(year));
    });

    test('never drops below the floor where percentiles get noisy', () {
      expect(ForecastEngine.pathsForHorizon(100000), greaterThanOrEqualTo(800));
    });

    test('a five-year forecast still returns ordered percentiles for every '
        'day of the horizon', () {
      final now = DateTime.now();
      final txs = List.generate(
        40,
        (i) => TransactionModel(
          id: 'tx$i',
          title: 'op$i',
          amount: 1000.0 + (i % 7) * 120,
          type: i.isEven ? TransactionType.income : TransactionType.expense,
          date: now.subtract(Duration(days: 40 - i)),
        ),
      );

      final r = ForecastEngine.generate(
        transactions: txs,
        currentBalance: 50000,
        days: 1825,
      );

      expect(r.insufficientData, isFalse);
      expect(r.p50.length, 1825);
      for (var i = 0; i < r.p50.length; i++) {
        expect(r.p10[i], lessThanOrEqualTo(r.p50[i]));
        expect(r.p50[i], lessThanOrEqualTo(r.p90[i]));
      }
    });
  });
}
