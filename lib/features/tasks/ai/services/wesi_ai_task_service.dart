import 'package:hive_flutter/hive_flutter.dart';

import '../../../../core/sync/sync_account_scope.dart';
import '../../../audio/models/audio_vault_models.dart';
import '../../../audio/services/audio_vault_service.dart';
import '../../../crm/models/crm_models.dart';
import '../../../crm/services/crm_service.dart';
import '../../../files/models/file_share_models.dart';
import '../../../files/services/file_share_service.dart';
import '../../../organizations/models/organization_access_grant.dart';
import '../../../organizations/services/organization_access_service.dart';
import '../../../organizations/services/organization_context.dart';
import '../../../organizations/services/organization_service.dart';
import '../../../roadmap/models/roadmap_models.dart';
import '../../../roadmap/services/roadmap_service.dart';
import '../../../team/models/team_permissions.dart';
import '../../../team/services/team_service.dart';
import '../../../treasury/models/transaction_model.dart';
import '../../../treasury/services/treasury_service.dart';
import '../../models/task_model.dart';
import '../../services/task_assignment.dart';
import '../../services/task_service.dart';
import '../models/ai_learning_profile.dart';
import '../models/ai_task_suggestion.dart';
import 'task_template_catalog.dart';
import 'wesi_ai_fact_finder.dart';
import 'wesi_ai_strategy_planner.dart';
import 'wesi_ai_task_engine.dart';

class WesiAiTaskService {
  WesiAiTaskService._();

  static const String memoryBaseBoxName = 'wesios_wesi_ai_task_memory_v1';
  static String get memoryBoxName => SyncAccountScope.boxName(memoryBaseBoxName);
  static const int visibleLimit = 5;

  static Future<AiTaskAnalysisResult> analyze({DateTime? now}) async {
    final clock = now ?? DateTime.now();
    final organization = await OrganizationContext.currentOrganization();
    final tasks = await TaskService().getForOrganizations({organization.id});
    final eligibleIds = await _employeeIdsForOrganization(organization.id);
    // Журнал операций читается один раз на весь разбор: и денежные итоги, и
    // поиск фактов смотрят в один и тот же список.
    final transactions = await _scopedTransactions(organization.id);
    final businessSignal = await _businessSignal(clock, transactions);
    final world = await _worldState(organization.id, tasks, transactions);
    final box = await Hive.openBox<dynamic>(memoryBoxName);
    final learningProfile = _learningProfile(box, organization.id);

    final raw = WesiAiTaskEngine.analyze(WesiAiAnalysisInput(
      tasks: tasks,
      world: world,
      employees: TeamService.all,
      eligibleEmployeeIds: eligibleIds,
      organizationId: organization.id,
      organizationName: organization.name,
      organizationDescription: organization.description ?? '',
      currentEmployeeId: TeamService.current?.id,
      canAssignToOthers: TaskAssignment.canAssignToOthers,
      businessSignal: businessSignal,
      learningProfile: learningProfile,
      now: clock,
    ));

    final allowed = <AiTaskSuggestion>[];
    for (final suggestion in raw) {
      if (await _suppressed(box, suggestion, tasks, clock)) continue;
      allowed.add(suggestion);
    }

    final strategic = WesiAiStrategyPlanner.rank(
      suggestions: allowed,
      tasks: tasks,
      organizationId: organization.id,
      organizationName: organization.name,
      organizationDescription: organization.description ?? '',
      businessSignal: businessSignal,
      now: clock,
    );

    return AiTaskAnalysisResult(
      suggestions: strategic.take(visibleLimit).toList(),
      businessSignal: businessSignal,
      analyzedAt: clock,
      organizationName: organization.name,
    );
  }

  static Future<void> snooze(
    AiTaskSuggestion suggestion, {
    Duration duration = const Duration(days: 3),
  }) async {
    final box = await Hive.openBox<dynamic>(memoryBoxName);
    await box.put(_decisionKey(suggestion.fingerprint), {
      'type': 'snooze',
      'until': DateTime.now().add(duration).toIso8601String(),
      'templateId': suggestion.templateId,
    });
    await _recordLearningEvent(box, suggestion, 'snooze');
  }

  static Future<void> reject(
    AiTaskSuggestion suggestion, {
    Duration duration = const Duration(days: 14),
  }) async {
    final box = await Hive.openBox<dynamic>(memoryBoxName);
    await box.put(_decisionKey(suggestion.fingerprint), {
      'type': 'reject',
      'until': DateTime.now().add(duration).toIso8601String(),
      'templateId': suggestion.templateId,
    });
    await _recordLearningEvent(box, suggestion, 'reject');
  }

