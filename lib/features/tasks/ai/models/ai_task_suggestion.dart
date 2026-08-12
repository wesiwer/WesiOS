import '../../models/task_model.dart';
import 'ai_task_template.dart';

class AiTaskSuggestion {
  final String id;
  final String fingerprint;
  final String templateId;
  final AiTaskCategory category;
  final String organizationId;
  final String title;
  final String description;
  final String? assigneeId;
  final List<String> alternativeAssigneeIds;
  final TaskPriority priority;
  final AiForecastImpact forecastImpact;
  final double needScore;
  final double confidence;
  final double effortPoints;
  final DateTime? dueDate;
  final String whyNow;
  final List<String> evidence;
  final String? sourceTaskId;

  const AiTaskSuggestion({
    required this.id,
    required this.fingerprint,
    required this.templateId,
    required this.category,
    required this.organizationId,
    required this.title,
    required this.description,
    required this.assigneeId,
    this.alternativeAssigneeIds = const [],
    required this.priority,
    required this.forecastImpact,
    required this.needScore,
    required this.confidence,
    required this.effortPoints,
    this.dueDate,
    required this.whyNow,
    this.evidence = const [],
    this.sourceTaskId,
  });

  AiTaskSuggestion copyWith({
    String? title,
    String? description,
    String? assigneeId,
    bool clearAssignee = false,
    TaskPriority? priority,
    AiForecastImpact? forecastImpact,
    DateTime? dueDate,
    bool clearDueDate = false,
  }) =>
      AiTaskSuggestion(
        id: id,
        fingerprint: fingerprint,
        templateId: templateId,
        category: category,
        organizationId: organizationId,
        title: title ?? this.title,
        description: description ?? this.description,
        assigneeId: clearAssignee ? null : (assigneeId ?? this.assigneeId),
        alternativeAssigneeIds: alternativeAssigneeIds,
        priority: priority ?? this.priority,
        forecastImpact: forecastImpact ?? this.forecastImpact,
        needScore: needScore,
        confidence: confidence,
        effortPoints: effortPoints,
        dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
        whyNow: whyNow,
        evidence: evidence,
        sourceTaskId: sourceTaskId,
      );
}

class AiBusinessSignal {
  final bool financeAvailable;
  final double recentIncome;
  final double previousIncome;
  final double recentNet;
  final double incomeGrowth;
  final double forecastTrendPerDay;
  final double maximumCashRisk;
  final int? runwayDays;
  final bool forecastInsufficient;

  const AiBusinessSignal({
    this.financeAvailable = false,
    this.recentIncome = 0,
    this.previousIncome = 0,
    this.recentNet = 0,
    this.incomeGrowth = 0,
    this.forecastTrendPerDay = 0,
    this.maximumCashRisk = 0,
    this.runwayDays,
    this.forecastInsufficient = true,
  });

  bool get salesPressure => financeAvailable &&
      (recentIncome <= 0 ||
          recentNet <= 0 ||
          incomeGrowth < -0.12 ||
          forecastTrendPerDay < 0 ||
          maximumCashRisk >= 0.25);

  double get pressureScore {
    if (!financeAvailable) return 0;
    var score = 0.0;
    if (recentIncome <= 0) score += .30;
    if (recentNet <= 0) score += .25;
    if (incomeGrowth < -0.12) score += .20;
    if (forecastTrendPerDay < 0) score += .15;
    if (maximumCashRisk >= .25) score += .20;
    if (runwayDays != null && runwayDays! <= 45) score += .20;
    return score.clamp(0.0, 1.0).toDouble();
  }
}

class AiTaskAnalysisResult {
  final List<AiTaskSuggestion> suggestions;
  final AiBusinessSignal businessSignal;
  final DateTime analyzedAt;

  const AiTaskAnalysisResult({
    required this.suggestions,
    required this.businessSignal,
    required this.analyzedAt,
  });
}
