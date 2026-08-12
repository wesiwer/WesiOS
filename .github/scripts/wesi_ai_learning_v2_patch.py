from pathlib import Path

# ---------------------------------------------------------------------------
# Adaptive policy: expose the most recent matching task alongside learned cadence.
p = Path('lib/features/tasks/ai/services/wesi_ai_adaptive_policy.dart')
s = p.read_text(encoding='utf-8')
s = s.replace(
"""  final int matchingTasks;

  const AiCadenceSignal({
    required this.effectiveDays,
    this.learnedMedianDays,
    required this.matchingTasks,
  });""",
"""  final int matchingTasks;
  final DateTime? latestAt;

  const AiCadenceSignal({
    required this.effectiveDays,
    this.learnedMedianDays,
    required this.matchingTasks,
    this.latestAt,
  });""",
)
s = s.replace(
"""      return AiCadenceSignal(
        effectiveDays: template.cadenceDays,
        matchingTasks: matching.length,
      );""",
"""      return AiCadenceSignal(
        effectiveDays: template.cadenceDays,
        matchingTasks: matching.length,
        latestAt: matching.isEmpty ? null : matching.last.createdAt,
      );""",
)
# There are two identical fallback blocks; replace handles both.
s = s.replace(
"""    return AiCadenceSignal(
      effectiveDays: blended.clamp(minimum, maximum).toInt(),
      learnedMedianDays: median,
      matchingTasks: matching.length,
    );""",
"""    return AiCadenceSignal(
      effectiveDays: blended.clamp(minimum, maximum).toInt(),
      learnedMedianDays: median,
      matchingTasks: matching.length,
      latestAt: matching.last.createdAt,
    );""",
)
p.write_text(s, encoding='utf-8')

# ---------------------------------------------------------------------------
# Engine integration.
p = Path('lib/features/tasks/ai/services/wesi_ai_task_engine.dart')
s = p.read_text(encoding='utf-8')
s = s.replace(
"""import '../models/ai_task_suggestion.dart';
import '../models/ai_task_template.dart';
import 'task_template_catalog.dart';""",
"""import '../models/ai_learning_profile.dart';
import '../models/ai_task_suggestion.dart';
import '../models/ai_task_template.dart';
import 'task_template_catalog.dart';
import 'wesi_ai_adaptive_policy.dart';""",
)
s = s.replace(
"""  final AiBusinessSignal businessSignal;
  final DateTime now;""",
"""  final AiBusinessSignal businessSignal;
  final AiLearningProfile learningProfile;
  final DateTime now;""",
)
s = s.replace(
"""    required this.businessSignal,
    required this.now,""",
"""    required this.businessSignal,
    this.learningProfile = const AiLearningProfile(),
    required this.now,""",
)
old = """      final trigger = _triggerNeed(template, input, scopedTasks);
      if (!trigger.needed) continue;

      final ranked = _rankEmployees(template, input, scopedTasks);
      if (ranked.isEmpty) continue;

      final chosen = ranked.first;
      final priority =
          _priorityFor(template, trigger.score, input.businessSignal);"""
new = """      final trigger = _triggerNeed(template, input, scopedTasks);
      if (!trigger.needed) continue;
      final learning = input.learningProfile.forTemplate(template.id);
      final needScore =
          (trigger.score * learning.needMultiplier).clamp(0.0, 1.0).toDouble();
      // Repeated rejection lowers routine noise, but cannot silence a truly
      // critical signal: a very high raw need is still allowed through.
      if (learning.rejected >= 2 &&
          learning.accepted == 0 &&
          needScore < .85) {
        continue;
      }

      final ranked = _rankEmployees(template, input, scopedTasks, learning);
      if (ranked.isEmpty) continue;

      final chosen = ranked.first;
      final priority = _priorityFor(
        template,
        needScore,
        input.businessSignal,
        learning,
      );"""
if old not in s:
    raise SystemExit('engine analyze anchor not found')
s = s.replace(old, new)
s = s.replace(
"""        ...trigger.evidence,
        _employeeEvidence(chosen, scopedTasks),
      ];""",
"""        ...trigger.evidence,
        _employeeEvidence(chosen, scopedTasks, input.now),
        if (learning.decisions >= 2)
          'Учтено ваших решений по этому типу задач: ${learning.decisions}',
      ];""",
)
s = s.replace(
"""        forecastImpact: _impactFor(template, input.businessSignal),
        needScore: trigger.score.clamp(0.0, 1.0).toDouble(),
        confidence: _confidence(template, trigger, ranked.length),""",
"""        forecastImpact: _impactFor(
          template,
          input.businessSignal,
          learning,
        ),
        needScore: needScore,
        confidence: _confidence(template, trigger, ranked.length, learning),""",
)

