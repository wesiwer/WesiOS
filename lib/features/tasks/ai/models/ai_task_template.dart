import '../../models/task_model.dart';

enum AiTaskCategory {
  production,
  design,
  sales,
  marketing,
  content,
  customer,
  finance,
  operations,
  quality,
  product,
  technology,
}

enum AiTaskTrigger {
  cadence,
  businessPressure,
  completionChain,
  workloadGap,
  hygiene,
}

enum AiForecastImpact { low, medium, high, critical }

class AiTaskTemplate {
  final String id;
  final AiTaskCategory category;
  final AiTaskTrigger trigger;
  final String title;
  final String description;
  final List<String> roleAliases;
  final List<String> taskKeywords;
  final List<String> organizationHints;
  final int cadenceDays;
  final int minRestDays;
  final int cooldownDays;
  final double effortPoints;
  final TaskPriority basePriority;
  final AiForecastImpact forecastImpact;
  final AiTaskCategory? followsCategory;
  final int? quantity;

  const AiTaskTemplate({
    required this.id,
    required this.category,
    required this.trigger,
    required this.title,
    required this.description,
    required this.roleAliases,
    required this.taskKeywords,
    this.organizationHints = const [],
    this.cadenceDays = 7,
    this.minRestDays = 0,
    this.cooldownDays = 5,
    this.effortPoints = 1,
    this.basePriority = TaskPriority.normal,
    this.forecastImpact = AiForecastImpact.medium,
    this.followsCategory,
    this.quantity,
  });
}

extension AiTaskCategoryLabel on AiTaskCategory {
  String get ru => switch (this) {
        AiTaskCategory.production => 'Продакшн',
        AiTaskCategory.design => 'Дизайн',
        AiTaskCategory.sales => 'Продажи',
        AiTaskCategory.marketing => 'Маркетинг',
        AiTaskCategory.content => 'Контент',
        AiTaskCategory.customer => 'Клиенты',
        AiTaskCategory.finance => 'Финансы',
        AiTaskCategory.operations => 'Операционка',
        AiTaskCategory.quality => 'Качество',
        AiTaskCategory.product => 'Продукт',
        AiTaskCategory.technology => 'Технологии',
      };
}

extension AiForecastImpactLabel on AiForecastImpact {
  String get ru => switch (this) {
        AiForecastImpact.low => 'Низкое',
        AiForecastImpact.medium => 'Среднее',
        AiForecastImpact.high => 'Высокое',
        AiForecastImpact.critical => 'Критическое',
      };
}
