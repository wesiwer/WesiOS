import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/services/recurrence.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';

void main() {
  TransactionModel tx(RecurringPeriod? period, DateTime start,
          {bool isRecurring = true}) =>
      TransactionModel(
        id: 'x',
        title: 'x',
        amount: 100,
        type: TransactionType.expense,
        date: start,
        isRecurring: isRecurring,
        recurringPeriod: period,
      );

  group('occursOn', () {
    test('до первой даты не срабатывает', () {
      final t = tx(RecurringPeriod.monthly, DateTime(2026, 3, 10));
      expect(Recurrence.occursOn(t, DateTime(2026, 2, 10)), isFalse);
      expect(Recurrence.occursOn(t, DateTime(2026, 3, 10)), isTrue);
    });

    test('ежедневный — каждый день после начала', () {
      final t = tx(RecurringPeriod.daily, DateTime(2026, 1, 1));
      expect(Recurrence.occursOn(t, DateTime(2026, 7, 17)), isTrue);
    });

    test('еженедельный — только в тот же день недели', () {
      final t = tx(RecurringPeriod.weekly, DateTime(2026, 7, 1));
      expect(Recurrence.occursOn(t, DateTime(2026, 7, 8)), isTrue);
      expect(Recurrence.occursOn(t, DateTime(2026, 7, 9)), isFalse);
    });

    test('еженедельный переживает перевод часов', () {
      // Полгода недельных выплат: если считать разницу на местных датах,
      // сутки в 23 или 25 часов дают шесть дней вместо семи, и платёж
      // «пропадает» начиная с ближайшего перевода стрелок.
      final t = tx(RecurringPeriod.weekly, DateTime(2026, 1, 4));
      for (var week = 0; week < 26; week++) {
        final day = DateTime(2026, 1, 4).add(Duration(days: week * 7));
        final aligned = DateTime(day.year, day.month, day.day);
        expect(Recurrence.occursOn(t, aligned), isTrue,
            reason: 'неделя $week — $aligned');
      }
    });

    test('ежемесячный — в своё число', () {
      final t = tx(RecurringPeriod.monthly, DateTime(2026, 1, 18));
      expect(Recurrence.occursOn(t, DateTime(2026, 7, 18)), isTrue);
      expect(Recurrence.occursOn(t, DateTime(2026, 7, 17)), isFalse);
    });

    test('ежемесячный 31-го в коротком месяце — в последний день', () {
      final t = tx(RecurringPeriod.monthly, DateTime(2026, 1, 31));
      expect(Recurrence.occursOn(t, DateTime(2026, 6, 30)), isTrue);
      expect(Recurrence.occursOn(t, DateTime(2026, 2, 28)), isTrue);
      expect(Recurrence.occursOn(t, DateTime(2026, 7, 1)), isFalse);
    });

    test('годовой — только в свой месяц', () {
      final t = tx(RecurringPeriod.yearly, DateTime(2020, 1, 18));
      expect(Recurrence.occursOn(t, DateTime(2026, 1, 18)), isTrue);
      expect(Recurrence.occursOn(t, DateTime(2026, 7, 18)), isFalse);
    });

    test('нерегулярная операция и операция без периода не повторяются', () {
      expect(
        Recurrence.occursOn(
            tx(RecurringPeriod.daily, DateTime(2026, 1, 1),
                isRecurring: false),
            DateTime(2026, 7, 1)),
        isFalse,
      );
      expect(
        Recurrence.occursOn(tx(null, DateTime(2026, 1, 1)), DateTime(2026, 7, 1)),
        isFalse,
      );
    });
  });

  group('nextOccurrence', () {
    test('будущая первая дата возвращается как есть', () {
      final t = tx(RecurringPeriod.monthly, DateTime(2026, 9, 1));
      expect(Recurrence.nextOccurrence(t, DateTime(2026, 7, 15)),
          DateTime(2026, 9, 1));
    });

    test('ежемесячный: сегодняшнее число считается ближайшим, а не следующим '
        'месяцем', () {
      final t = tx(RecurringPeriod.monthly, DateTime(2026, 1, 18));
      expect(Recurrence.nextOccurrence(t, DateTime(2026, 7, 18)),
          DateTime(2026, 7, 18));
    });

    test('ежемесячный: после своего числа переходит на следующий месяц', () {
      final t = tx(RecurringPeriod.monthly, DateTime(2026, 1, 18));
      expect(Recurrence.nextOccurrence(t, DateTime(2026, 7, 19)),
          DateTime(2026, 8, 18));
    });

    test('ежемесячный на границе года не улетает в тринадцатый месяц', () {
      final t = tx(RecurringPeriod.monthly, DateTime(2026, 1, 5));
      expect(Recurrence.nextOccurrence(t, DateTime(2026, 12, 20)),
          DateTime(2027, 1, 5));
    });

    test('годовой считает год, а не месяц', () {
      final t = tx(RecurringPeriod.yearly, DateTime(2020, 1, 18));
      expect(Recurrence.nextOccurrence(t, DateTime(2026, 7, 15)),
          DateTime(2027, 1, 18));
    });

    test('еженедельный доводит до ближайшего того же дня недели', () {
      final t = tx(RecurringPeriod.weekly, DateTime(2026, 7, 1));
      expect(Recurrence.nextOccurrence(t, DateTime(2026, 7, 3)),
          DateTime(2026, 7, 8));
    });

    test('без периода — null, а не догадка', () {
      expect(
        Recurrence.nextOccurrence(
            tx(null, DateTime(2026, 1, 1)), DateTime(2026, 7, 1)),
        isNull,
      );
    });

    test('occursOn и nextOccurrence согласованы между собой', () {
      // Расхождение здесь означало бы, что календарь и уведомления называют
      // разные даты для одного и того же платежа.
      for (final period in RecurringPeriod.values) {
        final t = tx(period, DateTime(2026, 1, 18));
        final next = Recurrence.nextOccurrence(t, DateTime(2026, 7, 15));
        expect(next, isNotNull, reason: '$period');
        expect(Recurrence.occursOn(t, next!), isTrue, reason: '$period → $next');
      }
    });
  });
}
