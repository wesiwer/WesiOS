import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/calendar_days.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';
import 'package:wesios/features/treasury/services/payment_calendar.dart';

void main() {
  group('производственный календарь', () {
    test('новогодние каникулы — нерабочие', () {
      for (var day = 1; day <= 8; day++) {
        expect(PaymentCalendar.isNonWorking(DateTime(2026, 1, day)), isTrue,
            reason: '$day января');
      }
      expect(PaymentCalendar.isNonWorking(DateTime(2026, 1, 9)), isFalse,
          reason: '9 января 2026 — пятница, рабочий день');
    });

    test('праздники статьи 112 распознаются в любом году', () {
      for (final year in [2026, 2027, 2030]) {
        expect(PaymentCalendar.isHoliday(DateTime(year, 3, 8)), isTrue);
        expect(PaymentCalendar.isHoliday(DateTime(year, 5, 9)), isTrue);
        expect(PaymentCalendar.isHoliday(DateTime(year, 11, 4)), isTrue);
        expect(PaymentCalendar.isHoliday(DateTime(year, 7, 15)), isFalse);
      }
    });

    test('списание уезжает вперёд, зарплата — назад', () {
      // 3 января 2026 — суббота, посреди каникул.
      final holiday = DateTime(2026, 1, 3);
      expect(PaymentCalendar.settle(holiday, PaymentShift.forward),
          DateTime(2026, 1, 9),
          reason: 'аренда спишется в первый рабочий день после каникул');
      expect(PaymentCalendar.settle(holiday, PaymentShift.backward),
          DateTime(2025, 12, 31),
          reason: 'зарплата по ТК выплачивается накануне');
      expect(PaymentCalendar.settle(holiday, PaymentShift.none), holiday);
    });

    test('намерение платежа читается по названию', () {
      expect(PaymentCalendar.shiftFor(title: 'Зарплата за январь'),
          PaymentShift.backward);
      expect(PaymentCalendar.shiftFor(title: 'Аренда офиса'),
          PaymentShift.forward);
      expect(PaymentCalendar.shiftFor(title: 'Налог УСН'),
          PaymentShift.forward);
      expect(PaymentCalendar.shiftFor(title: 'Снял наличные'),
          PaymentShift.none);
    });

    test('рабочие дни считаются, а не угадываются', () {
      // 1–11 января 2026: каникулы по 8-е, 9-е пятница, 10–11 выходные.
      expect(
        PaymentCalendar.workingDaysBetween(
            DateTime(2026, 1, 1), DateTime(2026, 1, 11)),
        1,
      );
    });
  });

  group('прогноз учитывает календарь', () {
    test('аренда 3 января попадает в прогноз девятым, а не третьим', () {
      final today = DateTime(2025, 12, 30);
      final rent = TransactionModel(
        id: 'rent',
        title: 'Аренда офиса',
        amount: 50000,
        type: TransactionType.expense,
        date: DateTime(2025, 12, 3),
        category: 'Аренда',
        isRecurring: true,
        recurringPeriod: RecurringPeriod.monthly,
      );
      final history = <TransactionModel>[
        rent,
        for (var i = 1; i <= 60; i++)
          TransactionModel(
            id: 'e$i',
            title: 'Расход $i',
            amount: 1000,
            type: TransactionType.expense,
            date: addDays(today, -i),
          ),
        for (var i = 1; i <= 60; i++)
          TransactionModel(
            id: 'in$i',
            title: 'Приход $i',
            amount: 2000,
            type: TransactionType.income,
            date: addDays(today, -i),
          ),
      ];

      final r = ForecastEngine.generate(
        transactions: history,
        currentBalance: 300000,
        days: 30,
        asOf: today,
      );

      // День 4 — это 3 января, день 10 — 9 января.
      final onThird = r.committedNetByDay[3];
      final onNinth = r.committedNetByDay[9];
      expect(onThird, 0,
          reason: '3 января банк ничего не спишет — это каникулы');
      expect(onNinth, lessThan(-40000),
          reason: 'аренда обязана приехать в первый рабочий день: '
              'третьего $onThird, девятого $onNinth');
    });
  });
}