# Adaptive cadence in trigger evaluation.
old = """    final categoryTasks = tasks
        .where((task) => categoryOfTask(task) == template.category)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final latest = categoryTasks.isEmpty ? null : categoryTasks.first;
    final gapDays = latest == null
        ? template.cadenceDays + 1
        : input.now.difference(latest.createdAt).inDays;"""
new = """    final categoryTasks = tasks
        .where((task) => categoryOfTask(task) == template.category)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final cadence = WesiAiAdaptivePolicy.cadenceFor(template, tasks, input.now);
    final latest = cadence.latestAt ??
        (categoryTasks.isEmpty ? null : categoryTasks.first.createdAt);
    final gapDays = latest == null
        ? cadence.effectiveDays + 1
        : input.now.difference(latest).inDays;"""
if old not in s:
    raise SystemExit('engine cadence anchor not found')
s = s.replace(old, new)
s = s.replace('gapDays < template.cadenceDays', 'gapDays < cadence.effectiveDays')
s = s.replace(
'final ratio = gapDays / max(1, template.cadenceDays);',
'final ratio = gapDays / max(1, cadence.effectiveDays);',
)
s = s.replace(
"""        final label = latest == null
            ? 'Таких задач ещё не было в истории организации'
            : 'Последняя похожая задача была $gapDays дн. назад';
        return _TriggerNeed(
          needed: true,
          score: score,
          whyNow: latest == null
              ? 'В работе организации есть незакрытая регулярная зона.'
              : 'Интервал с последней похожей работой уже превышает нормальный цикл.',
          evidence: [label],
        );""",
"""        final label = latest == null
            ? 'Таких задач ещё не было в истории организации'
            : 'Последняя похожая задача была $gapDays дн. назад';
        return _TriggerNeed(
          needed: true,
          score: score,
          whyNow: latest == null
              ? 'В работе организации есть незакрытая регулярная зона.'
              : 'Интервал с последней похожей работой уже превышает нормальный цикл.',
          evidence: [
            label,
            if (cadence.learned)
              'Обычный ритм организации: примерно раз в ${cadence.effectiveDays} дн.',
          ],
        );""",
)

# Rank by title + demonstrated work, protect fatigue, favor genuinely free staff,
# and learn accepted assignees.
s = s.replace(
"""  static List<_RankedEmployee> _rankEmployees(
    AiTaskTemplate template,
    WesiAiAnalysisInput input,
    List<TaskModel> tasks,
  ) {""",
"""  static List<_RankedEmployee> _rankEmployees(
    AiTaskTemplate template,
    WesiAiAnalysisInput input,
    List<TaskModel> tasks,
    AiTemplateLearning learning,
  ) {""",
)
s = s.replace(
"""      final roleFit = _roleFit(employee.position, template.roleAliases);
      if (roleFit <= 0) continue;

      final workload = _workload(employee.id, tasks);
      if (workload.openWeight >= 7 || workload.overdue >= 4) continue;""",
"""      final positionFit = _roleFit(employee.position, template.roleAliases);
      final historyFit = WesiAiAdaptivePolicy.historicalRoleFit(
        employee,
        template.category,
        tasks,
        categoryOfTask,
      );
      final roleFit = max(positionFit, historyFit);
      if (roleFit <= 0) continue;

      final workload = _workload(employee.id, tasks);
      final adaptiveCapacity = WesiAiAdaptivePolicy.capacityFor(
        employee.id,
        tasks,
        input.now,
      );
      if (workload.openWeight >= 7 || workload.overdue >= 4) continue;
      if (adaptiveCapacity.fatigueRisk && template.effortPoints >= 2.5) {
        continue;
      }""",
)
s = s.replace(
"""      final capacity = (1 - workload.openWeight / 7).clamp(0.0, 1.0);
      final health = workload.total == 0
          ? .65
          : (workload.done / workload.total).clamp(0.0, 1.0);
      final overduePenalty = min(.40, workload.overdue * .12);
      final score =
          roleFit * .48 + capacity * .34 + health * .18 - overduePenalty;
      result.add(_RankedEmployee(employee, score, workload));""",
"""      final capacity = (1 - workload.openWeight / 7).clamp(0.0, 1.0);
      final reliability = adaptiveCapacity.reliability;
      final underloadBoost = adaptiveCapacity.underutilized ? .10 : 0.0;
      final fatiguePenalty = adaptiveCapacity.recentIntensity7 >= 4.5 ? .08 : 0.0;
      final overduePenalty = min(.40, workload.overdue * .12);
      final score = roleFit * .48 +
          capacity * .28 +
          reliability * .10 +
          underloadBoost +
          learning.assigneeBoost(employee.id) -
          overduePenalty -
          fatiguePenalty;
      result.add(_RankedEmployee(employee, score, workload));""",
)

