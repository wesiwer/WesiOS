import 'dart:math';

import '../../models/task_model.dart';
import '../../../team/models/employee_model.dart';
import '../models/ai_learning_profile.dart';
import '../models/ai_task_suggestion.dart';
import '../models/ai_task_template.dart';
import 'task_template_catalog.dart';
import 'wesi_ai_adaptive_policy.dart';

class WesiAiAnalysisInput {
  final List<TaskModel> tasks;
  final List<EmployeeModel> employees;
  final Set<String> eligibleEmployeeIds;
  final String organizationId;
  final String organizationName;
  final String organizationDescription;
  final String? currentEmployeeId;
  final bool canAssignToOthers;
  final AiBusinessSignal businessSignal;
  final AiLearningProfile learningProfile;
  final DateTime now;

  const WesiAiAnalysisInput({
    required this.tasks,
    required this.employees,
    required this.eligibleEmployeeIds,
    required this.organizationId,
    required this.organizationName,
    this.organizationDescription = '',
    required this.currentEmployeeId,
    required this.canAssignToOthers,
    required this.businessSignal,
    this.learningProfile = const AiLearningProfile(),
    required this.now,
  });
}

class WesiAiTaskEngine {
  WesiAiTaskEngine._();

  static List<AiTaskSuggestion> analyze(WesiAiAnalysisInput input) {
    final scopedTasks = input.tasks
        .where((task) => task.effectiveOrganizationId == input.organizationId)
        .toList();
    final candidates = <AiTaskSuggestion>[];

    for (final template in WesiAiTaskCatalog.all) {
      if (!_organizationRelevant(template, input, scopedTasks)) continue;
      if (_hasEquivalentOpenTask(template, scopedTasks)) continue;

      final trigger = _triggerNeed(template, input, scopedTasks);
      if (!trigger.needed) continue;
      final learning = input.learningProfile.forTemplate(template.id);
      final needScore =
          (trigger.score * learning.needMultiplier).clamp(0.0, 1.0).toDouble();
      // Repeated rejection lowers routine noise, but cannot silence a truly
      // critical signal: a very high raw need is still allowed through.
      if (learning.rejected >= 2 && learning.accepted == 0 && needScore < .85) {
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
      );
      final source = trigger.sourceTask;
      final fingerprint = [
        input.organizationId,
        template.id,
        source?.id ?? 'cycle',
      ].join(':');
      final evidence = <String>[
        ...trigger.evidence,
        _employeeEvidence(chosen, scopedTasks, input.now),
        if (learning.decisions >= 2)
          'Учтено ваших решений по этому типу задач: ${learning.decisions}',
      ];

      candidates.add(AiTaskSuggestion(
        id: 'wesi-ai-${fingerprint.hashCode.abs()}',
        fingerprint: fingerprint,
        templateId: template.id,
        category: template.category,
        organizationId: input.organizationId,
        title: template.title,
        description: template.description,
        assigneeId: chosen.employee.id,
        alternativeAssigneeIds: ranked.map((item) => item.employee.id).toList(),
        priority: priority,
        forecastImpact: _impactFor(
          template,
          input.businessSignal,
          learning,
        ),
        needScore: needScore,
        confidence: _confidence(template, trigger, ranked.length, learning),
        effortPoints: template.effortPoints,
        dueDate: _dueDate(input.now, priority, template.effortPoints),
        whyNow: trigger.whyNow,
        evidence: evidence,
        sourceTaskId: source?.id,
      ));
    }

    candidates.sort((a, b) {
      final need = b.needScore.compareTo(a.needScore);
      if (need != 0) return need;
      final impact = b.forecastImpact.index.compareTo(a.forecastImpact.index);
      if (impact != 0) return impact;
      return b.priority.index.compareTo(a.priority.index);
    });

    // Anti-spam at the recommendation layer: no more than five cards and no
    // more than two from one business area. A chain after completed work may
    // therefore coexist with one strategic recommendation, but sales pressure
    // cannot flood the whole panel with five variations of outreach.
    final perCategory = <AiTaskCategory, int>{};
    final result = <AiTaskSuggestion>[];
    for (final suggestion in candidates) {
      final count = perCategory[suggestion.category] ?? 0;
      if (count >= 2) continue;
      result.add(suggestion);
      perCategory[suggestion.category] = count + 1;
      if (result.length >= 5) break;
    }
    return result;
  }

