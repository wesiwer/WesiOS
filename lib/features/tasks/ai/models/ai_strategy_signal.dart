import 'ai_task_template.dart';

class AiStrategySignal {
  final double multiplier;
  final double strategicScore;
  final String reason;
  final List<String> evidence;

  const AiStrategySignal({
    this.multiplier = 1,
    this.strategicScore = .5,
    this.reason = '',
    this.evidence = const [],
  });
}

class AiPipelineHealth {
  final String name;
  final Map<AiTaskCategory, int> completed30d;
  final Map<AiTaskCategory, int> open;
  final AiTaskCategory? bottleneck;
  final double imbalance;
  final String summary;

  const AiPipelineHealth({
    required this.name,
    this.completed30d = const {},
    this.open = const {},
    this.bottleneck,
    this.imbalance = 0,
    this.summary = '',
  });
}
