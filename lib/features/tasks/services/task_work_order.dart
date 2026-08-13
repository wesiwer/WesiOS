import 'dart:math';

import '../models/task_model.dart';

/// Порядок задач внутри этапа: сверху то, за что стоит браться сейчас.
///
/// До этого порядка не было вовсе — задачи показывались в том виде, в каком
/// лежали в хранилище, то есть по времени заведения. Список из двадцати
/// карточек в таком порядке ничего не подсказывает: просроченное на неделю
/// стоит вперемешку с тем, что нужно через месяц, и решать, за что взяться,
/// приходится каждый раз заново, перечитывая всё.
///
/// Двух отдельных сортировок — «по сроку» и «по важности» — недостаточно.
/// По сроку наверх всплывает мелочь с ближайшей датой, по важности —
/// важное, до которого ещё месяц. Работой управляет сочетание: насколько
/// горит и насколько это вообще имеет значение.
class TaskWorkOrder {
  TaskWorkOrder._();

  /// Вес срочности в общей оценке. Срочность весит больше важности, потому
  /// что важность — это мнение, а срок — обязательство перед кем-то ещё.
  static const double urgencyWeight = .58;
  static const double importanceWeight = .42;

  /// Насколько задача горит по сроку: 0 — не горит, 1 — горит сильнее всего.
  ///
  /// Просроченное всегда выше любого будущего срока: обещание уже нарушено,
  /// и каждый следующий день делает это хуже. Дальше кривая падает
  /// насыщением, а не по прямой: разница между «сегодня» и «завтра» весит
  /// больше, чем между «через месяц» и «через месяц и один день», — ровно
  /// так это ощущается в работе.
  static double urgency(TaskModel task, {DateTime? now}) {
    // Сделанное не горит. Срок у него мог быть и вчера, но это уже история.
    if (task.status == TaskStatus.done) return 0;
    final due = task.dueDate;
    // Без срока задача не срочна, но и не безразлична: её всё ещё может
    // поднять важность. Ноль означал бы «этого нет», а она есть.
    if (due == null) return .22;

    final today = _day(now ?? DateTime.now());
    final left = _day(due).difference(today).inDays;

    if (left < 0) {
      final over = -left;
      return (.90 + .10 * (1 - pow(0.5, over / 5).toDouble()))
          .clamp(0.0, 1.0)
          .toDouble();
    }
    return .88 * pow(0.5, left / 4.5).toDouble();
  }

  /// Насколько задача важна сама по себе, безотносительно срока.
  static double importance(TaskModel task) => switch (task.priority) {
        TaskPriority.low => 0,
        TaskPriority.normal => .34,
        TaskPriority.high => .67,
        TaskPriority.urgent => 1,
      };

  /// Общая оценка «за это стоит взяться сейчас».
  static double score(TaskModel task, {DateTime? now}) =>
      urgency(task, now: now) * urgencyWeight +
      importance(task) * importanceWeight;

  /// Сравнение двух задач одного этапа.
  ///
  /// При равной оценке порядок берётся из поля `order`, а потом из времени
  /// заведения: одинаковые по смыслу задачи не должны переставляться местами
  /// сами по себе при каждой перерисовке.
  static int compare(TaskModel a, TaskModel b, {DateTime? now}) {
    final byScore = score(b, now: now).compareTo(score(a, now: now));
    if (byScore != 0) return byScore;
    final byOrder = a.order.compareTo(b.order);
    if (byOrder != 0) return byOrder;
    return a.createdAt.compareTo(b.createdAt);
  }

  /// Отсортированная копия. Исходный список не меняется — он приходит из
  /// хранилища, и переставлять его на месте значит тихо менять чужие данные.
  static List<TaskModel> sort(List<TaskModel> tasks, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    return [...tasks]..sort((a, b) => compare(a, b, now: clock));
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