# Learn user priority/impact corrections.
s = s.replace(
"""  static TaskPriority _priorityFor(
    AiTaskTemplate template,
    double need,
    AiBusinessSignal signal,
  ) {""",
"""  static TaskPriority _priorityFor(
    AiTaskTemplate template,
    double need,
    AiBusinessSignal signal,
    AiTemplateLearning learning,
  ) {""",
)
s = s.replace(
"""    if (template.trigger == AiTaskTrigger.businessPressure &&
        signal.pressureScore >= .70) {
      index++;
    }
    return TaskPriority""",
"""    if (template.trigger == AiTaskTrigger.businessPressure &&
        signal.pressureScore >= .70) {
      index++;
    }
    if (learning.accepted > 0 && learning.averagePriorityDelta.abs() >= .45) {
      index += learning.averagePriorityDelta.round();
    }
    return TaskPriority""",
)
s = s.replace(
"""  static AiForecastImpact _impactFor(
    AiTaskTemplate template,
    AiBusinessSignal signal,
  ) {""",
"""  static AiForecastImpact _impactFor(
    AiTaskTemplate template,
    AiBusinessSignal signal,
    AiTemplateLearning learning,
  ) {""",
)
s = s.replace(
"""    if (template.trigger == AiTaskTrigger.businessPressure &&
        signal.pressureScore >= .75) {
      index++;
    }
    return AiForecastImpact""",
"""    if (template.trigger == AiTaskTrigger.businessPressure &&
        signal.pressureScore >= .75) {
      index++;
    }
    if (learning.accepted > 0 && learning.averageImpactDelta.abs() >= .45) {
      index += learning.averageImpactDelta.round();
    }
    return AiForecastImpact""",
)
s = s.replace(
"""  static double _confidence(
    AiTaskTemplate template,
    _TriggerNeed trigger,
    int eligiblePeople,
  ) {""",
"""  static double _confidence(
    AiTaskTemplate template,
    _TriggerNeed trigger,
    int eligiblePeople,
    AiTemplateLearning learning,
  ) {""",
)
s = s.replace(
"""    if (trigger.sourceTask != null) value += .08;
    if (template.trigger == AiTaskTrigger.businessPressure) value += .04;
    return value.clamp(.45, .96).toDouble();""",
"""    if (trigger.sourceTask != null) value += .08;
    if (template.trigger == AiTaskTrigger.businessPressure) value += .04;
    if (learning.decisions >= 3) {
      value += learning.accepted >= learning.rejected ? .03 : -.03;
    }
    return value.clamp(.45, .96).toDouble();""",
)
# Due date respects effort instead of forcing a multi-hour/heavy task into a
# one-day box just because it is urgent.
s = s.replace(
"""  static DateTime _dueDate(DateTime now, TaskPriority priority) {
    final days = switch (priority) {
      TaskPriority.urgent => 1,
      TaskPriority.high => 2,
      TaskPriority.normal => 4,
      TaskPriority.low => 7,
    };
    return DateTime(now.year, now.month, now.day).add(Duration(days: days));
  }""",
"""  static DateTime _dueDate(
    DateTime now,
    TaskPriority priority,
    [double effortPoints = 1],
  ) {
    final priorityDays = switch (priority) {
      TaskPriority.urgent => 1,
      TaskPriority.high => 2,
      TaskPriority.normal => 4,
      TaskPriority.low => 7,
    };
    final effortDays = effortPoints.ceil().clamp(1, 7);
    final days = max(priorityDays, effortDays);
    return DateTime(now.year, now.month, now.day).add(Duration(days: days));
  }""",
)
s = s.replace('dueDate: _dueDate(input.now, priority),', 'dueDate: _dueDate(input.now, priority, template.effortPoints),')

# Employee explanation distinguishes free capacity from simple historical rate.
s = s.replace(
"""  static String _employeeEvidence(
    _RankedEmployee ranked,
    List<TaskModel> tasks,
  ) {
    final load = ranked.workload.openWeight;""",
"""  static String _employeeEvidence(
    _RankedEmployee ranked,
    List<TaskModel> tasks,
    DateTime now,
  ) {
    final load = ranked.workload.openWeight;
    final adaptive = WesiAiAdaptivePolicy.capacityFor(
      ranked.employee.id,
      tasks,
      now,
    );
    if (adaptive.underutilized) {
      return '${ranked.employee.displayName}: есть свободная ёмкость без просроченного хвоста';
    }""",
)
p.write_text(s, encoding='utf-8')

