import 'package:hive/hive.dart';

part 'task_model.g.dart';

/// Колонка канбан-доски.
@HiveType(typeId: 10)
enum TaskStatus {
  @HiveField(0)
  backlog,
  @HiveField(1)
  inProgress,
  @HiveField(2)
  review,
  @HiveField(3)
  done,
}

/// Приоритет задачи.
@HiveType(typeId: 11)
enum TaskPriority {
  @HiveField(0)
  low,
  @HiveField(1)
  normal,
  @HiveField(2)
  high,
  @HiveField(3)
  urgent,
}

/// Пункт чек-листа внутри задачи.
@HiveType(typeId: 12)
class SubTask {
  @HiveField(0)
  final String title;

  @HiveField(1)
  final bool done;

  const SubTask({required this.title, this.done = false});

  SubTask copyWith({String? title, bool? done}) =>
      SubTask(title: title ?? this.title, done: done ?? this.done);
}

@HiveType(typeId: 13)
class TaskModel {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String? description;

  @HiveField(3)
  final TaskStatus status;

  @HiveField(4)
  final TaskPriority priority;

  @HiveField(5)
  final DateTime createdAt;

  /// Срок. null — задача без дедлайна.
  @HiveField(6)
  final DateTime? dueDate;

  @HiveField(7)
  final String? assignee;

  @HiveField(8)
  final List<SubTask> subtasks;

  @HiveField(9)
  final List<String> tags;

  /// Порядок внутри колонки — чтобы перетаскивание сохранялось.
  @HiveField(10)
  final int order;

  const TaskModel({
    required this.id,
    required this.title,
    this.description,
    this.status = TaskStatus.backlog,
    this.priority = TaskPriority.normal,
    required this.createdAt,
    this.dueDate,
    this.assignee,
    this.subtasks = const [],
    this.tags = const [],
    this.order = 0,
  });

  /// Просрочена ли задача. Завершённые не считаются просроченными, даже
  /// если срок прошёл, — иначе доска краснеет от уже сделанного.
  bool get isOverdue {
    if (dueDate == null || status == TaskStatus.done) return false;
    final now = DateTime.now();
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    final today = DateTime(now.year, now.month, now.day);
    return due.isBefore(today);
  }

  /// Срок сегодня.
  bool get isDueToday {
    if (dueDate == null || status == TaskStatus.done) return false;
    final now = DateTime.now();
    return dueDate!.year == now.year &&
        dueDate!.month == now.month &&
        dueDate!.day == now.day;
  }

  double get checklistProgress {
    if (subtasks.isEmpty) return 0;
    return subtasks.where((s) => s.done).length / subtasks.length;
  }

  TaskModel copyWith({
    String? title,
    String? description,
    TaskStatus? status,
    TaskPriority? priority,
    DateTime? dueDate,
    bool clearDueDate = false,
    String? assignee,
    // По образцу clearDueDate: без явного флага исполнителя можно только
    // заменить, но не снять — `assignee ?? this.assignee` вернёт прежнего.
    bool clearAssignee = false,
    List<SubTask>? subtasks,
    List<String>? tags,
    int? order,
  }) {
    return TaskModel(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      createdAt: createdAt,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      assignee: clearAssignee ? null : (assignee ?? this.assignee),
      subtasks: subtasks ?? this.subtasks,
      tags: tags ?? this.tags,
      order: order ?? this.order,
    );
  }
}
