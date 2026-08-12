class AiTemplateLearning {
  final int accepted;
  final int rejected;
  final int snoozed;
  final double averagePriorityDelta;
  final double averageImpactDelta;
  final Map<String, int> acceptedAssignees;

  const AiTemplateLearning({
    this.accepted = 0,
    this.rejected = 0,
    this.snoozed = 0,
    this.averagePriorityDelta = 0,
    this.averageImpactDelta = 0,
    this.acceptedAssignees = const {},
  });

  int get decisions => accepted + rejected + snoozed;

  /// Human feedback is deliberately bounded. Wesi AI may learn that a class
  /// of suggestions is useful or annoying, but it may not make an important
  /// business signal disappear solely because of a few historical clicks.
  double get needMultiplier {
    if (decisions == 0) return 1;
    final positive = accepted * 1.0;
    final negative = rejected * .85 + snoozed * .30;
    final raw = 1 + (positive - negative) / (decisions + 3) * .32;
    return raw.clamp(.68, 1.22).toDouble();
  }

  double assigneeBoost(String employeeId) {
    final count = acceptedAssignees[employeeId] ?? 0;
    if (count == 0 || accepted == 0) return 0;
    final share = count / accepted;
    return (.10 * share).clamp(0.0, .10).toDouble();
  }
}

class AiLearningProfile {
  final Map<String, AiTemplateLearning> templates;

  const AiLearningProfile({this.templates = const {}});

  AiTemplateLearning forTemplate(String templateId) =>
      templates[templateId] ?? const AiTemplateLearning();
}
