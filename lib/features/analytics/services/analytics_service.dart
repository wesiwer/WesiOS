import '../../tasks/models/task_model.dart';
import '../../tasks/services/task_service.dart';
import '../../treasury/models/transaction_model.dart';
import '../../treasury/services/treasury_service.dart';

/// Один месяц в разрезе денег.
class MonthPoint {
  final DateTime month;
  final double income;
  final double expense;

  const MonthPoint({
    required this.month,
    required this.income,
    required this.expense,
  });

  double get net => income - expense;
}

/// Показатель со сравнением к предыдущему периоду.
///
/// Голое число почти ничего не говорит: «300 000 за месяц» — это много или
/// мало? Смысл появляется только рядом с тем, что было в прошлом периоде.
class Kpi {
  final double value;
  final double previous;

  const Kpi(this.value, this.previous);

  double get delta => value - previous;

  /// Относительное изменение. null — сравнивать не с чем (в прошлом периоде
  /// был ноль), и рисовать «+∞ %» честнее не показывать вовсе.
  double? get changeFraction {
    if (previous == 0) return null;
    return (value - previous) / previous.abs();
  }

  bool get isUp => delta > 0;
}

/// Полная сводка для вкладки «Аналитика».
class AnalyticsSnapshot {
  final Kpi income;
  final Kpi expense;
  final Kpi net;
  final Kpi operations;

  /// Помесячная динамика за выбранный горизонт.
  final List<MonthPoint> months;

  /// Топ категорий расходов и доходов за период.
  final List<MapEntry<String, double>> topExpenseCategories;
  final List<MapEntry<String, double>> topIncomeCategories;

  /// Средний чек: сколько в среднем приносит одна операция дохода.
  final double averageIncomeTicket;

  /// Средние расходы в день за период — база для «на сколько хватит денег».
  final double burnPerDay;

  /// На сколько дней хватит текущего баланса при нынешнем темпе трат.
  /// null — расходов нет или они перекрыты доходами.
  final int? runwayDays;

  /// Задачи: сделано за период, просрочено, доля выполнения.
  final int tasksDone;
  final int tasksOverdue;
  final int tasksTotal;

  final DateTime from;
  final DateTime to;
  final bool isEmpty;

  const AnalyticsSnapshot({
    required this.income,
    required this.expense,
    required this.net,
    required this.operations,
    required this.months,
    required this.topExpenseCategories,
    required this.topIncomeCategories,
    required this.averageIncomeTicket,
    required this.burnPerDay,
    required this.runwayDays,
    required this.tasksDone,
    required this.tasksOverdue,
    required this.tasksTotal,
    required this.from,
    required this.to,
    this.isEmpty = false,
  });

  double get taskCompletion =>
      tasksTotal == 0 ? 0 : tasksDone / tasksTotal;

  static AnalyticsSnapshot empty(DateTime from, DateTime to) =>
      AnalyticsSnapshot(
        income: const Kpi(0, 0),
        expense: const Kpi(0, 0),
        net: const Kpi(0, 0),
        operations: const Kpi(0, 0),
        months: const [],
        topExpenseCategories: const [],
        topIncomeCategories: const [],
        averageIncomeTicket: 0,
        burnPerDay: 0,
        runwayDays: null,
        tasksDone: 0,
        tasksOverdue: 0,
        tasksTotal: 0,
        from: from,
        to: to,
        isEmpty: true,
      );
}

/// Считает сводку по всем модулям.
///
/// Чистая функция поверх уже загруженных данных: сервис ничего не рисует и
/// не лезет в Hive напрямую в [build] — это позволяет проверять расчёты
/// тестами, не поднимая UI.
class AnalyticsService {
  final TreasuryService _treasury = TreasuryService();
  final TaskService _tasks = TaskService();

  Future<AnalyticsSnapshot> build({required int periodDays}) async {
    final transactions = await _treasury.getAllTransactions();
    final tasks = await _tasks.getAll();
    return compute(
      transactions: transactions,
      tasks: tasks,
      periodDays: periodDays,
      now: DateTime.now(),
    );
  }

