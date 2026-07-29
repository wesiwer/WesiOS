import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/home/services/alert_service.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';

void main() {
  final now = DateTime(2026, 7, 15, 12);

  TaskModel task(
    String title, {
    DateTime? due,
    TaskStatus status = TaskStatus.backlog,
  }) =>
      TaskModel(
        id: title,
        title: title,
        createdAt: now,
        dueDate: due,
        status: status,
      );

  TransactionModel recurring(
    String title,
    RecurringPeriod period,
    DateTime start, {
    double amount = 1000,
  }) =>
      TransactionModel(
        id: title,
        title: title,
        amount: amount,
        type: TransactionType.expense,
        date: start,
        isRecurring: true,
        recurringPeriod: period,
      );

  List<Alert> compute({
    List<TransactionModel> transactions = const [],
    List<TaskModel> tasks = const [],
    double balance = 100000,
    bool shieldConfigured = true,
    String? updateVersion,
  }) =>
      AlertService.compute(
        transactions: transactions,
        tasks: tasks,
        balance: balance,
        now: now,
        shieldConfigured: shieldConfigured,
        updateVersion: updateVersion,
      );

  group('пустое состояние', () {
    test('когда всё в порядке — уведомлений нет', () {
      expect(compute(), isEmpty);
    });
  });

  group('задачи', () {
    test('просроченная задача даёт уведомление уровня danger', () {
      final alerts = compute(tasks: [task('Отчёт', due: DateTime(2026, 7, 10))]);
      expect(alerts.single.level, AlertLevel.danger);
      expect(alerts.single.route, '/tasks');
    });

    test('завершённая задача с прошедшим сроком не считается просроченной — '
        'иначе список краснел бы от уже сделанного', () {
      final alerts = compute(tasks: [
        task('Отчёт', due: DateTime(2026, 7, 10), status: TaskStatus.done),
      ]);
      expect(alerts, isEmpty);
    });

    test('срок сегодня — предупреждение, а не тревога', () {
      final alerts = compute(tasks: [task('Созвон', due: DateTime(2026, 7, 15))]);
      expect(alerts.single.level, AlertLevel.warning);
    });

    test('далёкий срок не тревожит', () {
      final alerts = compute(tasks: [task('Ревизия', due: DateTime(2026, 9, 1))]);
      expect(alerts, isEmpty);
    });

    test('срок через три дня попадает в «ближайшие», через четыре — нет', () {
      expect(
        compute(tasks: [task('X', due: DateTime(2026, 7, 18))]),
        isNotEmpty,
      );
      expect(
        compute(tasks: [task('X', due: DateTime(2026, 7, 19))]),
        isEmpty,
      );
    });
  });

  group('регулярные платежи', () {
    test('ежемесячный платёж 20-го числа виден за три дня', () {
      final alerts = compute(
        transactions: [
          recurring('Аренда', RecurringPeriod.monthly, DateTime(2026, 1, 18)),
        ],
      );
      expect(alerts.single.title, contains('Скоро списания'));
    });

    test('ежемесячный платёж 1-го числа сейчас не тревожит', () {
      final alerts = compute(
        transactions: [
          recurring('Хостинг', RecurringPeriod.monthly, DateTime(2026, 1, 1)),
        ],
      );
      expect(alerts, isEmpty);
    });

    test('годовой платёж срабатывает в свой месяц, а не в любой', () {
      // Платёж 18 января. В июле до него далеко: помесячный перебор ошибочно
      // нашёл бы «18 июля» и предупредил бы о списании, которого не будет.
      final alerts = compute(
        transactions: [
          recurring('Домен', RecurringPeriod.yearly, DateTime(2020, 1, 18)),
        ],
      );
      expect(alerts, isEmpty);
    });

    test('годовой платёж в текущем месяце всё же виден', () {
      final alerts = compute(
        transactions: [
          recurring('Лицензия', RecurringPeriod.yearly, DateTime(2020, 7, 17)),
        ],
      );
      expect(alerts.single.title, contains('Скоро списания'));
    });

    test('платёж 31-го числа в коротком месяце не проскакивает мимо', () {
      // Июнь заканчивается 30-м. Без поправки дата уехала бы на 1 июля.
      final alerts = AlertService.compute(
        transactions: [
          recurring('Кредит', RecurringPeriod.monthly, DateTime(2026, 1, 31)),
        ],
        tasks: const [],
        balance: 100000,
        now: DateTime(2026, 6, 29, 12),
      );
      expect(alerts.single.title, contains('Скоро списания'));
    });

    test('когда на счету меньше суммы списаний — уровень поднимается', () {
      final alerts = compute(
        transactions: [
          recurring('Аренда', RecurringPeriod.monthly, DateTime(2026, 1, 18),
              amount: 50000),
        ],
        balance: 1000,
      );
      expect(alerts.single.level, AlertLevel.danger);
    });

    test('регулярный доход не выдаётся за предстоящее списание', () {
      final income = TransactionModel(
        id: 'i',
        title: 'Зарплата',
        amount: 5000,
        type: TransactionType.income,
        date: DateTime(2026, 1, 18),
        isRecurring: true,
        recurringPeriod: RecurringPeriod.monthly,
      );
      expect(compute(transactions: [income]), isEmpty);
    });

    test('регулярный платёж без периода молчит, а не угадывает', () {
      final broken = TransactionModel(
        id: 'b',
        title: 'Непонятно что',
        amount: 100,
        type: TransactionType.expense,
        date: DateTime(2026, 1, 18),
        isRecurring: true,
      );
      expect(compute(transactions: [broken]), isEmpty);
    });
  });

  group('прочее', () {
    test('отрицательный баланс — danger', () {
      final alerts = compute(balance: -500);
      expect(alerts.single.level, AlertLevel.danger);
      expect(alerts.single.route, '/treasury');
    });

    test('выключенная защита ведёт в Wesi Shield', () {
      final alerts = compute(shieldConfigured: false);
      expect(alerts.single.route, '/shield');
    });

    test('обновление — информационное, не тревога', () {
      final alerts = compute(updateVersion: '1.2.3');
      expect(alerts.single.level, AlertLevel.info);
      expect(alerts.single.detail, contains('1.2.3'));
    });
  });

  group('порядок', () {
    test('срочное идёт первым независимо от порядка проверок', () {
      final alerts = compute(
        tasks: [task('Просрочено', due: DateTime(2026, 7, 1))],
        updateVersion: '1.2.3',
        shieldConfigured: false,
      );
      expect(alerts.first.level, AlertLevel.danger);
      expect(alerts.last.level, AlertLevel.info);
    });

    test('при равном уровне порядок стабилен между вызовами', () {
      List<String> run() => compute(
            tasks: [
              task('A', due: DateTime(2026, 7, 1)),
            ],
            balance: -1,
          ).map((a) => a.title).toList();
      expect(run(), run());
    });
  });
}
