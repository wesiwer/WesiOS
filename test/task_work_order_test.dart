import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/tasks/services/task_work_order.dart';

/// Порядок задач внутри этапа.
///
/// Порядка не было вовсе: карточки показывались так, как лежали в
/// хранилище, то есть по времени заведения. Просроченное на неделю стояло
/// вперемешку с тем, что нужно через месяц, и решать, за что взяться,
/// приходилось каждый раз заново, перечитывая весь столбец.
///
/// Одной сортировки мало. По сроку наверх всплывает мелочь с ближайшей
/// датой, по важности — важное, до которого ещё месяц. Работой управляет
/// сочетание, и здесь проверяется, что сочетание считается разумно —
/// особенно там, где две шкалы спорят между собой.
void main() {
  final now = DateTime(2026, 8, 13, 12);

  TaskModel task(
    String id, {
    int? dueInDays,
    TaskPriority priority = TaskPriority.normal,
    TaskStatus status = TaskStatus.backlog,
    int order = 0,
    DateTime? createdAt,
  }) =>
      TaskModel(
        id: id,
        title: id,
        status: status,
        priority: priority,
        createdAt: createdAt ?? DateTime(2026, 1, 1),
        dueDate: dueInDays == null ? null : now.add(Duration(days: dueInDays)),
        order: order,
      );

  List<String> order(List<TaskModel> tasks) =>
      TaskWorkOrder.sort(tasks, now: now).map((t) => t.id).toList();

  group('срочность по сроку', () {
    test('просроченное горит сильнее любого будущего срока', () {
      expect(
        TaskWorkOrder.urgency(task('a', dueInDays: -1), now: now),
        greaterThan(TaskWorkOrder.urgency(task('b', dueInDays: 0), now: now)),
      );
    });

    test('чем дольше просрочка, тем хуже', () {
      final day = TaskWorkOrder.urgency(task('a', dueInDays: -1), now: now);
      final month = TaskWorkOrder.urgency(task('b', dueInDays: -30), now: now);
      expect(month, greaterThan(day));
      expect(month, lessThanOrEqualTo(1.0));
    });

    test('срочность падает по мере отдаления срока', () {
      final values = [0, 1, 3, 7, 14, 30]
          .map((d) => TaskWorkOrder.urgency(task('t', dueInDays: d), now: now))
          .toList();
      for (var i = 1; i < values.length; i++) {
        expect(values[i], lessThan(values[i - 1]),
            reason: 'на позиции $i срочность не упала');
      }
    });

    test('ближние дни различаются сильнее дальних', () {
      // Разница между «сегодня» и «завтра» весит больше, чем между «через
      // месяц» и «через месяц и день»: именно так это ощущается в работе.
      double at(int d) => TaskWorkOrder.urgency(task('t', dueInDays: d), now: now);
      expect(at(0) - at(1), greaterThan(at(30) - at(31)));
    });

    test('задача без срока не срочна, но и не забыта', () {
      final none = TaskWorkOrder.urgency(task('a'), now: now);
      expect(none, greaterThan(0));
      expect(none, lessThan(TaskWorkOrder.urgency(task('b', dueInDays: 7), now: now)));
    });

    test('сделанное не горит', () {
      expect(
        TaskWorkOrder.urgency(
          task('a', dueInDays: -30, status: TaskStatus.done),
          now: now,
        ),
        0,
      );
    });
  });

  group('пример из жизни', () {
    test('срочное на завтра — сверху, слабое через неделю — снизу', () {
      // Дословно то, что было заказано.
      expect(
        order([
          task('через неделю и неважное',
              dueInDays: 7, priority: TaskPriority.low),
          task('завтра и срочное', dueInDays: 1, priority: TaskPriority.urgent),
          task('через три дня и важное',
              dueInDays: 3, priority: TaskPriority.high),
        ]),
        [
          'завтра и срочное',
          'через три дня и важное',
          'через неделю и неважное',
        ],
      );
    });

    test('близкая мелочь идёт раньше далёкого среднего', () {
      // Спорный на первый взгляд случай, и решён он сознательно: до задачи
      // через неделю действительно ближе, чем до задачи через месяц, и
      // сделать её придётся раньше — независимо от того, что важнее вообще.
      expect(
        order([
          task('обычное через месяц', dueInDays: 30),
          task('низкое через неделю',
              dueInDays: 7, priority: TaskPriority.low),
        ]),
        ['низкое через неделю', 'обычное через месяц'],
      );
    });

    test('при равном сроке решает важность', () {
      expect(
        order([
          task('обычное', dueInDays: 3),
          task('срочное', dueInDays: 3, priority: TaskPriority.urgent),
          task('низкое', dueInDays: 3, priority: TaskPriority.low),
          task('высокое', dueInDays: 3, priority: TaskPriority.high),
        ]),
        ['срочное', 'высокое', 'обычное', 'низкое'],
      );
    });

    test('при равной важности решает срок', () {
      expect(
        order([
          task('через месяц', dueInDays: 30),
          task('вчера', dueInDays: -1),
          task('через три дня', dueInDays: 3),
        ]),
        ['вчера', 'через три дня', 'через месяц'],
      );
    });
  });

  group('когда шкалы спорят', () {
    test('просроченная мелочь важнее срочного дела на будущий месяц', () {
      // Просроченное — это уже нарушенное обещание кому-то. «Срочно» без
      // срока — пока только мнение.
      expect(
        order([
          task('срочное через месяц',
              dueInDays: 30, priority: TaskPriority.urgent),
          task('низкое просрочено', dueInDays: -3, priority: TaskPriority.low),
        ]),
        ['низкое просрочено', 'срочное через месяц'],
      );
    });

    test('срочное на этой неделе обгоняет залежавшуюся мелочь', () {
      // Обратный случай: просрочка не превращает низкий приоритет в главное
      // дело недели, если рядом лежит срочное с близким сроком.
      expect(
        order([
          task('низкое просрочено', dueInDays: -3, priority: TaskPriority.low),
          task('срочное через неделю',
              dueInDays: 7, priority: TaskPriority.urgent),
        ]),
        ['срочное через неделю', 'низкое просрочено'],
      );
    });

    test('срочное без срока не тонет', () {
      expect(
        order([
          task('обычное через месяц', dueInDays: 30),
          task('срочное без срока', priority: TaskPriority.urgent),
        ]),
        ['срочное без срока', 'обычное через месяц'],
      );
    });
  });

  group('устойчивость', () {
    test('одинаковые задачи не перескакивают сами по себе', () {
      // Без устойчивого правила равные карточки меняются местами при каждой
      // перерисовке, и список «шевелится» под рукой.
      final tasks = [
        task('второй', dueInDays: 5, order: 2),
        task('первый', dueInDays: 5, order: 1),
        task('третий', dueInDays: 5, order: 3),
      ];
      expect(order(tasks), ['первый', 'второй', 'третий']);
      expect(order(tasks), order(tasks));
    });

    test('при равном order решает время заведения', () {
      expect(
        order([
          task('поздняя', dueInDays: 5, createdAt: DateTime(2026, 5, 1)),
          task('ранняя', dueInDays: 5, createdAt: DateTime(2026, 1, 1)),
        ]),
        ['ранняя', 'поздняя'],
      );
    });

    test('исходный список не меняется', () {
      // Он приходит из хранилища: переставить его на месте значит тихо
      // поменять чужие данные.
      final source = [
        task('б', dueInDays: 30),
        task('а', dueInDays: -1),
      ];
      TaskWorkOrder.sort(source, now: now);
      expect(source.map((t) => t.id).toList(), ['б', 'а']);
    });

    test('пустой список и один элемент не ломают сортировку', () {
      expect(order(const []), isEmpty);
      expect(order([task('один')]), ['один']);
    });
  });

  group('сделанные задачи', () {
    test('в готовом этапе порядок задаёт важность, а не сгоревший срок', () {
      expect(
        order([
          task('низкое', dueInDays: -30, status: TaskStatus.done,
              priority: TaskPriority.low),
          task('срочное', dueInDays: -1, status: TaskStatus.done,
              priority: TaskPriority.urgent),
        ]),
        ['срочное', 'низкое'],
      );
    });
  });
}