  static AiTaskCategory? categoryOfTask(TaskModel task) {
    for (final tag in task.tags) {
      const prefix = 'wesi-ai:category:';
      if (!tag.startsWith(prefix)) continue;
      final name = tag.substring(prefix.length);
      for (final category in AiTaskCategory.values) {
        if (category.name == name) return category;
      }
    }

    for (final tag in task.tags) {
      const prefix = 'wesi-ai:template:';
      if (!tag.startsWith(prefix)) continue;
      final id = tag.substring(prefix.length);
      for (final template in WesiAiTaskCatalog.all) {
        if (template.id == id) return template.category;
      }
    }

    final text = _normalize(
        '${task.title} ${task.description ?? ''} ${task.tags.join(' ')}');
    AiTaskCategory? best;
    var bestScore = 0;
    for (final template in WesiAiTaskCatalog.all) {
      var score = 0;
      for (final keyword in template.taskKeywords) {
        if (text.contains(_normalize(keyword))) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        best = template.category;
      }
    }
    return bestScore == 0 ? null : best;
  }

  static bool _organizationRelevant(
    AiTaskTemplate template,
    WesiAiAnalysisInput input,
    List<TaskModel> tasks,
  ) {
    if (template.organizationHints.isEmpty) return true;
    if (input.organizationId == 'org_wesi_beats' &&
        template.organizationHints.any(WesiAiTaskCatalog.musicHints.contains)) {
      return true;
    }
    final descriptor = _normalize(
      '${input.organizationName} ${input.organizationDescription}',
    );
    if (template.organizationHints
        .any((hint) => descriptor.contains(_normalize(hint)))) {
      return true;
    }
    // Existing work is a stronger direction signal than the organization name.
    return tasks.any((task) => categoryOfTask(task) == template.category);
  }

  static bool _hasEquivalentOpenTask(
    AiTaskTemplate template,
    List<TaskModel> tasks,
  ) {
    for (final task in tasks) {
      if (task.status == TaskStatus.done) continue;
      if (task.tags.contains('wesi-ai:template:${template.id}')) return true;
      final text = _normalize('${task.title} ${task.description ?? ''}');
      var matches = 0;
      for (final keyword in template.taskKeywords) {
        if (text.contains(_normalize(keyword))) matches++;
      }
      if (matches >= min(2, template.taskKeywords.length)) return true;
    }
    return false;
  }

