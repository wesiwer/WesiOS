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

/// Насколько сильно предложение поднимается в очереди.
///
/// Имя `forecastImpact` осталось от первой версии и обещало больше, чем
/// делает: в денежный прогноз это число не попадает и никогда не попадало.
/// Оно даёт 18 % веса в сортировке предложений — и всё. Деньги приходят в
/// Horizon от самих объектов (сделка CRM с ожидаемой датой закрытия,
/// лицензия на бит), причём только по той организации, чей прогноз открыт.
/// Поэтому в интерфейсе это называется значимостью, а не влиянием на
/// прогноз: подпись должна совпадать с тем, что происходит на самом деле.
extension AiForecastImpactLabel on AiForecastImpact {
  String get ru => switch (this) {
        AiForecastImpact.low => 'Низкая',
        AiForecastImpact.medium => 'Средняя',
        AiForecastImpact.high => 'Высокая',
        AiForecastImpact.critical => 'Критическая',
      };
}
