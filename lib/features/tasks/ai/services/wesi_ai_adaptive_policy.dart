import 'dart:math';

import '../../../team/models/employee_model.dart';
import '../../models/task_model.dart';
import '../models/ai_task_template.dart';

class AiCadenceSignal {
  final int effectiveDays;
  final int? learnedMedianDays;
  final int matchingTasks;
  final DateTime? latestAt;

  const AiCadenceSignal({
    required this.effectiveDays,
    this.learnedMedianDays,
    required this.matchingTasks,
    this.latestAt,
  });

  bool get learned => learnedMedianDays != null;
}

class AiEmployeeCapacitySignal {
  final int recentAssigned14;
  final int recentDone14;
  final int overdueOpen;
  final double recentIntensity7;
  final DateTime? lastAssignedAt;

  const AiEmployeeCapacitySignal({
    required this.recentAssigned14,
    required this.recentDone14,
    required this.overdueOpen,
    required this.recentIntensity7,
    required this.lastAssignedAt,
  });

  bool get underutilized =>
      recentAssigned14 <= 2 && overdueOpen == 0 && recentIntensity7 < 2.6;

  bool get fatigueRisk => recentIntensity7 >= 6.5 || overdueOpen >= 3;

  double get reliability {
    if (recentAssigned14 == 0) return .65;
    return (recentDone14 / recentAssigned14).clamp(0.0, 1.0).toDouble();
  }
}

class WesiAiAdaptivePolicy {
  WesiAiAdaptivePolicy._();

  static AiCadenceSignal cadenceFor(
    AiTaskTemplate template,
    List<TaskModel> tasks,
    DateTime now,
  ) {
    final matching = tasks
        .where((task) => _matchesTemplate(task, template))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (matching.length < 3) {
      return AiCadenceSignal(
        effectiveDays: template.cadenceDays,
        matchingTasks: matching.length,
        latestAt: matching.isEmpty ? null : matching.last.createdAt,
      );
    }

    final intervals = <int>[];
    for (var i = 1; i < matching.length; i++) {
      final days =
          matching[i].createdAt.difference(matching[i - 1].createdAt).inDays;
      if (days > 0 && days <= 120) intervals.add(days);
    }
    if (intervals.length < 2) {
      return AiCadenceSignal(
        effectiveDays: template.cadenceDays,
        matchingTasks: matching.length,
        latestAt: matching.isEmpty ? null : matching.last.createdAt,
      );
    }
    intervals.sort();
    final median = intervals.length.isOdd
        ? intervals[intervals.length ~/ 2]
        : ((intervals[intervals.length ~/ 2 - 1] +
                    intervals[intervals.length ~/ 2]) /
                2)
            .round();

    final minimum = max(
      template.minRestDays + 1,
      max(1, (template.cadenceDays * .60).round()),
    );
    final maximum = max(minimum, (template.cadenceDays * 1.80).round());
    final blended = (template.cadenceDays * .45 + median * .55).round();
    return AiCadenceSignal(
      effectiveDays: blended.clamp(minimum, maximum).toInt(),
      learnedMedianDays: median,
      matchingTasks: matching.length,
      latestAt: matching.last.createdAt,
    );
  }

  static double categoryDirectionScore(
    AiTaskCategory category,
    List<TaskModel> tasks,
    DateTime now,
    AiTaskCategory? Function(TaskModel task) categoryOfTask,
  ) {
    final start = now.subtract(const Duration(days: 90));
    var categorized = 0;
    var same = 0;
    for (final task in tasks) {
      if (task.createdAt.isBefore(start)) continue;
      final resolved = categoryOfTask(task);
      if (resolved == null) continue;
      categorized++;
      if (resolved == category) same++;
    }
    if (categorized == 0) return 0;
    return (same / categorized).clamp(0.0, 1.0).toDouble();
  }

  static double historicalRoleFit(
    EmployeeModel employee,
    AiTaskCategory category,
    List<TaskModel> tasks,
    AiTaskCategory? Function(TaskModel task) categoryOfTask,
  ) {
    var total = 0;
    var done = 0;
    for (final task in tasks) {
      if (task.effectiveResponsibleEmployeeId != employee.id) continue;
      if (categoryOfTask(task) != category) continue;
      total++;
      if (task.status == TaskStatus.done) done++;
    }
    if (total < 2) return 0;
    final completion = done / total;
    return (.62 + min(.18, total * .025) + completion * .12)
        .clamp(0.0, .92)
        .toDouble();
  }

  static AiEmployeeCapacitySignal capacityFor(
    String employeeId,
    List<TaskModel> tasks,
    DateTime now,
  ) {
    final start14 = now.subtract(const Duration(days: 14));
    final start7 = now.subtract(const Duration(days: 7));
    var assigned14 = 0;
    var done14 = 0;
    var overdue = 0;
    var intensity = 0.0;
    DateTime? latest;

    for (final task in tasks) {
      if (task.effectiveResponsibleEmployeeId != employeeId) continue;
      if (latest == null || task.createdAt.isAfter(latest))
        latest = task.createdAt;
      if (!task.createdAt.isBefore(start14)) {
        assigned14++;
        if (task.status == TaskStatus.done) done14++;
      }
      if (task.status != TaskStatus.done && task.isOverdue) overdue++;
      if (!task.createdAt.isBefore(start7)) {
        intensity += _taskIntensity(task);
      }
    }

    return AiEmployeeCapacitySignal(
      recentAssigned14: assigned14,
      recentDone14: done14,
      overdueOpen: overdue,
      recentIntensity7: intensity,
      lastAssignedAt: latest,
    );
  }

  static bool _matchesTemplate(TaskModel task, AiTaskTemplate template) {
    if (task.tags.contains('wesi-ai:template:${template.id}')) return true;
    final text = _normalize(
      '${task.title} ${task.description ?? ''} ${task.tags.join(' ')}',
    );
    var hits = 0;
    for (final keyword in template.taskKeywords) {
      if (text.contains(_normalize(keyword))) hits++;
    }
    if (template.taskKeywords.length <= 2) return hits >= 1;
    return hits >= 2;
  }

  static double _taskIntensity(TaskModel task) {
    final statusWeight = switch (task.status) {
      TaskStatus.inProgress => 1.10,
      TaskStatus.review => .90,
      TaskStatus.backlog => .65,
      TaskStatus.done => .75,
    };
    final priorityWeight = switch (task.priority) {
      TaskPriority.urgent => .75,
      TaskPriority.high => .45,
      TaskPriority.normal => .20,
      TaskPriority.low => 0,
    };
    return statusWeight + priorityWeight;
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
      .trim();
}
