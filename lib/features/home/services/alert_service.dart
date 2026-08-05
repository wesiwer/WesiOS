import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../../core/services/recurrence.dart';
import '../../tasks/models/task_model.dart';
import '../../treasury/models/transaction_model.dart';

enum AlertLevel { info, warning, danger }

class Alert {
  final AlertLevel level;
  final String title;
  final String detail;
  final String? route;
  bool read;

  Alert({
    required this.level,
    required this.title,
    required this.detail,
    this.route,
    this.read = false,
  });
}

/// Вычисляет активные предупреждения и хранит, какие из них уже открывали.
class AlertService {
  static const int soonDays = 3;
  static const String _settingsBox = 'wesios_settings';
  static const String _readKey = 'home_alert_read_ids_v2';

  static final Set<String> _readIds = <String>{};
  static bool _readLoaded = false;
  static final unreadCount = ValueNotifier<int>(0);

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

    int? daysUntilDue(TaskModel task) {
      final due = task.dueDate;
      if (due == null || task.status == TaskStatus.done) return null;
      return DateTime(due.year, due.month, due.day).difference(today).inDays;
    }

    final overdue = tasks.where((task) {
      final days = daysUntilDue(task);
      return days != null && days < 0;
    }).toList();
    if (overdue.isNotEmpty) {
      alerts.add(Alert(
        level: AlertLevel.danger,
        title: russian
            ? 'Просрочено задач: ${overdue.length}'
            : 'Overdue tasks: ${overdue.length}',
        detail: overdue.take(3).map((task) => task.title).join(' · '),
        route: '/tasks',
      ));
    }

    final dueToday = tasks.where((task) => daysUntilDue(task) == 0).toList();
    if (dueToday.isNotEmpty) {
      alerts.add(Alert(
        level: AlertLevel.warning,
        title: russian
            ? 'Сегодня к сроку: ${dueToday.length}'
            : 'Due today: ${dueToday.length}',
        detail: dueToday.take(3).map((task) => task.title).join(' · '),
        route: '/tasks',
      ));
    }

    final soon = tasks.where((task) {
      final days = daysUntilDue(task);
      return days != null && days > 0 && days <= soonDays;
    }).toList();
    if (soon.isNotEmpty) {
      alerts.add(Alert(
        level: AlertLevel.info,
        title: russian
            ? 'Ближайшие сроки: ${soon.length}'
            : 'Deadlines soon: ${soon.length}',
        detail: soon.take(3).map((task) => task.title).join(' · '),
        route: '/tasks',
      ));
    }

    final upcoming = <TransactionModel>[];
    for (final transaction in transactions) {
      if (transaction.type != TransactionType.expense) continue;
      final next = Recurrence.nextOccurrence(transaction, today);
      if (next == null) continue;
      final difference = next.difference(today).inDays;
      if (difference >= 0 && difference <= soonDays) {
        upcoming.add(transaction);
      }
    }
    if (upcoming.isNotEmpty) {
      final sum = upcoming.fold<double>(0, (value, item) => value + item.amount);
      alerts.add(Alert(
        level: balance < sum ? AlertLevel.danger : AlertLevel.warning,
        title: russian
            ? 'Скоро списания: ${upcoming.length}'
            : 'Upcoming charges: ${upcoming.length}',
        detail: upcoming.take(3).map((item) => item.title).join(' · '),
        route: '/treasury/operations',
      ));
    }

    final anomalies = transactions.where((item) => item.isAnomaly).toList();
    if (anomalies.isNotEmpty) {
      alerts.add(Alert(
        level: AlertLevel.warning,
        title: russian
            ? 'Необычные операции: ${anomalies.length}'
            : 'Unusual operations: ${anomalies.length}',
        detail: anomalies.take(3).map((item) => item.title).join(' · '),
        route: '/treasury/operations',
      ));
    }

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
    final result = indexed.map((entry) => entry.value).toList();
    syncReadFlags(result);
    return result;
  }

  /// Стабильный идентификатор конкретного состояния предупреждения.
  /// Если число просроченных задач или версия обновления меняется, это новое
  /// уведомление и оно снова становится непрочитанным.
  static String idOf(Alert alert) =>
      '${alert.level.name}|${alert.title}|${alert.detail}|${alert.route ?? ''}';

  static int unreadOf(Iterable<Alert> alerts) =>
      alerts.where((alert) => !alert.read).length;

  /// Пометить показанный набор прочитанным.
  ///
  /// Хранилище при этом **заменяется** текущим набором, а не пополняется.
  /// Иначе отметка о пропавшем поводе живёт вечно, и вернувшаяся беда молчит:
  /// баланс ушёл в минус, уведомление прочитали, баланс выправился,
  /// уведомление исчезло — а когда счёт снова уходит в минус, отпечаток
  /// совпадает со старым, и колокольчик об этом не говорит. Такое молчание
  /// хуже лишней цифры: это ровно тот случай, ради которого колокольчик есть.
  static void markAllRead(List<Alert> alerts) {
    _ensureReadLoaded();
    final current = <String>{};
    for (final alert in alerts) {
      alert.read = true;
      current.add(idOf(alert));
    }
    _readIds
      ..clear()
      ..addAll(current);
    _persistReadIds();
    _updateUnread(alerts);
  }

  /// Только для тестов: забыть прочитанное.
  @visibleForTesting
  static void forgetRead() {
    _readLoaded = true;
    _readIds.clear();
    _persistReadIds();
    unreadCount.value = 0;
  }

  static void markRead(Alert alert, [List<Alert>? current]) {
    _ensureReadLoaded();
    alert.read = true;
    _readIds.add(idOf(alert));
    _persistReadIds();
    if (current != null) _updateUnread(current);
  }

  static void syncReadFlags(List<Alert> alerts) {
    _ensureReadLoaded();
    for (final alert in alerts) {
      alert.read = _readIds.contains(idOf(alert));
    }
    _updateUnread(alerts);
  }

  static void _ensureReadLoaded() {
    if (_readLoaded) return;
    _readLoaded = true;
    try {
      final raw = Hive.box<dynamic>(_settingsBox).get(_readKey);
      if (raw is List) {
        _readIds.addAll(raw.whereType<String>());
      }
    } catch (_) {}
  }

  static void _persistReadIds() {
    // Ограничиваем историю: устаревшие динамические уведомления больше не
    // появятся, а бесконечно растущий список имён не нужен.
    final ids = _readIds.toList();
    final kept = ids.length <= 500 ? ids : ids.sublist(ids.length - 500);
    _readIds
      ..clear()
      ..addAll(kept);
    try {
      unawaited(Hive.box<dynamic>(_settingsBox).put(_readKey, kept));
    } catch (_) {}
  }

  static void _updateUnread(List<Alert> alerts) {
    final count = unreadOf(alerts);
    if (unreadCount.value != count) unreadCount.value = count;
  }
}