  /// Расчёт вынесен отдельно и принимает `now` — иначе тест зависел бы от
  /// сегодняшней даты и «протухал» бы со временем.
  static AnalyticsSnapshot compute({
    required List<TransactionModel> transactions,
    required List<TaskModel> tasks,
    required int periodDays,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final from = today.subtract(Duration(days: periodDays - 1));
    final prevFrom = from.subtract(Duration(days: periodDays));

    bool inRange(DateTime d, DateTime a, DateTime b) {
      final day = DateTime(d.year, d.month, d.day);
      return !day.isBefore(a) && !day.isAfter(b);
    }

    final current =
        transactions.where((t) => inRange(t.date, from, today)).toList();
    final previous = transactions
        .where((t) => inRange(
            t.date, prevFrom, from.subtract(const Duration(days: 1))))
        .toList();

    double sum(List<TransactionModel> rows, TransactionType type) => rows
        .where((t) => t.type == type)
        .fold<double>(0, (s, t) => s + t.amount);

    final income = sum(current, TransactionType.income);
    final expense = sum(current, TransactionType.expense);
    final prevIncome = sum(previous, TransactionType.income);
    final prevExpense = sum(previous, TransactionType.expense);

    // Помесячная динамика по всей истории в пределах периода.
    final byMonth = <DateTime, List<TransactionModel>>{};
    for (final t in current) {
      final key = DateTime(t.date.year, t.date.month);
      (byMonth[key] ??= []).add(t);
    }
    final months = byMonth.entries
        .map((e) => MonthPoint(
              month: e.key,
              income: sum(e.value, TransactionType.income),
              expense: sum(e.value, TransactionType.expense),
            ))
        .toList()
      ..sort((a, b) => a.month.compareTo(b.month));

    List<MapEntry<String, double>> topCategories(TransactionType type) {
      final map = <String, double>{};
      for (final t in current.where((t) => t.type == type)) {
        final key = (t.category == null || t.category!.trim().isEmpty)
            ? '—'
            : t.category!;
        map[key] = (map[key] ?? 0) + t.amount;
      }
      final list = map.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return list.take(5).toList();
    }

    final incomeOps =
        current.where((t) => t.type == TransactionType.income).length;

    // Баланс на конец периода — по всей истории, а не только по окну:
    // деньги, заработанные раньше, никуда не делись.
    final balance = transactions.fold<double>(
      0,
      (s, t) => t.type == TransactionType.income ? s + t.amount : s - t.amount,
    );

    final burnPerDay = expense / periodDays;
    // Runway имеет смысл, только когда траты реально превышают поступления:
    // при положительном нетто деньги не кончаются, и число дней было бы
    // выдумкой.
    final netPerDay = (income - expense) / periodDays;
    final int? runwayDays = (netPerDay < 0 && balance > 0)
        ? (balance / -netPerDay).floor()
        : null;

    final doneInPeriod = tasks
        .where((t) =>
            t.status == TaskStatus.done &&
            inRange(t.dueDate ?? t.createdAt, from, today))
        .length;

    return AnalyticsSnapshot(
      income: Kpi(income, prevIncome),
      expense: Kpi(expense, prevExpense),
      net: Kpi(income - expense, prevIncome - prevExpense),
      operations:
          Kpi(current.length.toDouble(), previous.length.toDouble()),
      months: months,
      topExpenseCategories: topCategories(TransactionType.expense),
      topIncomeCategories: topCategories(TransactionType.income),
      averageIncomeTicket: incomeOps == 0 ? 0 : income / incomeOps,
      burnPerDay: burnPerDay,
      runwayDays: runwayDays,
      tasksDone: doneInPeriod,
      tasksOverdue: tasks.where((t) => t.isOverdue).length,
      tasksTotal: tasks.length,
      from: from,
      to: today,
      isEmpty: transactions.isEmpty && tasks.isEmpty,
    );
  }
}
