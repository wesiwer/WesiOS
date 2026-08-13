import 'dart:math';

import '../../models/task_model.dart';
import '../models/ai_strategy_signal.dart';
import '../models/ai_task_suggestion.dart';
import '../models/ai_task_template.dart';
import 'task_template_catalog.dart';
import 'wesi_ai_task_engine.dart';

class WesiAiStrategyPlanner {
  WesiAiStrategyPlanner._();

  static List<AiTaskSuggestion> rank({
    required List<AiTaskSuggestion> suggestions,
    required List<TaskModel> tasks,
    required String organizationId,
    required String organizationName,
    required String organizationDescription,
    required AiBusinessSignal businessSignal,
    required DateTime now,
  }) {
    if (suggestions.isEmpty) return suggestions;
    final scoped = tasks
        .where((task) => task.effectiveOrganizationId == organizationId)
        .toList();
    final health = pipelineHealth(
      tasks: scoped,
      organizationName: organizationName,
      organizationDescription: organizationDescription,
      now: now,
    );

    final enriched = suggestions.map((suggestion) {
      // Наблюдение о конкретном объекте не пересчитывается формой цепочки:
      // у просроченной сделки своя срочность, и «в этом направлении и так
      // много задач» её не отменяет.
      if (suggestion.isFact) return suggestion;
      final template = WesiAiTaskCatalog.all
          .where((item) => item.id == suggestion.templateId)
          .firstOrNull;
      final signal = template == null
          ? const AiStrategySignal()
          : signalFor(
              template: template,
              tasks: scoped,
              health: health,
              businessSignal: businessSignal,
              now: now,
            );
      final strategicNeed =
          (suggestion.needScore * signal.multiplier).clamp(0.0, 1.0).toDouble();
      final evidence = <String>[
        ...suggestion.evidence,
        ...signal.evidence.where((item) => !suggestion.evidence.contains(item)),
      ];
      return suggestion.copyWith(
        needScore: strategicNeed,
        strategicScore: signal.strategicScore,
        strategicReason: signal.reason,
        evidence: evidence,
      );
    }).toList();

    enriched.sort((a, b) {
      final grounding = b.groundingTier.compareTo(a.groundingTier);
      if (grounding != 0) return grounding;
      final aScore = _portfolioScore(a, businessSignal);
      final bScore = _portfolioScore(b, businessSignal);
      final score = bScore.compareTo(aScore);
      if (score != 0) return score;
      return b.needScore.compareTo(a.needScore);
    });

    // Portfolio anti-spam: do not allow one category to occupy the whole
    // strategic shortlist even if multiple templates in it score similarly.
    final result = <AiTaskSuggestion>[];
    final perCategory = <AiTaskCategory, int>{};
    for (final item in enriched) {
      final count = perCategory[item.category] ?? 0;
      if (count >= 2) continue;
      result.add(item);
      perCategory[item.category] = count + 1;
      if (result.length >= 5) break;
    }
    return result;
  }

  static AiPipelineHealth pipelineHealth({
    required List<TaskModel> tasks,
    required String organizationName,
    required String organizationDescription,
    required DateTime now,
  }) {
    final descriptor = _normalize('$organizationName $organizationDescription');
    final music = WesiAiTaskCatalog.musicHints
        .any((hint) => descriptor.contains(_normalize(hint)));
    final categories = music
        ? const [
            AiTaskCategory.production,
            AiTaskCategory.quality,
            AiTaskCategory.design,
            AiTaskCategory.operations,
            AiTaskCategory.sales,
          ]
        : const [
            AiTaskCategory.product,
            AiTaskCategory.operations,
            AiTaskCategory.marketing,
            AiTaskCategory.sales,
            AiTaskCategory.customer,
          ];

    final completed = <AiTaskCategory, int>{};
    final open = <AiTaskCategory, int>{};
    final start = now.subtract(const Duration(days: 30));
    for (final task in tasks) {
      final category = WesiAiTaskEngine.categoryOfTask(task);
      if (category == null) continue;
      if (task.status == TaskStatus.done && !task.createdAt.isBefore(start)) {
        completed[category] = (completed[category] ?? 0) + 1;
      } else if (task.status != TaskStatus.done) {
        open[category] = (open[category] ?? 0) + 1;
      }
    }

    AiTaskCategory? bottleneck;
    var maxGap = 0.0;
    for (var i = 1; i < categories.length; i++) {
      final upstream = completed[categories[i - 1]] ?? 0;
      final downstream = completed[categories[i]] ?? 0;
      if (upstream <= 0) continue;
      final gap = (upstream - downstream) / max(1, upstream);
      if (gap > maxGap && (open[categories[i]] ?? 0) <= 2) {
        maxGap = gap;
        bottleneck = categories[i];
      }
    }

    // No visible downstream work while upstream has output is a stronger
    // bottleneck than a simple cadence miss.
    String summary = '';
    if (bottleneck != null) {
      summary = music
          ? 'В цепочке битов накопился разрыв перед этапом «${bottleneck.ru}».'
          : 'В рабочей цепочке накопился разрыв перед этапом «${bottleneck.ru}».';
    }
    return AiPipelineHealth(
      name: music ? 'music-sales' : 'business-growth',
      completed30d: completed,
      open: open,
      bottleneck: bottleneck,
      imbalance: maxGap.clamp(0.0, 1.0).toDouble(),
      summary: summary,
    );
  }