# ---------------------------------------------------------------------------
# Service: persist learning events per organization and feed profile to engine.
p = Path('lib/features/tasks/ai/services/wesi_ai_task_service.dart')
s = p.read_text(encoding='utf-8')
s = s.replace(
"""import '../models/ai_task_suggestion.dart';
import 'wesi_ai_task_engine.dart';""",
"""import '../models/ai_learning_profile.dart';
import '../models/ai_task_suggestion.dart';
import 'task_template_catalog.dart';
import 'wesi_ai_task_engine.dart';""",
)
s = s.replace(
"""    final businessSignal = await _businessSignal(clock);

    final raw = WesiAiTaskEngine.analyze(WesiAiAnalysisInput(""",
"""    final businessSignal = await _businessSignal(clock);
    final box = await Hive.openBox<dynamic>(_memoryBoxName);
    final learningProfile = _learningProfile(box, organization.id);

    final raw = WesiAiTaskEngine.analyze(WesiAiAnalysisInput(""",
)
s = s.replace(
"""      businessSignal: businessSignal,
      now: clock,""",
"""      businessSignal: businessSignal,
      learningProfile: learningProfile,
      now: clock,""",
)
s = s.replace("\n    final box = await Hive.openBox<dynamic>(_memoryBoxName);\n    final visible", "\n    final visible", 1)
# Above replace may hit the earlier box; ensure analyze has exactly one declaration
# before engine and none immediately before visible.

s = s.replace(
"""    await box.put(_decisionKey(suggestion.fingerprint), {
      'type': 'snooze',
      'until': DateTime.now().add(duration).toIso8601String(),
      'templateId': suggestion.templateId,
    });
  }""",
"""    await box.put(_decisionKey(suggestion.fingerprint), {
      'type': 'snooze',
      'until': DateTime.now().add(duration).toIso8601String(),
      'templateId': suggestion.templateId,
    });
    await _recordLearningEvent(box, suggestion, 'snooze');
  }""",
)
s = s.replace(
"""    await box.put(_decisionKey(suggestion.fingerprint), {
      'type': 'reject',
      'until': DateTime.now().add(duration).toIso8601String(),
      'templateId': suggestion.templateId,
    });
  }""",
"""    await box.put(_decisionKey(suggestion.fingerprint), {
      'type': 'reject',
      'until': DateTime.now().add(duration).toIso8601String(),
      'templateId': suggestion.templateId,
    });
    await _recordLearningEvent(box, suggestion, 'reject');
  }""",
)
s = s.replace(
"""    await box.put(_decisionKey(suggestion.fingerprint), {
      'type': 'accepted',
      'taskId': task.id,
      'at': now.toIso8601String(),
      'templateId': suggestion.templateId,
    });
    return task;""",
"""    await box.put(_decisionKey(suggestion.fingerprint), {
      'type': 'accepted',
      'taskId': task.id,
      'at': now.toIso8601String(),
      'templateId': suggestion.templateId,
    });
    await _recordLearningEvent(
      box,
      suggestion.copyWith(assigneeId: assignee, clearAssignee: assignee == null),
      'accepted',
      taskId: task.id,
    );
    return task;""",
)
anchor = """  static Future<Set<String>> _employeeIdsForOrganization(String orgId) async {"""
helpers = r'''  static AiLearningProfile _learningProfile(
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
            final map = assignees.putIfAbsent(templateId, () => <String, int>{});
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
    await box.put('event::${now.microsecondsSinceEpoch}::${suggestion.templateId}', {
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

'''
if anchor not in s:
    raise SystemExit('service helper anchor not found')
s = s.replace(anchor, helpers + anchor)
# Add local firstOrNull extension if service does not already have one.
if 'extension _FirstOrNull' not in s:
    s += r'''

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
'''
p.write_text(s, encoding='utf-8')

# ---------------------------------------------------------------------------
# UI wording: make learning visible but not noisy.
p = Path('lib/features/tasks/ai/widgets/wesi_ai_suggestions_panel.dart')
s = p.read_text(encoding='utf-8')
s = s.replace(
"Учитываю историю работы, роли, загрузку, отдых и Wesi Horizon.",
"Учитываю историю работы, ваши решения, роли, загрузку, отдых и Wesi Horizon.",
)
s = s.replace(
"Учитываю историю работы, роли, загрузку и отдых. Финансы недоступны этому профилю.",
"Учитываю историю работы, ваши решения, роли, загрузку и отдых. Финансы недоступны этому профилю.",
)
p.write_text(s, encoding='utf-8')

print('Wesi AI adaptive learning v2 patch applied')