  static _TriggerNeed _triggerNeed(
    AiTaskTemplate template,
    WesiAiAnalysisInput input,
    List<TaskModel> tasks,
  ) {
    final categoryTasks = tasks
        .where((task) => categoryOfTask(task) == template.category)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final cadence = WesiAiAdaptivePolicy.cadenceFor(template, tasks, input.now);
    final latest = cadence.latestAt ??
        (categoryTasks.isEmpty ? null : categoryTasks.first.createdAt);
    final gapDays = latest == null
        ? cadence.effectiveDays + 1
        : input.now.difference(latest).inDays;

    switch (template.trigger) {
      case AiTaskTrigger.businessPressure:
        if (!input.businessSignal.salesPressure) {
          return const _TriggerNeed.no();
        }
        final score = (.68 + input.businessSignal.pressureScore * .30)
            .clamp(0.0, 1.0)
            .toDouble();
        return _TriggerNeed(
          needed: true,
          score: score,
          whyNow: _businessPressureReason(input.businessSignal),
          evidence: _businessPressureEvidence(input.businessSignal),
        );

      case AiTaskTrigger.completionChain:
        final predecessor = tasks
            .where((task) =>
                task.status == TaskStatus.done &&
                categoryOfTask(task) == template.followsCategory)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (predecessor.isEmpty) return const _TriggerNeed.no();
        for (final source in predecessor) {
          final explicitSourceTag = 'wesi-ai:source:${source.id}';
          final alreadyFollowed = tasks.any((task) =>
              categoryOfTask(task) == template.category &&
              (task.tags.contains(explicitSourceTag) ||
                  task.createdAt.isAfter(source.createdAt)));
          if (alreadyFollowed) continue;
          return _TriggerNeed(
            needed: true,
            score: .84,
            whyNow:
                'Есть завершённый этап, после которого следующий шаг ещё не поставлен.',
            evidence: [
              'Завершено: «${source.title}»',
              'Следующий этап ${template.category.ru.toLowerCase()} ещё не найден в задачах',
            ],
            sourceTask: source,
          );
        }
        return const _TriggerNeed.no();

      case AiTaskTrigger.workloadGap:
        final lowLoadExists = input.employees.any((employee) {
          if (!input.eligibleEmployeeIds.contains(employee.id)) return false;
          if (!input.canAssignToOthers &&
              employee.id != input.currentEmployeeId) {
            return false;
          }
          return _workload(employee.id, tasks).openWeight <= 1.5;
        });
        if (!lowLoadExists || gapDays < cadence.effectiveDays) {
          return const _TriggerNeed.no();
        }
        return _TriggerNeed(
          needed: true,
          score: .56,
          whyNow:
              'В команде есть свободная ёмкость, которую можно направить на полезное улучшение.',
          evidence: ['По этой категории давно не было активной работы'],
        );

      case AiTaskTrigger.hygiene:
      case AiTaskTrigger.cadence:
        if (gapDays < cadence.effectiveDays) return const _TriggerNeed.no();
        final ratio = gapDays / max(1, cadence.effectiveDays);
        final score =
            (.50 + min(.42, (ratio - 1) * .28)).clamp(0.0, 1.0).toDouble();
        final label = latest == null
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
        );
    }
  }

  static List<_RankedEmployee> _rankEmployees(
    AiTaskTemplate template,
    WesiAiAnalysisInput input,
    List<TaskModel> tasks,
    AiTemplateLearning learning,
  ) {
    final result = <_RankedEmployee>[];
    for (final employee in input.employees) {
      if (!input.eligibleEmployeeIds.contains(employee.id)) continue;
      if (!input.canAssignToOthers && employee.id != input.currentEmployeeId) {
        continue;
      }
      final positionFit = _roleFit(employee.position, template.roleAliases);
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
      }

      final lastSameCategory = tasks
          .where((task) =>
              task.effectiveResponsibleEmployeeId == employee.id &&
              categoryOfTask(task) == template.category)
          .map((task) => task.createdAt)
          .fold<DateTime?>(null, (latest, value) {
        if (latest == null || value.isAfter(latest)) return value;
        return latest;
      });
      if (lastSameCategory != null && template.minRestDays > 0) {
        final rest = input.now.difference(lastSameCategory).inDays;
        if (rest < template.minRestDays) continue;
      }

      final capacity = (1 - workload.openWeight / 7).clamp(0.0, 1.0);
      final reliability = adaptiveCapacity.reliability;
      final underloadBoost = adaptiveCapacity.underutilized ? .10 : 0.0;
      final fatiguePenalty =
          adaptiveCapacity.recentIntensity7 >= 4.5 ? .08 : 0.0;
      final overduePenalty = min(.40, workload.overdue * .12);
      final score = roleFit * .48 +
          capacity * .28 +
          reliability * .10 +
          underloadBoost +
          learning.assigneeBoost(employee.id) -
          overduePenalty -
          fatiguePenalty;
      result.add(_RankedEmployee(employee, score, workload));
    }
    result.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      return a.workload.openWeight.compareTo(b.workload.openWeight);
    });
    return result;
  }

  static double _roleFit(String position, List<String> aliases) {
    final normalized = _normalize(position);
    if (normalized.isEmpty) return 0;
    var best = 0.0;
    for (final alias in aliases) {
      final needle = _normalize(alias);
      if (normalized == needle) return 1;
      if (normalized.contains(needle) || needle.contains(normalized)) {
        best = max(best, .88);
      }
    }
    return best;
  }

  static _Workload _workload(String employeeId, List<TaskModel> tasks) {
    var weight = 0.0;
    var overdue = 0;
    var total = 0;
    var done = 0;
    for (final task in tasks) {
      if (task.effectiveResponsibleEmployeeId != employeeId) continue;
      total++;
      if (task.status == TaskStatus.done) {
        done++;
        continue;
      }
      weight += switch (task.status) {
        TaskStatus.inProgress => 1.35,
        TaskStatus.review => 1.05,
        TaskStatus.backlog => .80,
        TaskStatus.done => 0,
      };
      weight += switch (task.priority) {
        TaskPriority.urgent => .55,
        TaskPriority.high => .30,
        TaskPriority.normal => .10,
        TaskPriority.low => 0,
      };
      if (task.isOverdue) {
        overdue++;
        weight += .45;
      }
    }
    return _Workload(weight, overdue, total, done);
  }

  static TaskPriority _priorityFor(
    AiTaskTemplate template,
    double need,
    AiBusinessSignal signal,
    AiTemplateLearning learning,
  ) {
    var index = template.basePriority.index;
    if (need >= .80) index++;
    if (template.trigger == AiTaskTrigger.businessPressure &&
        signal.pressureScore >= .70) {
      index++;
    }
    if (learning.accepted > 0 && learning.averagePriorityDelta.abs() >= .45) {
      index += learning.averagePriorityDelta.round();
    }
    return TaskPriority
        .values[index.clamp(0, TaskPriority.values.length - 1).toInt()];
  }

  static AiForecastImpact _impactFor(
    AiTaskTemplate template,
    AiBusinessSignal signal,
    AiTemplateLearning learning,
  ) {
    var index = template.forecastImpact.index;
    if (template.trigger == AiTaskTrigger.businessPressure &&
        signal.pressureScore >= .75) {
      index++;
    }
    if (learning.accepted > 0 && learning.averageImpactDelta.abs() >= .45) {
      index += learning.averageImpactDelta.round();
    }
    return AiForecastImpact
        .values[index.clamp(0, AiForecastImpact.values.length - 1).toInt()];
  }

  static double _confidence(
    AiTaskTemplate template,
    _TriggerNeed trigger,
    int eligiblePeople,
    AiTemplateLearning learning,
  ) {
    var value = .62 + trigger.score * .22;
    if (eligiblePeople == 1) value += .04;
    if (trigger.sourceTask != null) value += .08;
    if (template.trigger == AiTaskTrigger.businessPressure) value += .04;
    if (learning.decisions >= 3) {
      value += learning.accepted >= learning.rejected ? .03 : -.03;
    }
    return value.clamp(.45, .96).toDouble();
  }

  static DateTime _dueDate(DateTime now, TaskPriority priority,
      [double effortPoints = 1]) {
    final priorityDays = switch (priority) {
      TaskPriority.urgent => 1,
      TaskPriority.high => 2,
      TaskPriority.normal => 4,
      TaskPriority.low => 7,
    };
    final effortDays = effortPoints.ceil().clamp(1, 7);
    final days = max(priorityDays, effortDays);
    return DateTime(now.year, now.month, now.day).add(Duration(days: days));
  }

  static String _employeeEvidence(
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
    }
    if (load < 1) {
      return '${ranked.employee.displayName}: почти нет активной загрузки';
    }
    if (load <= 2.5) {
      return '${ranked.employee.displayName}: одна из самых низких текущих загрузок';
    }
    return '${ranked.employee.displayName}: лучший баланс роли и доступной ёмкости';
  }

  static String _businessPressureReason(AiBusinessSignal signal) {
    if (signal.recentIncome <= 0) {
      return 'За последние 30 дней не видно дохода — системе нужен следующий шаг, способный приблизить продажи.';
    }
    if (signal.recentNet <= 0) {
      return 'За последние 30 дней чистый денежный поток не положительный.';
    }
    if (signal.incomeGrowth < -0.12) {
      return 'Доход заметно снизился относительно предыдущего 30-дневного периода.';
    }
    if (signal.maximumCashRisk >= .25) {
      return 'Wesi Horizon видит повышенный риск кассового разрыва.';
    }
    return 'Финансовый тренд требует более сильного действия со стороны продаж.';
  }

  static List<String> _businessPressureEvidence(AiBusinessSignal signal) {
    final evidence = <String>[];
    if (signal.recentIncome <= 0) evidence.add('Доход за 30 дней: 0');
    if (signal.recentNet <= 0)
      evidence.add('Чистый поток за 30 дней: не выше 0');
    if (signal.incomeGrowth < -0.12) {
      evidence.add(
          'Изменение дохода к прошлым 30 дням: ${(signal.incomeGrowth * 100).round()}%');
    }
    if (!signal.forecastInsufficient && signal.forecastTrendPerDay < 0) {
      evidence.add('Тренд Wesi Horizon направлен вниз');
    }
    if (signal.maximumCashRisk >= .25) {
      evidence.add(
          'Риск кассового разрыва: ${(signal.maximumCashRisk * 100).round()}%');
    }
    if (signal.runwayDays != null && signal.runwayDays! <= 45) {
      evidence.add('Оценочный запас ликвидности: ${signal.runwayDays} дн.');
    }
    return evidence;
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
      .trim();
}

class _TriggerNeed {
  final bool needed;
  final double score;
  final String whyNow;
  final List<String> evidence;
  final TaskModel? sourceTask;

  const _TriggerNeed({
    required this.needed,
    required this.score,
    required this.whyNow,
    required this.evidence,
    this.sourceTask,
  });

  const _TriggerNeed.no()
      : needed = false,
        score = 0,
        whyNow = '',
        evidence = const [],
        sourceTask = null;
}

class _RankedEmployee {
  final EmployeeModel employee;
  final double score;
  final _Workload workload;

  const _RankedEmployee(this.employee, this.score, this.workload);
}

class _Workload {
  final double openWeight;
  final int overdue;
  final int total;
  final int done;

  const _Workload(this.openWeight, this.overdue, this.total, this.done);
}
