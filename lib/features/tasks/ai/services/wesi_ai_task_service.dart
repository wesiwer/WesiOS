import 'package:hive_flutter/hive_flutter.dart';

import '../../../organizations/models/organization_access_grant.dart';
import '../../../organizations/services/organization_access_service.dart';
import '../../../organizations/services/organization_context.dart';
import '../../../organizations/services/organization_service.dart';
import '../../../team/services/team_service.dart';
import '../../../treasury/models/transaction_model.dart';
import '../../../treasury/services/treasury_service.dart';
import '../../models/task_model.dart';
import '../../services/task_assignment.dart';
import '../../services/task_service.dart';
import '../models/ai_task_suggestion.dart';
import 'wesi_ai_task_engine.dart';

class WesiAiTaskService {
  WesiAiTaskService._();

  static const String _memoryBoxName = 'wesios_wesi_ai_task_memory_v1';
  static const int visibleLimit = 5;

  static Future<AiTaskAnalysisResult> analyze({DateTime? now}) async {
    final clock = now ?? DateTime.now();
    final organization = await OrganizationContext.currentOrganization();
    final tasks = await TaskService().getForOrganizations({organization.id});
    final eligibleIds = await _employeeIdsForOrganization(organization.id);
    final businessSignal = await _businessSignal(clock);

    final raw = WesiAiTaskEngine.analyze(WesiAiAnalysisInput(
      tasks: tasks,
      employees: TeamService.all,
      eligibleEmployeeIds: eligibleIds,
      organizationId: organization.id,
      organizationName: organization.name,
      organizationDescription: organization.description ?? '',
      currentEmployeeId: TeamService.current?.id,
      canAssignToOthers: TaskAssignment.canAssignToOthers,
      businessSignal: businessSignal,
      now: clock,
    ));

    final box = await Hive.openBox<dynamic>(_memoryBoxName);
    final visible = <AiTaskSuggestion>[];
    for (final suggestion in raw) {
      if (await _suppressed(box, suggestion, tasks, clock)) continue;
      visible.add(suggestion);
      if (visible.length >= visibleLimit) break;
    }

    return AiTaskAnalysisResult(
      suggestions: visible,
      businessSignal: businessSignal,
      analyzedAt: clock,
    );
  }

  static Future<void> snooze(
    AiTaskSuggestion suggestion, {
    Duration duration = const Duration(days: 3),
  }) async {
    final box = await Hive.openBox<dynamic>(_memoryBoxName);
    await box.put(_decisionKey(suggestion.fingerprint), {
      'type': 'snooze',
      'until': DateTime.now().add(duration).toIso8601String(),
      'templateId': suggestion.templateId,
    });
  }

  static Future<void> reject(
    AiTaskSuggestion suggestion, {
    Duration duration = const Duration(days: 14),
  }) async {
    final box = await Hive.openBox<dynamic>(_memoryBoxName);
    await box.put(_decisionKey(suggestion.fingerprint), {
      'type': 'reject',
      'until': DateTime.now().add(duration).toIso8601String(),
      'templateId': suggestion.templateId,
    });
  }

  static Future<TaskModel> accept(AiTaskSuggestion suggestion) async {
    final now = DateTime.now();
    final assignee = TaskAssignment.coerce(suggestion.assigneeId);
    final tags = <String>[
      'wesi-ai',
      'wesi-ai:template:${suggestion.templateId}',
      'wesi-ai:category:${suggestion.category.name}',
      'wesi-ai:impact:${suggestion.forecastImpact.name}',
      'wesi-ai:fingerprint:${suggestion.fingerprint}',
      if (suggestion.sourceTaskId != null)
        'wesi-ai:source:${suggestion.sourceTaskId}',
    ];
    final task = TaskModel(
      id: 'wesi_ai_${now.microsecondsSinceEpoch}',
      title: suggestion.title.trim(),
      description: suggestion.description.trim().isEmpty
          ? null
          : suggestion.description.trim(),
      status: TaskStatus.backlog,
      priority: suggestion.priority,
      createdAt: now,
      dueDate: suggestion.dueDate,
      assignee: assignee,
      organizationId: suggestion.organizationId,
      responsibleEmployeeId: assignee,
      tags: tags,
    );
    await TaskService().save(task);

    final box = await Hive.openBox<dynamic>(_memoryBoxName);
    await box.put(_decisionKey(suggestion.fingerprint), {
      'type': 'accepted',
      'taskId': task.id,
      'at': now.toIso8601String(),
      'templateId': suggestion.templateId,
    });
    return task;
  }

