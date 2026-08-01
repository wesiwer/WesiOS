import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'models/task_model.dart';

/// Подписи и цвета для задач — в одном месте, чтобы доска, диалог и
/// карточка не расходились в формулировках и оттенках.
class TaskLabels {
  const TaskLabels._();

  static String status(TaskStatus s, bool ru) => switch (s) {
        TaskStatus.backlog => ru ? 'Бэклог' : 'Backlog',
        TaskStatus.inProgress => ru ? 'В работе' : 'In progress',
        TaskStatus.review => ru ? 'На проверке' : 'Review',
        TaskStatus.done => ru ? 'Готово' : 'Done',
      };

  static IconData statusIcon(TaskStatus s) => switch (s) {
        TaskStatus.backlog => Icons.inbox,
        TaskStatus.inProgress => Icons.play_circle_outline,
        TaskStatus.review => Icons.rate_review_outlined,
        TaskStatus.done => Icons.check_circle_outline,
      };

  static String priority(TaskPriority p, bool ru) => switch (p) {
        TaskPriority.low => ru ? 'Низкий' : 'Low',
        TaskPriority.normal => ru ? 'Обычный' : 'Normal',
        TaskPriority.high => ru ? 'Высокий' : 'High',
        TaskPriority.urgent => ru ? 'Срочно' : 'Urgent',
      };

  static Color priorityColor(TaskPriority p) => switch (p) {
        TaskPriority.low => AppTheme.textMuted,
        TaskPriority.normal => Color(0xFF38BDF8),
        TaskPriority.high => AppTheme.accentOrange,
        TaskPriority.urgent => AppTheme.accentRed,
      };

  static String date(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }

  /// Короткая подпись срока: «сегодня», «завтра», «просрочено N дн.» —
  /// по голой дате оценить срочность на доске тяжелее.
  static String dueLabel(DateTime due, bool ru) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(due.year, due.month, due.day);
    final diff = target.difference(today).inDays;

    if (diff == 0) return ru ? 'сегодня' : 'today';
    if (diff == 1) return ru ? 'завтра' : 'tomorrow';
    if (diff == -1) return ru ? 'вчера' : 'yesterday';
    if (diff < 0) {
      return ru ? 'просрочено ${-diff} дн.' : '${-diff}d overdue';
    }
    if (diff <= 7) return ru ? 'через $diff дн.' : 'in ${diff}d';
    return date(due);
  }
}
