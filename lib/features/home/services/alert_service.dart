import 'package:flutter/material.dart';
import '../../../core/services/recurrence.dart';
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

  /// Прочитано ли уведомление.
  bool read;

  Alert({
    required this.level,
    required this.title,
    required this.detail,
    this.route,
    this.read = false,
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
      if (t.type != TransactionType.expense) continue;
      final next = Recurrence.nextOccurrence(t, today);
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

  // ── Отслеживание прочитанных уведомлений ──

  static final _readIds = <String>{};
  static final unreadCount = ValueNotifier<int>(0);

  /// Уникальный ID уведомления (хеш от содержимого).
  static String _id(Alert a) => '${a.level.name}|${a.title}|${a.detail}';

  /// Пометить все текущие уведомления как прочитанные.
  static void markAllRead(List<Alert> alerts) {
    for (final a in alerts) {
      a.read = true;
      _readIds.add(_id(a));
    }
    _updateUnread(alerts);
  }

  /// Пометить одно уведомление как прочитанное.
  static void markRead(Alert alert) {
    alert.read = true;
    _readIds.add(_id(alert));
  }

  /// Обновить счётчик непрочитанных.
  static void _updateUnread(List<Alert> alerts) {
    final count = alerts.where((a) => !a.read).length;
    if (unreadCount.value != count) {
      unreadCount.value = count;
    }
  }

  /// Синхронизировать read-флаги с уже прочитанными ID.
  static void syncReadFlags(List<Alert> alerts) {
    for (final a in alerts) {
      if (_readIds.contains(_id(a))) {
        a.read = true;
      }
    }
    _updateUnread(alerts);
  }

}