  static Future<Set<String>> _employeeIdsForOrganization(String orgId) async {
    final result = <String>{};
    for (final employee in TeamService.all) {
      if (employee.isOwner) {
        result.add(employee.id);
        continue;
      }
      final grants = await OrganizationAccessService.grantsFor(employee.id);
      for (final grant in grants) {
        if (!grant.allows(OrganizationPermissions.view)) continue;
        if (grant.organizationId == orgId) {
          result.add(employee.id);
          break;
        }
        if (grant.includeSubtree &&
            await OrganizationService.isDescendant(
                orgId, grant.organizationId)) {
          result.add(employee.id);
          break;
        }
      }
    }
    return result;
  }

  static Future<AiBusinessSignal> _businessSignal(DateTime now) async {
    final orgId = OrganizationContext.currentOrganizationId;
    try {
      if (TeamService.current != null &&
          !await OrganizationAccessService.can(
            orgId,
            OrganizationPermissions.viewFinance,
          )) {
        return const AiBusinessSignal();
      }

      final treasury = TreasuryService();
      final all = (await treasury.getAllTransactions())
          .where((tx) => tx.effectiveOrganizationId == orgId)
          .toList();
      final recentStart = now.subtract(const Duration(days: 30));
      final previousStart = now.subtract(const Duration(days: 60));
      var recentIncome = 0.0;
      var previousIncome = 0.0;
      var recentExpense = 0.0;
      for (final tx in all) {
        if (tx.isRecurring || tx.date.isAfter(now)) continue;
        if (!tx.date.isBefore(recentStart)) {
          if (tx.type == TransactionType.income) {
            recentIncome += tx.amount;
          } else {
            recentExpense += tx.amount;
          }
        } else if (!tx.date.isBefore(previousStart) &&
            tx.type == TransactionType.income) {
          previousIncome += tx.amount;
        }
      }
      final growth = previousIncome <= 0
          ? (recentIncome > 0 ? 1.0 : 0.0)
          : (recentIncome - previousIncome) / previousIncome;

      var forecastTrend = 0.0;
      var maxRisk = 0.0;
      int? runwayDays;
      var forecastInsufficient = true;
      try {
        if (TeamService.current == null ||
            await OrganizationAccessService.can(
              orgId,
              OrganizationPermissions.viewForecast,
            )) {
          final forecast = await treasury.generateForecast(days: 30);
          forecastTrend = forecast.trendPerDay;
          maxRisk = forecast.maximumGapRisk;
          runwayDays = forecast.runwayDays;
          forecastInsufficient = forecast.insufficientData;
        }
      } catch (_) {
        // Finance history is still useful when Horizon is not available.
      }

      return AiBusinessSignal(
        financeAvailable: true,
        recentIncome: recentIncome,
        previousIncome: previousIncome,
        recentNet: recentIncome - recentExpense,
        incomeGrowth: growth,
        forecastTrendPerDay: forecastTrend,
        maximumCashRisk: maxRisk,
        runwayDays: runwayDays,
        forecastInsufficient: forecastInsufficient,
      );
    } catch (_) {
      return const AiBusinessSignal();
    }
  }

  static Future<bool> _suppressed(
    Box<dynamic> box,
    AiTaskSuggestion suggestion,
    List<TaskModel> tasks,
    DateTime now,
  ) async {
    final raw = box.get(_decisionKey(suggestion.fingerprint));
    if (raw is! Map) return false;
    final type = raw['type']?.toString();
    if (type == 'snooze' || type == 'reject') {
      final until = DateTime.tryParse(raw['until']?.toString() ?? '');
      return until != null && now.isBefore(until);
    }
    if (type == 'accepted') {
      final taskId = raw['taskId']?.toString();
      if (taskId == null) return false;
      TaskModel? accepted;
      for (final task in tasks) {
        if (task.id == taskId) {
          accepted = task;
          break;
        }
      }
      if (accepted == null) return false;
      if (accepted.status != TaskStatus.done) return true;
      // Do not immediately recreate a just-finished recurring cycle.
      return now.difference(accepted.createdAt).inDays < 2;
    }
    return false;
  }

  static String _decisionKey(String fingerprint) => 'decision::$fingerprint';
}
