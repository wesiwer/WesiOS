import '../../tasks/models/task_model.dart';
import '../../treasury/models/transaction_model.dart';

/// Насколько срочно. Влияет на цвет и на порядок в списке.
enum AlertLevel { info, warning, danger }

/// Одно уведомление.
class Alert {
  final AlertLevel level;
  final String title;
  final String detail;

  /// Куда вести по нажатию. null — уведомление некуда открывать.
  final String? route;

  const Alert({
    required this.level,
    required this.title,
    required this.detail,
    this.route,
  });
}

/// Что показывать в колокольчике на главной.
///
/// Все проверки — чистая функция от уже загруженных данных: так их видно
/// целиком и можно проверить тестом, не поднимая ни Hive, ни экран.
class AlertService {
  /// Порог «скоро»: платёж или срок в пределах трёх дней.
  static const int soonDays = 3;

  static List<Alert> compute({
    required List<TransactionModel> transactions,
    required List<TaskModel> tasks,
    required double balance,
    required DateTime now,
    bool russian = true,
    bool shieldConfigured = true,
    String? updateVersion,
  }) {
    final alerts = <Alert>[];
    final today = DateTime(now.year, now.month, now.day);

    // ---- обновление
    if (updateVersion != null) {
      alerts.add(Alert(
        level: AlertLevel.info,
        title: russian ? 'Доступно обновление' : 'Update available',
        detail: russian
            ? 'Версия $updateVersion уже вышла'
            : 'Version $updateVersion is out',
        route: '/settings',
      ));
    }

    // ---- защита
    if (!shieldConfigured) {
      alerts.add(Alert(
        level: AlertLevel.warning,
        title: russian ? 'Защита не включена' : 'Protection is off',
        detail: russian
            ? 'Любой, кто взял устройство, видит финансы и ключи'
            : 'Anyone holding the device sees finances and keys',
        route: '/shield',
      ));
    }

    // ---- баланс
    if (balance < 0) {
      alerts.add(Alert(
        level: AlertLevel.danger,
        title: russian ? 'Баланс ушёл в минус' : 'Balance is negative',
        detail: russian
            ? 'Расходы превысили поступления'
            : 'Spending has outrun income',
        route: '/treasury',
      ));
    }

    // ---- задачи
    //
    // Сроки считаются от переданного `now`, а не через TaskModel.isOverdue:
    // те геттеры смотрят на системные часы, и функция, объявленная чистой,
    // молча зависела бы от момента вызова.
    int? daysUntilDue(TaskModel t) {
      final due = t.dueDate;
      if (due == null || t.status == TaskStatus.done) return null;
      return DateTime(due.year, due.month, due.day).difference(today).inDays;
    }

    final overdue = tasks.where((t) {
      final d = daysUntilDue(t);
      return d != null && d < 0;
    }).toList();
    if (overdue.isNotEmpty) {
      alerts.add(Alert(
        level: AlertLevel.danger,
        title: russian
            ? 'Просрочено задач: ${overdue.length}'
            : 'Overdue tasks: ${overdue.length}',
        detail: overdue.take(3).map((t) => t.title).join(' · '),
        route: '/tasks',
      ));
    }

    final dueToday = tasks.where((t) => daysUntilDue(t) == 0).toList();
    if (dueToday.isNotEmpty) {
      alerts.add(Alert(
        level: AlertLevel.warning,
        title: russian
            ? 'Сегодня к сроку: ${dueToday.length}'
            : 'Due today: ${dueToday.length}',
        detail: dueToday.take(3).map((t) => t.title).join(' · '),
        route: '/tasks',
      ));
    }

    final soon = tasks.where((t) {
      final d = daysUntilDue(t);
      return d != null && d > 0 && d <= soonDays;
    }).toList();
    if (soon.isNotEmpty) {
      alerts.add(Alert(
        level: AlertLevel.info,
        title: russian
            ? 'Ближайшие сроки: ${soon.length}'
            : 'Deadlines soon: ${soon.length}',
        detail: soon.take(3).map((t) => t.title).join(' · '),
        route: '/tasks',
      ));
    }

    // ---- регулярные платежи
    //
    // Считаем по дню месяца: регулярный платёж хранится одной записью с датой
    // первого списания, а не списком будущих копий, поэтому «когда следующий»
    // выводится из неё, а не читается готовым.
    final upcoming = <TransactionModel>[];
    for (final t in transactions) {
      if (!t.isRecurring || t.type != TransactionType.expense) continue;
      final next = _nextOccurrence(t, today);
      if (next == null) continue;
      final diff = next.difference(today).inDays;
      if (diff >= 0 && diff <= soonDays) upcoming.add(t);
    }
    if (upcoming.isNotEmpty) {
      final sum = upcoming.fold<double>(0, (s, t) => s + t.amount);
      alerts.add(Alert(
        level: balance < sum ? AlertLevel.danger : AlertLevel.warning,
        title: russian
            ? 'Скоро списания: ${upcoming.length}'
            : 'Upcoming charges: ${upcoming.length}',
        detail: upcoming.take(3).map((t) => t.title).join(' · '),
        route: '/treasury/operations',
      ));
    }

    // ---- аномалии
    final anomalies = transactions.where((t) => t.isAnomaly).toList();
    if (anomalies.isNotEmpty) {
      alerts.add(Alert(
        level: AlertLevel.warning,
        title: russian
            ? 'Необычные операции: ${anomalies.length}'
            : 'Unusual operations: ${anomalies.length}',
        detail: anomalies.take(3).map((t) => t.title).join(' · '),
        route: '/treasury/operations',
      ));
    }

    // Сортировка по важности устойчива: при равном уровне порядок остаётся
    // тем, в каком проверки перечислены выше.
    const weight = {
      AlertLevel.danger: 0,
      AlertLevel.warning: 1,
      AlertLevel.info: 2,
    };
    final indexed = alerts.asMap().entries.toList()
      ..sort((a, b) {
        final byLevel =
            weight[a.value.level]!.compareTo(weight[b.value.level]!);
        return byLevel != 0 ? byLevel : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
  }

  /// Ближайшая дата списания регулярного платежа, начиная с `from`.
  ///
  /// Возвращает null для периодов, которые не заданы: угадывать за
  /// пользователя, каждый ли это месяц, — значит однажды напугать его
  /// списанием, которого не будет.
  static DateTime? _nextOccurrence(TransactionModel t, DateTime from) {
    final period = t.recurringPeriod;
    if (period == null) return null;
    final start = DateTime(t.date.year, t.date.month, t.date.day);
    if (!start.isBefore(from)) return start;

    switch (period) {
      case RecurringPeriod.daily:
        return from;
      case RecurringPeriod.weekly:
        final days = from.difference(start).inDays;
        return from.add(Duration(days: (7 - days % 7) % 7));
      case RecurringPeriod.monthly:
        // Начинаем с текущего месяца: платёж мог быть ещё впереди в нём.
        for (var i = 0; i <= 1; i++) {
          final date = _clampToMonth(from.year, from.month + i, start.day);
          if (!date.isBefore(from)) return date;
        }
        return _clampToMonth(from.year, from.month + 2, start.day);
      case RecurringPeriod.yearly:
        // Годовой платёж повторяется в свой месяц, а не в любой: перебираем
        // годы, месяц берём из исходной даты.
        for (var i = 0; i <= 1; i++) {
          final date =
              _clampToMonth(from.year + i, start.month, start.day);
          if (!date.isBefore(from)) return date;
        }
        return _clampToMonth(from.year + 2, start.month, start.day);
    }
  }

  /// Дата с поправкой на короткие месяцы: платёж 31-го в феврале должен стать
  /// 28-м (или 29-м), а не уехать на 3 марта.
  static DateTime _clampToMonth(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day > lastDay ? lastDay : day);
  }
}
