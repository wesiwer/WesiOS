import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/calendar_days.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';
import 'package:wesios/features/treasury/services/recurring_engine.dart';

/// Даты повторов и границы горизонта — то, что нельзя проверить глазами на
/// графике, но именно от них зависят все числа прогноза.
void main() {
  TransactionModel tx({
    required String id,
    required double amount,
    required TransactionType type,
    required DateTime date,
    RecurringPeriod? period,
    DateTime? anchor,
  }) =>
      TransactionModel(
        id: id,
        title: id,
        amount: amount,
        type: type,
        date: date,
        isRecurring: period != null,
        recurringPeriod: period,
        recurringAnchor: anchor,
      );

  group('даты повторов', () {
    test('платёж 31-го числа не съезжает после короткого месяца', () {
      final anchor = DateTime(2026, 1, 31);
      final days = [
        for (var i = 1; i <= 12; i++)
          RecurringEngine.occurrence(anchor, RecurringPeriod.monthly, i).day
      ];
      expect(
        days,
        [28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31, 31],
        reason: 'февраль прижимает дату к 28-му, но март обязан вернуть 31-е',
      );
    });

    test('30-е число переживает февраль', () {
      final anchor = DateTime(2026, 1, 30);
      final days = [
        for (var i = 1; i <= 3; i++)
          RecurringEngine.occurrence(anchor, RecurringPeriod.monthly, i).day
      ];
      expect(days, [28, 30, 30]);
    });

    test('ежемесячный платёж наступает двенадцать раз в год', () {
      final map = RecurringEngine.projectFutureContributions(
        [
          tx(
            id: 'rent',
            amount: 1000,
            type: TransactionType.expense,
            date: DateTime(2025, 12, 31),
            period: RecurringPeriod.monthly,
          )
        ],
        days: 365,
        from: DateTime(2026, 1, 1),
      );
      expect(map.length, 12);
      expect(map.values.every((v) => v == -1000), isTrue);
    });

    test('прогноз считает от якоря, а не от даты последнего списания', () {
      // Так выглядит запись после того, как февральский платёж уже прошёл.
      final map = RecurringEngine.projectFutureContributions(
        [
          tx(
            id: 'rent',
            amount: 1000,
            type: TransactionType.expense,
            date: DateTime(2026, 2, 28),
            anchor: DateTime(2026, 1, 31),
            period: RecurringPeriod.monthly,
          )
        ],
        days: 40,
        from: DateTime(2026, 3, 1),
      );
      final dates = map.keys.map((o) => addDays(DateTime(2026, 3, 1), o)).toList();
      expect(dates, [DateTime(2026, 3, 31)],
          reason: 'мартовский платёж — 31-го, а не 28-го');
    });

    test('далёкий якорь не упирается в ограничитель', () {
      final next = RecurringEngine.nextOccurrenceAfter(
        DateTime(1996, 1, 1),
        RecurringPeriod.daily,
        DateTime(2026, 3, 1),
      );
      expect(next, DateTime(2026, 3, 2));
    });
  });

  group('границы горизонта', () {
    List<TransactionModel> history(DateTime today) => [
          for (var i = 0; i < 40; i++)
            tx(
              id: 'h\$i',
              amount: 100,
              type: TransactionType.income,
              date: addDays(today, -(i + 1)),
            ),
        ];

    test('событие ровно на последний день горизонта учитывается', () {
      final today = DateTime(2026, 3, 1);
      final withEvent = ForecastEngine.generate(
        transactions: history(today),
        currentBalance: 0,
        days: 30,
        asOf: today,
        whatIf: WhatIfScenario(
          events: [
            WhatIfEvent(
              title: 'бонус',
              amount: 100000,
              type: TransactionType.income,
              date: addDays(today, 30),
            ),
          ],
        ),
      );
      final plain = ForecastEngine.generate(
        transactions: history(today),
        currentBalance: 0,
        days: 30,
        asOf: today,
      );
      expect(withEvent.p50.last - plain.p50.last, closeTo(100000, 1));
    });

    test('операция, датированная будущим, приходит в свой день', () {
      final today = DateTime(2026, 3, 1);
      final txs = [
        ...history(today),
        tx(
          id: 'аванс',
          amount: 50000,
          type: TransactionType.income,
          date: addDays(today, 10),
        ),
      ];
      final r = ForecastEngine.generate(
        transactions: txs,
        currentBalance: 0,
        days: 30,
        asOf: today,
      );
      final jump = r.p50[9] - r.p50[8];
      expect(jump, greaterThan(40000),
          reason: 'деньги обязаны появиться на своей дате, а не в первый день');
    });
  });
}
