import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../organizations/models/organization_access_grant.dart';
import '../../organizations/services/organization_access_service.dart';
import '../../organizations/services/organization_context.dart';
import '../../organizations/services/organization_service.dart';
import '../../team/models/team_permissions.dart';
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

  bool _taskModuleAllowed() {
    final current = TeamService.current;
    return current == null ||
        current.isOwner ||
        current.permissions.allows(TeamModules.tasks);
  }

  bool _canManagePeople() {
    final current = TeamService.current;
    if (current == null || current.isOwner) return true;
    return current.permissions.canManageTeam ||
        current.permissions.canAssignTasks ||
        current.permissions.canSeeOthersStats;
  }

  bool _belongsToCurrentEmployee(TaskModel task) {
    final current = TeamService.current;
    if (current == null || current.isOwner) return true;
    return task.assignee == current.id ||
        task.effectiveResponsibleEmployeeId == current.id;
  }

  Future<Set<String>> _allowedOrganizationIds() async {
    if (!_taskModuleAllowed()) return <String>{};
    final requested = await OrganizationContext.effectiveOrganizationIds();
    final current = TeamService.current;
    if (current == null || current.isOwner) return requested;
    final visible = await OrganizationAccessService.organizationIdsFor(
      OrganizationPermissions.view,
      employeeId: current.id,
    );
    return requested.intersection(visible);
  }

  Future<List<TaskModel>> getAllRaw() async {
    final box = await _tasksBox;
    final list = box.values.toList();
    list.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  Future<List<TaskModel>> getAll() async {
    final ids = await _allowedOrganizationIds();
    if (ids.isEmpty) return const <TaskModel>[];
    final manager = _canManagePeople();
    final all = await getAllRaw();
    return all
        .where((task) =>
            ids.contains(task.effectiveOrganizationId) &&
            (manager || _belongsToCurrentEmployee(task)))
        .toList();
  }

  Future<List<TaskModel>> getForOrganizations(Set<String> organizationIds) async {
    final allowed = await _allowedOrganizationIds();
    final ids = organizationIds.intersection(allowed);
    if (ids.isEmpty) return const <TaskModel>[];
    final manager = _canManagePeople();
    final all = await getAllRaw();
    return all
        .where((task) =>
            ids.contains(task.effectiveOrganizationId) &&
            (manager || _belongsToCurrentEmployee(task)))
        .toList();
  }

  Future<List<TaskModel>> byStatus(TaskStatus status) async {
    final all = await getAll();
    return all.where((t) => t.status == status).toList();
  }

  Future<void> _requireWritableTask(
    TaskModel normalized, {
    TaskModel? before,
  }) async {
    final current = TeamService.current;
    if (current == null || current.isOwner) return;
    if (!current.permissions.allows(TeamModules.tasks)) {
      throw StateError('tasks module access required');
    }

    final allowedIds = await _allowedOrganizationIds();
    if (!allowedIds.contains(normalized.effectiveOrganizationId)) {
      throw StateError('task organization access denied');
    }
    if (before != null &&
        !allowedIds.contains(before.effectiveOrganizationId)) {
      throw StateError('existing task organization access denied');
    }

    if (_canManagePeople()) return;

    if (before != null && !_belongsToCurrentEmployee(before)) {
      throw StateError('task belongs to another employee');
    }
    final targetAssignee = normalized.assignee;
    final targetResponsible = normalized.effectiveResponsibleEmployeeId;
    if ((targetAssignee != null && targetAssignee != current.id) ||
        (targetResponsible != null && targetResponsible != current.id)) {
      throw StateError('cannot assign task to another employee');
    }
  }

  Future<void> save(TaskModel task) async {
    final box = await _tasksBox;
    final before = box.get(task.id);
    final allowedAssignee = TaskAssignment.coerce(task.assignee);
    final employee = allowedAssignee == null
        ? null
        : TeamService.byId(allowedAssignee);
    final current = TeamService.current;
    final orgId = task.organizationId ??
        (before?.effectiveOrganizationId ??
            (task.effectiveOrganizationId.isNotEmpty
                ? task.effectiveOrganizationId
                : OrganizationContext.currentOrganizationId));
    final org = await OrganizationService.byId(orgId);
    if (org == null || org.archived) {
      throw StateError('task organization unavailable');
    }

    String? responsible = task.responsibleEmployeeId ??
        task.effectiveResponsibleEmployeeId ??
        employee?.id ??
        before?.effectiveResponsibleEmployeeId;
    if (before == null &&
        current != null &&
        !current.isOwner &&
        !_canManagePeople()) {
      responsible ??= current.id;
    }

    final tags = TaskModel.withOwnershipTags(
      task.tags,
      organizationId: orgId,
      employeeId: responsible,
    );
    final normalized = task.copyWith(
      assignee: allowedAssignee,
      clearAssignee: allowedAssignee == null,
      organizationId: orgId,
      responsibleEmployeeId: responsible,
      clearResponsibleEmployee: responsible == null,
      tags: tags,
    );

    await _requireWritableTask(normalized, before: before);
    await box.put(task.id, normalized);
    revision.value++;
  }

  Future<void> delete(String id) async {
    final box = await _tasksBox;
    final before = box.get(id);
    if (before == null) return;
    await _requireWritableTask(before, before: before);
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
