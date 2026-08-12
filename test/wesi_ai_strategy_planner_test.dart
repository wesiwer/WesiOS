import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/tasks/ai/models/ai_task_suggestion.dart';
import 'package:wesios/features/tasks/ai/models/ai_task_template.dart';
import 'package:wesios/features/tasks/ai/services/task_template_catalog.dart';
import 'package:wesios/features/tasks/ai/services/wesi_ai_strategy_planner.dart';
import 'package:wesios/features/tasks/models/task_model.dart';

void main() {
  final now = DateTime(2026, 8, 12, 12);

  TaskModel task({
    required String id,
    required String title,
    required AiTaskCategory category,
    TaskStatus status = TaskStatus.done,
    DateTime? createdAt,
  }) =>
      TaskModel(
        id: id,
        title: title,
        status: status,
        priority: TaskPriority.normal,
        createdAt: createdAt ?? now.subtract(const Duration(days: 2)),
        organizationId: 'org_wesi_beats',
        tags: ['wesi-ai:category:${category.name}'],
      );

  AiTaskSuggestion suggestion({
    required String templateId,
    required AiTaskCategory category,
    double need = .70,
    AiForecastImpact impact = AiForecastImpact.medium,
  }) =>
      AiTaskSuggestion(
        id: templateId,
        fingerprint: 'fp:$templateId',
        templateId: templateId,
        category: category,
        organizationId: 'org_wesi_beats',
        title: templateId,
        description: '',
        assigneeId: 'employee',
        priority: TaskPriority.normal,
        forecastImpact: impact,
        needScore: need,
        confidence: .8,
        effortPoints: 1,
        whyNow: 'test',
      );

  test('detects downstream bottleneck after production output', () {
    final tasks = [
      task(id: 'beat-1', title: 'Бит 1', category: AiTaskCategory.production),
      task(id: 'beat-2', title: 'Бит 2', category: AiTaskCategory.production),
      task(id: 'beat-3', title: 'Бит 3', category: AiTaskCategory.production),
    ];

    final health = WesiAiStrategyPlanner.pipelineHealth(
      tasks: tasks,
      organizationName: 'Wesi Beats',
      organizationDescription: 'Продажа битов артистам',
      now: now,
    );

    expect(health.bottleneck, AiTaskCategory.quality);
    expect(health.imbalance, 1);
  });

  test('bottleneck task receives stronger strategic score', () {
    final tasks = [
      task(id: 'beat-1', title: 'Бит 1', category: AiTaskCategory.production),
      task(id: 'beat-2', title: 'Бит 2', category: AiTaskCategory.production),
    ];
    final health = WesiAiStrategyPlanner.pipelineHealth(
      tasks: tasks,
      organizationName: 'Wesi Beats',
      organizationDescription: 'Продажа битов артистам',
      now: now,
    );
    final qc = WesiAiStrategyPlanner.signalFor(
      template: WesiAiTaskCatalog.all
          .firstWhere((item) => item.id == 'beat_quality_check'),
      tasks: tasks,
      health: health,
      businessSignal: const AiBusinessSignal(),
      now: now,
    );

    expect(qc.strategicScore, greaterThan(.7));
    expect(qc.multiplier, greaterThan(1));
    expect(qc.reason, contains('цепочк'));
  });

  test('financial pressure favors sales over more production when stock exists', () {
    final tasks = [
      task(id: 'beat-1', title: 'Бит 1', category: AiTaskCategory.production),
      task(id: 'beat-2', title: 'Бит 2', category: AiTaskCategory.production),
      task(id: 'pub-1', title: 'Публикация', category: AiTaskCategory.operations),
    ];
    const business = AiBusinessSignal(
      financeAvailable: true,
      recentIncome: 0,
      previousIncome: 10000,
      recentNet: -2000,
      incomeGrowth: -1,
      forecastTrendPerDay: -50,
      maximumCashRisk: .35,
      forecastInsufficient: false,
    );
    final ranked = WesiAiStrategyPlanner.rank(
      suggestions: [
        suggestion(
          templateId: 'beat_create',
          category: AiTaskCategory.production,
          need: .84,
          impact: AiForecastImpact.low,
        ),
        suggestion(
          templateId: 'artist_outreach_20',
          category: AiTaskCategory.sales,
          need: .72,
          impact: AiForecastImpact.high,
        ),
      ],
      tasks: tasks,
      organizationId: 'org_wesi_beats',
      organizationName: 'Wesi Beats',
      organizationDescription: 'Продажа битов артистам',
      businessSignal: business,
      now: now,
    );

    expect(ranked.first.templateId, 'artist_outreach_20');
    expect(ranked.first.strategicScore, greaterThan(.6));
  });

  test('existing category backlog suppresses adding more work to same queue', () {
    final tasks = [
      for (var i = 0; i < 4; i++)
        task(
          id: 'sales-$i',
          title: 'Продажи $i',
          category: AiTaskCategory.sales,
          status: TaskStatus.inProgress,
        ),
    ];
    final health = WesiAiStrategyPlanner.pipelineHealth(
      tasks: tasks,
      organizationName: 'Wesi Beats',
      organizationDescription: 'Продажа битов артистам',
      now: now,
    );
    final signal = WesiAiStrategyPlanner.signalFor(
      template: WesiAiTaskCatalog.all
          .firstWhere((item) => item.id == 'artist_outreach_20'),
      tasks: tasks,
      health: health,
      businessSignal: const AiBusinessSignal(),
      now: now,
    );

    expect(signal.multiplier, lessThan(1));
    expect(signal.evidence.any((item) => item.contains('незавершённых')), isTrue);
  });

  test('recent repeated work reduces burst recommendations', () {
    final tasks = [
      task(
        id: 'outreach-1',
        title: 'Рассылка артистам',
        category: AiTaskCategory.sales,
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      task(
        id: 'outreach-2',
        title: '20 рассылок артистам',
        category: AiTaskCategory.sales,
        createdAt: now.subtract(const Duration(days: 3)),
      ),
    ];
    final health = WesiAiStrategyPlanner.pipelineHealth(
      tasks: tasks,
      organizationName: 'Wesi Beats',
      organizationDescription: 'Продажа битов артистам',
      now: now,
    );
    final signal = WesiAiStrategyPlanner.signalFor(
      template: WesiAiTaskCatalog.all
          .firstWhere((item) => item.id == 'artist_outreach_20'),
      tasks: tasks,
      health: health,
      businessSignal: const AiBusinessSignal(),
      now: now,
    );

    expect(signal.multiplier, lessThan(1));
    expect(signal.evidence.any((item) => item.contains('последние 7 дней')), isTrue);
  });
}
