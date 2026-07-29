import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/task_model.dart';

/// Хранилище задач.
///
/// Тот же подход, что у Treasury: Hive-бокс + `revision`, чтобы открытые
/// экраны обновлялись без ручного дёргания (вкладки живут в IndexedStack и
/// сами по себе не пересоздаются).
class TaskService {
  static const String _boxName = 'wesios_tasks';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Box<TaskModel>? _box;

  Future<Box<TaskModel>> get _tasksBox async {
    _box ??= await Hive.openBox<TaskModel>(_boxName);
    return _box!;
  }

  Future<List<TaskModel>> getAll() async {
    final box = await _tasksBox;
    final list = box.values.toList();
    // Сортировка по порядку внутри колонки, затем по дате создания —
    // так новые задачи не прыгают в середину списка.
    list.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  Future<List<TaskModel>> byStatus(TaskStatus status) async {
    final all = await getAll();
    return all.where((t) => t.status == status).toList();
  }

  Future<void> save(TaskModel task) async {
    final box = await _tasksBox;
    await box.put(task.id, task);
    revision.value++;
  }

  Future<void> delete(String id) async {
    final box = await _tasksBox;
    await box.delete(id);
    revision.value++;
  }

  /// Переносит задачу в другую колонку, ставя её в конец.
  Future<void> move(TaskModel task, TaskStatus to) async {
    if (task.status == to) return;
    final inTarget = await byStatus(to);
    final nextOrder =
        inTarget.isEmpty ? 0 : inTarget.map((t) => t.order).reduce((a, b) => a > b ? a : b) + 1;
    await save(task.copyWith(status: to, order: nextOrder));
  }

  /// Задачи со сроком в указанный день — то, что календарь показывает
  /// в ячейке даты. Завершённые не выбрасываем: в календаре полезно видеть,
  /// что на этот день что-то было и оно сделано.
  Future<List<TaskModel>> dueOn(DateTime day) async {
    final all = await getAll();
    return all.where((t) {
      final d = t.dueDate;
      if (d == null) return false;
      return d.year == day.year && d.month == day.month && d.day == day.day;
    }).toList();
  }

  /// Ближайшие незавершённые задачи со сроком — для карточки на главной.
  /// Просроченные идут первыми: они и есть самое срочное.
  Future<List<TaskModel>> upcoming({int limit = 3}) async {
    final all = await getAll();
    final withDue = all
        .where((t) => t.dueDate != null && t.status != TaskStatus.done)
        .toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    return withDue.take(limit).toList();
  }

  /// Активные задачи без срока — показываем, когда со сроками ничего нет,
  /// иначе карточка на главной выглядит пустой при полной доске.
  Future<List<TaskModel>> activeWithoutDue({int limit = 3}) async {
    final all = await getAll();
    return all
        .where((t) => t.dueDate == null && t.status != TaskStatus.done)
        .take(limit)
        .toList();
  }

  /// Все дни, на которые назначены задачи — календарю нужно, чтобы
  /// проставить точки под датами, не перечитывая бокс на каждую ячейку.
  Future<Map<DateTime, List<TaskModel>>> byDueDay() async {
    final all = await getAll();
    final map = <DateTime, List<TaskModel>>{};
    for (final t in all) {
      final d = t.dueDate;
      if (d == null) continue;
      final key = DateTime(d.year, d.month, d.day);
      (map[key] ??= []).add(t);
    }
    return map;
  }

  /// Сводка для дашборда: сколько задач в каждой колонке и сколько просрочено.
  Future<TaskSummary> summary() async {
    final all = await getAll();
    return TaskSummary(
      total: all.length,
      byStatus: {
        for (final s in TaskStatus.values)
          s: all.where((t) => t.status == s).length,
      },
      overdue: all.where((t) => t.isOverdue).length,
      dueToday: all.where((t) => t.isDueToday).length,
    );
  }
}

class TaskSummary {
  final int total;
  final Map<TaskStatus, int> byStatus;
  final int overdue;
  final int dueToday;

  const TaskSummary({
    required this.total,
    required this.byStatus,
    required this.overdue,
    required this.dueToday,
  });
}
