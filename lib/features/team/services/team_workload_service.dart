import '../../tasks/models/task_model.dart';
import '../models/employee_model.dart';

class TeamWorkloadSnapshot {
  final double points;
  final double capacity;
  final double ratio;
  final double minRatio;
  final double maxRatio;
  final int activeTasks;
  final int overdueTasks;
  final int recentlyCompleted;

  const TeamWorkloadSnapshot({
    required this.points,
    required this.capacity,
    required this.ratio,
    required this.minRatio,
    required this.maxRatio,
    required this.activeTasks,
    required this.overdueTasks,
    required this.recentlyCompleted,
  });

  bool get underloaded => ratio < minRatio;
  bool get overloaded => ratio > maxRatio || overdueTasks >= 3;
  bool get balanced => !underloaded && !overloaded;

  String get status {
    if (overloaded) return 'Переработка';
    if (underloaded) return 'Недозагрузка';
    return 'Нагрузка в норме';
  }
}

class TeamWorkloadAlert {
  final String employeeId;
  final String employeeName;
  final bool overloaded;
  final double ratio;
  final int overdueTasks;
  final String recipientMode;

  const TeamWorkloadAlert({
    required this.employeeId,
    required this.employeeName,
    required this.overloaded,
    required this.ratio,
    required this.overdueTasks,
    required this.recipientMode,
  });

  String get message {
    final percent = (ratio * 100).round();
    if (overloaded) {
      final overdue = overdueTasks > 0 ? ', просрочено: $overdueTasks' : '';
      return '$employeeName перегружен: $percent% от рекомендуемой нагрузки$overdue.';
    }
    return '$employeeName недозагружен: $percent% от рекомендуемой нагрузки.';
  }
}

class TeamWorkloadService {
  TeamWorkloadService._();

  static TeamWorkloadSnapshot calculate(
    EmployeeModel employee,
    List<TaskModel> tasks, {
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final weekStart = clock.subtract(const Duration(days: 7));
    var points = 0.0;
    var active = 0;
    var overdue = 0;
    var done = 0;

    for (final task in tasks) {
      if (task.effectiveResponsibleEmployeeId != employee.id) continue;
      if (task.status == TaskStatus.done) {
        if (!task.createdAt.isBefore(weekStart)) {
          done++;
          points += .55 * _priorityWeight(task.priority);
        }
        continue;
      }

      active++;
      points += _statusWeight(task.status) * _priorityWeight(task.priority);
      if (task.isOverdue) {
        overdue++;
        points += .65;
      }
    }

    final capacity = employee.weeklyCapacityPoints <= 0
        ? 10.0
        : employee.weeklyCapacityPoints;
    return TeamWorkloadSnapshot(
      points: points,
      capacity: capacity,
      ratio: points / capacity,
      minRatio: employee.workloadMinRatio,
      maxRatio: employee.workloadMaxRatio,
      activeTasks: active,
      overdueTasks: overdue,
      recentlyCompleted: done,
    );
  }

  static List<TeamWorkloadAlert> alertsForViewer({
    required EmployeeModel viewer,
    required List<EmployeeModel> employees,
    required List<TaskModel> tasks,
    DateTime? now,
  }) {
    final result = <TeamWorkloadAlert>[];
    final clock = now ?? DateTime.now();
    for (final employee in employees) {
      if (employee.id == viewer.id || employee.isOwner) continue;
      if (clock.difference(employee.createdAt).inDays < 5) continue;
      if (!_canReceive(viewer, employee)) continue;
      final snapshot = calculate(employee, tasks, now: clock);
      if (!snapshot.overloaded && !snapshot.underloaded) continue;
      result.add(TeamWorkloadAlert(
        employeeId: employee.id,
        employeeName: employee.displayName,
        overloaded: snapshot.overloaded,
        ratio: snapshot.ratio,
        overdueTasks: snapshot.overdueTasks,
        recipientMode: employee.workloadAlertTarget,
      ));
    }
    result.sort((a, b) {
      if (a.overloaded != b.overloaded) return a.overloaded ? -1 : 1;
      return b.ratio.compareTo(a.ratio);
    });
    return result;
  }

  static bool _canReceive(EmployeeModel viewer, EmployeeModel employee) {
    switch (employee.workloadAlertTarget) {
      case 'off':
        return false;
      case 'ceo':
        return viewer.isOwner;
      case 'both':
        return viewer.isOwner || employee.managerEmployeeId == viewer.id;
      case 'manager':
      default:
        if (employee.managerEmployeeId == null ||
            employee.managerEmployeeId!.isEmpty) {
          return viewer.isOwner;
        }
        return employee.managerEmployeeId == viewer.id;
    }
  }

  static double _statusWeight(TaskStatus status) => switch (status) {
        TaskStatus.inProgress => 1.35,
        TaskStatus.review => 1.05,
        TaskStatus.backlog => .75,
        TaskStatus.done => .55,
      };

  static double _priorityWeight(TaskPriority priority) => switch (priority) {
        TaskPriority.urgent => 1.55,
        TaskPriority.high => 1.30,
        TaskPriority.normal => 1.0,
        TaskPriority.low => .75,
      };
}
