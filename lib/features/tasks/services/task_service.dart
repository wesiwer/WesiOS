import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../organizations/services/organization_context.dart';
import '../../team/services/team_service.dart';
import '../models/task_model.dart';
import 'task_assignment.dart';

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
    list.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  Future<List<TaskModel>> getForOrganizations(Set<String> organizationIds) async {
    final all = await getAll();
    return all
        .where((task) => organizationIds.contains(task.effectiveOrganizationId))
        .toList();
  }

  Future<List<TaskModel>> byStatus(TaskStatus status) async {
    final all = await getAll();
    return all.where((t) => t.status == status).toList();
  }

  Future<void> save(TaskModel task) async {
    final box = await _tasksBox;
    final allowed = TaskAssignment.coerce(task.assignee);
    final employee = allowed == null ? null : TeamService.byId(allowed);
    final orgId = task.organizationId ??
        (task.effectiveOrganizationId != 'org_wesi_beats'
            ? task.effectiveOrganizationId
            : OrganizationContext.currentOrganizationId);
    final responsible = task.responsibleEmployeeId ??
        task.effectiveResponsibleEmployeeId ??
        employee?.id;
    final tags = TaskModel.withOwnershipTags(
      task.tags,
      organizationId: orgId,
      employeeId: responsible,
    );
    final normalized = task.copyWith(
      assignee: allowed,
      clearAssignee: allowed == null,
      organizationId: orgId,
      responsibleEmployeeId: responsible,
      clearResponsibleEmployee: responsible == null,
      tags: tags,
    );
    await box.put(task.id, normalized);
    revision.value++;
  }

  Future<void> delete(String id) async {
    final box = await _tasksBox;
    await box.delete(id);
    revision.value++;
  }

  Future<void> move(TaskModel task, TaskStatus to) async {
    if (task.status == to) return;
    final inTarget = await byStatus(to);
    final nextOrder = inTarget.isEmpty
        ? 0
        : inTarget.map((t) => t.order).reduce((a, b) => a > b ? a : b) + 1;
    await save(task.copyWith(status: to, order: nextOrder));
  }

  Future<List<TaskModel>> dueOn(DateTime day) async {
    final all = await getAll();
    return all.where((t) {
      final d = t.dueDate;
      if (d == null) return false;
      return d.year == day.year && d.month == day.month && d.day == day.day;
    }).toList();
  }

  Future<List<TaskModel>> upcoming({int limit = 3}) async {
    final all = await getAll();
    final withDue = all
        .where((t) => t.dueDate != null && t.status != TaskStatus.done)
        .toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    return withDue.take(limit).toList();
  }

  Future<List<TaskModel>> activeWithoutDue({int limit = 3}) async {
    final all = await getAll();
    return all
        .where((t) => t.dueDate == null && t.status != TaskStatus.done)
        .take(limit)
        .toList();
  }

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