  static AiStrategySignal signalFor({
    required AiTaskTemplate template,
    required List<TaskModel> tasks,
    required AiPipelineHealth health,
    required AiBusinessSignal businessSignal,
    required DateTime now,
  }) {
    var multiplier = 1.0;
    var score = .50;
    final evidence = <String>[];
    var reason = '';

    if (health.bottleneck == template.category) {
      multiplier += .28 * max(.45, health.imbalance);
      score += .30;
      reason = health.summary;
      evidence.add(
        'Стратегический разрыв цепочки: ${(health.imbalance * 100).round()}%',
      );
    }

    final categoryOpen = health.open[template.category] ?? 0;
    if (categoryOpen >= 3) {
      // A category with a queue is usually execution-constrained, not
      // idea-constrained. Avoid producing more work for the same bottleneck.
      multiplier -= .22;
      score -= .16;
      evidence.add('В этом направлении уже $categoryOpen незавершённых задач');
      if (reason.isEmpty) {
        reason =
            'Сначала выгоднее разгрузить уже поставленные задачи этого направления.';
      }
    }

    if (businessSignal.salesPressure) {
      if (template.category == AiTaskCategory.sales ||
          template.category == AiTaskCategory.customer) {
        multiplier += .22 * max(.50, businessSignal.pressureScore);
        score += .24;
        reason = reason.isEmpty
            ? 'Финансовое давление делает действия ближе к выручке стратегически сильнее.'
            : reason;
        evidence.add('Есть финансовое давление на рост выручки');
      } else if (template.category == AiTaskCategory.production &&
          (health.completed30d[AiTaskCategory.production] ?? 0) >= 2 &&
          (health.completed30d[AiTaskCategory.sales] ?? 0) == 0) {
        multiplier -= .18;
        score -= .10;
        evidence.add(
            'Есть готовый производственный поток, но нет недавней работы по продажам');
        if (reason.isEmpty) {
          reason =
              'Сейчас дополнительное производство слабее действия, которое монетизирует уже созданный запас.';
        }
      }
    }

    final recentSameTemplate = tasks.where((task) {
      if (task.tags.contains('wesi-ai:template:${template.id}')) return true;
      final text = _normalize('${task.title} ${task.description ?? ''}');
      return template.taskKeywords.any((keyword) {
        final normalized = _normalize(keyword);
        return normalized.length >= 3 && text.contains(normalized);
      });
    }).where((task) =>
        !task.createdAt.isBefore(now.subtract(const Duration(days: 7))));
    final burst = recentSameTemplate.length;
    if (burst >= 2) {
      multiplier -= min(.28, burst * .08);
      score -= min(.18, burst * .05);
      evidence.add(
          'Похожая работа уже выполнялась $burst раз(а) за последние 7 дней');
      if (reason.isEmpty) {
        reason =
            'Система снижает повторяемость, чтобы не превращать рекомендации в поток одинаковых задач.';
      }
    }

    if (reason.isEmpty) {
      reason =
          'Предложение закрывает актуальную потребность без более сильного обнаруженного узкого места.';
    }
    return AiStrategySignal(
      multiplier: multiplier.clamp(.55, 1.45).toDouble(),
      strategicScore: score.clamp(0.0, 1.0).toDouble(),
      reason: reason,
      evidence: evidence,
    );
  }

  static double _portfolioScore(
    AiTaskSuggestion suggestion,
    AiBusinessSignal businessSignal,
  ) {
    final impact = suggestion.forecastImpact.index /
        max(1, AiForecastImpact.values.length - 1);
    final priority =
        suggestion.priority.index / max(1, TaskPriority.values.length - 1);
    var score = suggestion.needScore * .40 +
        suggestion.strategicScore * .34 +
        impact * .18 +
        priority * .08;
    if (businessSignal.salesPressure &&
        suggestion.category == AiTaskCategory.sales) {
      score += .08;
    }
    return score;
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
      .trim();
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
