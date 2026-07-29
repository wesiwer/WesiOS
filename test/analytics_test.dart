import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/analytics/services/analytics_service.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';

void main() {
  // Фиксированное «сегодня»: иначе тест зависел бы от реальной даты
  // и со временем начал бы падать сам по себе.
  final now = DateTime(2026, 6, 15);

  TransactionModel tx({
    required String id,
    required double amount,
    required TransactionType type,
    required DateTime date,
    String? category,
  }) =>
      TransactionModel(
        id: id,
        title: 'op $id',
        amount: amount,
        type: type,
        date: date,
        category: category,
      );

  group('Kpi', () {
    test('reports the change relative to the previous period', () {
      const k = Kpi(150, 100);
      expect(k.delta, 50);
      expect(k.changeFraction, closeTo(0.5, 1e-9));
      expect(k.isUp, isTrue);
    });

    test('returns null instead of infinity when the previous period was zero '
        '— "+∞ %" is not a number a human can act on', () {
      const k = Kpi(150, 0);
      expect(k.changeFraction, isNull);
    });

    test('a drop against a negative baseline still compares by magnitude', () {
      const k = Kpi(-50, -100);
      expect(k.delta, 50);
      expect(k.changeFraction, closeTo(0.5, 1e-9));
    });
  });

  group('AnalyticsService.compute — periods', () {
    test('splits the window into current and previous of the same length, '
        'so the comparison is like-for-like', () {
      final rows = [
        // Текущий период (последние 30 дней).
        tx(id: 'a', amount: 1000, type: TransactionType.income,
            date: now.subtract(const Duration(days: 3))),
        // Предыдущий период (дни 31..60).
        tx(id: 'b', amount: 400, type: TransactionType.income,
            date: now.subtract(const Duration(days: 40))),
        // За пределами обоих окон — не должно попасть никуда.
        tx(id: 'c', amount: 9999, type: TransactionType.income,
            date: now.subtract(const Duration(days: 200))),
      ];

      final s = AnalyticsService.compute(
        transactions: rows,
        tasks: const [],
        periodDays: 30,
        now: now,
      );

      expect(s.income.value, 1000);
      expect(s.income.previous, 400);
    });

    test('operations are counted, not summed', () {
      final rows = List.generate(
        4,
        (i) => tx(
          id: '$i',
          amount: 100,
          type: TransactionType.expense,
          date: now.subtract(Duration(days: i + 1)),
        ),
      );
      final s = AnalyticsService.compute(
        transactions: rows,
        tasks: const [],
        periodDays: 30,
        now: now,
      );
      expect(s.operations.value, 4);
      expect(s.expense.value, 400);
    });
  });

  group('AnalyticsService.compute — runway', () {
    test('is null when income covers the spending — otherwise the app would '
        'invent a day on which money "runs out" while it is actually growing',
        () {
      final rows = [
        tx(id: 'i', amount: 5000, type: TransactionType.income,
            date: now.subtract(const Duration(days: 2))),
        tx(id: 'e', amount: 1000, type: TransactionType.expense,
            date: now.subtract(const Duration(days: 2))),
      ];
      final s = AnalyticsService.compute(
        transactions: rows,
        tasks: const [],
        periodDays: 30,
        now: now,
      );
      expect(s.runwayDays, isNull);
    });

    test('counts the days left when spending outpaces income', () {
      final rows = [
        // Большой доход в прошлом создаёт баланс.
        tx(id: 'old', amount: 60000, type: TransactionType.income,
            date: now.subtract(const Duration(days: 300))),
        // В текущем окне только траты: 3000 за 30 дней = 100/день.
        tx(id: 'e', amount: 3000, type: TransactionType.expense,
            date: now.subtract(const Duration(days: 5))),
      ];
      final s = AnalyticsService.compute(
        transactions: rows,
        tasks: const [],
        periodDays: 30,
        now: now,
      );
      // Баланс 57000 при трате 100/день.
      expect(s.burnPerDay, closeTo(100, 1e-9));
      expect(s.runwayDays, 570);
    });
  });

  group('AnalyticsService.compute — breakdowns', () {
    test('top categories are sorted by amount and capped at five', () {
      final rows = List.generate(
        8,
        (i) => tx(
          id: 'c$i',
          amount: (i + 1) * 100,
          type: TransactionType.expense,
          date: now.subtract(const Duration(days: 2)),
          category: 'cat$i',
        ),
      );
      final s = AnalyticsService.compute(
        transactions: rows,
        tasks: const [],
        periodDays: 30,
        now: now,
      );
      expect(s.topExpenseCategories.length, 5);
      expect(s.topExpenseCategories.first.key, 'cat7');
      expect(s.topExpenseCategories.first.value, 800);
    });

    test('average income ticket divides by the number of income operations, '
        'not by all operations', () {
      final rows = [
        tx(id: 'i1', amount: 1000, type: TransactionType.income,
            date: now.subtract(const Duration(days: 1))),
        tx(id: 'i2', amount: 3000, type: TransactionType.income,
            date: now.subtract(const Duration(days: 2))),
        tx(id: 'e1', amount: 500, type: TransactionType.expense,
            date: now.subtract(const Duration(days: 2))),
      ];
      final s = AnalyticsService.compute(
        transactions: rows,
        tasks: const [],
        periodDays: 30,
        now: now,
      );
      expect(s.averageIncomeTicket, 2000);
    });

    test('months come back in chronological order', () {
      final rows = [
        tx(id: 'm1', amount: 100, type: TransactionType.income,
            date: DateTime(2026, 4, 10)),
        tx(id: 'm2', amount: 200, type: TransactionType.income,
            date: DateTime(2026, 6, 1)),
        tx(id: 'm3', amount: 300, type: TransactionType.income,
            date: DateTime(2026, 5, 5)),
      ];
      final s = AnalyticsService.compute(
        transactions: rows,
        tasks: const [],
        periodDays: 120,
        now: now,
      );
      expect(s.months.map((m) => m.month.month).toList(), [4, 5, 6]);
    });
  });

  group('AnalyticsService.compute — tasks', () {
    TaskModel task({
      required String id,
      TaskStatus status = TaskStatus.backlog,
      DateTime? due,
    }) =>
        TaskModel(
          id: id,
          title: id,
          status: status,
          createdAt: DateTime(2026, 6, 1),
          dueDate: due,
        );

    test('counts finished, overdue and total separately', () {
      final tasks = [
        task(id: 'done', status: TaskStatus.done, due: DateTime(2026, 6, 10)),
        task(id: 'late', due: DateTime(2020, 1, 1)),
        task(id: 'open'),
      ];
      final s = AnalyticsService.compute(
        transactions: const [],
        tasks: tasks,
        periodDays: 30,
        now: now,
      );
      expect(s.tasksDone, 1);
      expect(s.tasksOverdue, 1);
      expect(s.tasksTotal, 3);
      expect(s.taskCompletion, closeTo(1 / 3, 1e-9));
    });

    test('completion is zero, not NaN, when there are no tasks at all', () {
      final s = AnalyticsService.compute(
        transactions: const [],
        tasks: const [],
        periodDays: 30,
        now: now,
      );
      expect(s.taskCompletion, 0);
      expect(s.isEmpty, isTrue);
    });
  });
}