  static Future<TaskModel> accept(AiTaskSuggestion suggestion) async {
    final now = DateTime.now();
    final assignee = TaskAssignment.coerce(suggestion.assigneeId);
    final tags = <String>[
      'wesi-ai',
      'wesi-ai:template:${suggestion.templateId}',
      'wesi-ai:category:${suggestion.category.name}',
      'wesi-ai:impact:${suggestion.forecastImpact.name}',
      'wesi-ai:strategy:${(suggestion.strategicScore * 100).round()}',
      'wesi-ai:fingerprint:${suggestion.fingerprint}',
      if (suggestion.sourceTaskId != null)
        'wesi-ai:source:${suggestion.sourceTaskId}',
      // Метка объекта: пока задача не закрыта, система не предложит то же
      // самое ещё раз — ни на этом устройстве, ни на устройстве коллеги.
      if (suggestion.isFact) suggestion.factTag,
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

    final box = await Hive.openBox<dynamic>(memoryBoxName);
    await box.put(_decisionKey(suggestion.fingerprint), {
      'type': 'accepted',
      'taskId': task.id,
      'at': now.toIso8601String(),
      'templateId': suggestion.templateId,
    });
    await _recordLearningEvent(
      box,
      suggestion.copyWith(
          assigneeId: assignee, clearAssignee: assignee == null),
      'accepted',
      taskId: task.id,
    );
    return task;
  }

  static AiLearningProfile _learningProfile(
    Box<dynamic> box,
    String organizationId,
  ) {
    final accepted = <String, int>{};
    final rejected = <String, int>{};
    final snoozed = <String, int>{};
    final prioritySum = <String, double>{};
    final impactSum = <String, double>{};
    final assignees = <String, Map<String, int>>{};

    for (final raw in box.values) {
      if (raw is! Map || raw['eventVersion'] != 2) continue;
      if (raw['organizationId']?.toString() != organizationId) continue;
      final templateId = raw['templateId']?.toString();
      final type = raw['type']?.toString();
      if (templateId == null || type == null) continue;
      switch (type) {
        case 'accepted':
          accepted[templateId] = (accepted[templateId] ?? 0) + 1;
          prioritySum[templateId] =
              (prioritySum[templateId] ?? 0) + _asDouble(raw['priorityDelta']);
          impactSum[templateId] =
              (impactSum[templateId] ?? 0) + _asDouble(raw['impactDelta']);
          final employeeId = raw['assigneeId']?.toString();
          if (employeeId != null && employeeId.isNotEmpty) {
            final map =
                assignees.putIfAbsent(templateId, () => <String, int>{});
            map[employeeId] = (map[employeeId] ?? 0) + 1;
          }
          break;
        case 'reject':
          rejected[templateId] = (rejected[templateId] ?? 0) + 1;
          break;
        case 'snooze':
          snoozed[templateId] = (snoozed[templateId] ?? 0) + 1;
          break;
      }
    }

    final ids = <String>{
      ...accepted.keys,
      ...rejected.keys,
      ...snoozed.keys,
    };
    return AiLearningProfile(
      templates: {
        for (final id in ids)
          id: AiTemplateLearning(
            accepted: accepted[id] ?? 0,
            rejected: rejected[id] ?? 0,
            snoozed: snoozed[id] ?? 0,
            averagePriorityDelta: (accepted[id] ?? 0) == 0
                ? 0
                : (prioritySum[id] ?? 0) / accepted[id]!,
            averageImpactDelta: (accepted[id] ?? 0) == 0
                ? 0
                : (impactSum[id] ?? 0) / accepted[id]!,
            acceptedAssignees: Map.unmodifiable(
              assignees[id] ?? const <String, int>{},
            ),
          ),
      },
    );
  }

  static Future<void> _recordLearningEvent(
    Box<dynamic> box,
    AiTaskSuggestion suggestion,
    String type, {
    String? taskId,
  }) async {
    final now = DateTime.now();
    final template = WesiAiTaskCatalog.all
        .where((item) => item.id == suggestion.templateId)
        .firstOrNull;
    await box
        .put('event::${now.microsecondsSinceEpoch}::${suggestion.templateId}', {
      'eventVersion': 2,
      'type': type,
      'at': now.toIso8601String(),
      'organizationId': suggestion.organizationId,
      'templateId': suggestion.templateId,
      'taskId': taskId,
      'assigneeId': suggestion.assigneeId,
      'priorityDelta': template == null
          ? 0
          : suggestion.priority.index - template.basePriority.index,
      'impactDelta': template == null
          ? 0
          : suggestion.forecastImpact.index - template.forecastImpact.index,
      'strategicScore': suggestion.strategicScore,
    });

    final eventKeys = box.keys
        .where((key) => key.toString().startsWith('event::'))
        .map((key) => key.toString())
        .toList()
      ..sort();
    if (eventKeys.length > 300) {
      await box.deleteAll(eventKeys.take(eventKeys.length - 300));
    }
  }

  static double _asDouble(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

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

  /// Живые данные организации для поиска фактов.
  ///
  /// Каждый источник читается отдельно и в своём `try`: если у человека нет
  /// доступа к CRM или модуль поломан, система теряет один источник фактов,
  /// а не весь разбор целиком.
  static Future<WesiAiWorldState> _worldState(
    String organizationId,
    List<TaskModel> tasks,
    List<TransactionModel>? transactions,
  ) async {
    var clients = const <CrmClient>[];
    var deals = const <CrmDeal>[];
    var interactions = const <CrmInteraction>[];
    if (_moduleAllowed(TeamModules.crm)) {
      try {
        clients = await CrmService.clientsForOrganizations({organizationId});
        deals = await CrmService.dealsForOrganizations({organizationId});
        final visibleClients = {for (final c in clients) c.id};
        interactions = (await CrmService.interactionsRaw())
            .where((item) => visibleClients.contains(item.clientId))
            .toList();
      } catch (_) {
        clients = const [];
        deals = const [];
        interactions = const [];
      }
    }

    // У дорожной карты и каталога битов нет привязки к организации — это
    // данные всего приложения. Поэтому они видны в любом контексте, а от
    // повторных предложений защищает метка факта на созданной задаче.
    var projects = const <RoadmapProject>[];
    var roadmapItems = const <RoadmapItem>[];
    if (_moduleAllowed(TeamModules.roadmap)) {
      try {
        projects = await RoadmapService.projects(includeArchived: false);
        roadmapItems = await RoadmapService.items();
      } catch (_) {
        projects = const [];
        roadmapItems = const [];
      }
    }

    var beats = const <BeatEntry>[];
    if (_moduleAllowed(TeamModules.audio)) {
      try {
        beats = await AudioVaultService.all();
      } catch (_) {
        beats = const [];
      }
    }

    var fileRequests = const <FileShareRequest>[];
    try {
      final me = TeamService.current?.id;
      fileRequests = me == null
          ? const []
          : await FileShareService.incoming(me);
    } catch (_) {
      fileRequests = const [];
    }

    return WesiAiWorldState(
      tasks: tasks,
      clients: clients,
      deals: deals,
      interactions: interactions,
      projects: projects,
      roadmapItems: roadmapItems,
      beats: beats,
      fileRequests: fileRequests,
      transactions: transactions ?? const [],
    );
  }

  /// Операции организации — или `null`, если финансы этому человеку закрыты.
  ///
  /// Пустой список и «нет доступа» — разные вещи: в первом случае денежных
  /// итогов просто нет, во втором их нельзя показывать.
  static Future<List<TransactionModel>?> _scopedTransactions(
    String organizationId,
  ) async {
    if (!await _financeVisible(organizationId)) return null;
    try {
      return (await TreasuryService().getAllTransactions())
          .where((tx) => tx.effectiveOrganizationId == organizationId)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static bool _moduleAllowed(String module) {
    final current = TeamService.current;
    return current == null ||
        current.isOwner ||
        current.permissions.allows(module);
  }

  static Future<bool> _financeVisible(String organizationId) async {
    if (TeamService.current == null) return true;
    try {
      return await OrganizationAccessService.can(
        organizationId,
        OrganizationPermissions.viewFinance,
      );
    } catch (_) {
      return false;
    }
  }

  /// [scoped] — операции организации, уже прочитанные один раз.
  ///
  /// Раньше денежные итоги и поиск фактов читали журнал операций каждый
  /// по разу. На большом журнале это удвоенная работа на каждое обновление
  /// панели, поэтому список читается один раз и передаётся сюда.
  static Future<AiBusinessSignal> _businessSignal(
    DateTime now,
    List<TransactionModel>? scoped,
  ) async {
    final orgId = OrganizationContext.currentOrganizationId;
    if (scoped == null) return const AiBusinessSignal();
    try {
      final treasury = TreasuryService();
      final all = scoped;
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
      return now.difference(accepted.createdAt).inDays < 2;
    }
    return false;
  }

  static String _decisionKey(String fingerprint) => 'decision::$fingerprint';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
