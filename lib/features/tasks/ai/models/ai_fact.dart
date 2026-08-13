import 'dart:math';

import '../../models/task_model.dart';
import 'ai_task_template.dart';

/// Что именно система увидела в данных приложения.
///
/// Шаблон срабатывает по таймеру: «давно не было задач такого типа».
/// Факт срабатывает по конкретному объекту: вот этот клиент, вот эта сделка,
/// вот этот бит. Разница принципиальная — у факта есть имя, свой срок и
/// проверяемое основание, поэтому предложение из факта можно обсуждать, а
/// предложение из шаблона приходится принимать на веру.
enum AiFactKind {
  clientFollowUpOverdue,
  clientNeverContacted,
  dealCloseDatePassed,
  dealStalled,
  dealWithoutOwner,
  roadmapItemOverdue,
  roadmapItemBlocked,
  roadmapDeadlineNear,
  beatMissingCover,
  beatMissingMaster,
  beatStalled,
  leaseExpiring,
  leaseExpired,
  taskOverdue,
  taskStuckInReview,
  taskWithoutOwner,
  fileRequestWaiting,
  recurringPaymentDue,
}

/// Наблюдение о конкретном объекте: что именно не так и насколько это срочно.
///
/// Срочность здесь не константа из таблицы, а число, посчитанное из самих
/// данных: сколько дней просрочено и сколько денег на кону относительно
/// обычного масштаба этой организации.
class WesiAiFact {
  final AiFactKind kind;
  final AiTaskCategory category;

  /// Идентификатор реального объекта — по нему предложение не задваивается.
  final String subjectId;

  /// Имя объекта в том виде, в каком его знает человек.
  final String subjectTitle;

  final String title;
  final String description;

  /// 0..1. Считается из просрочки и суммы, а не назначается вручную.
  final double urgency;

  /// Срок берётся у самого объекта, а не из таблицы «важность → дни».
  final DateTime? deadline;

  /// Естественный исполнитель: владелец сделки, автор бита, ответственный
  /// за веху. Если он есть, спрашивать «кому поручить» уже не нужно.
  final String? ownerEmployeeId;

  /// Кому это подходит по роли, если естественного владельца нет.
  final List<String> roleAliases;

  final List<String> evidence;
  final String whyNow;
  final AiForecastImpact impact;
  final double effortPoints;

  /// Сумма, которая стоит за фактом. Нужна для сравнения фактов между собой.
  final double money;

  const WesiAiFact({
    required this.kind,
    required this.category,
    required this.subjectId,
    required this.subjectTitle,
    required this.title,
    required this.description,
    required this.urgency,
    required this.whyNow,
    this.deadline,
    this.ownerEmployeeId,
    this.roleAliases = const [],
    this.evidence = const [],
    this.impact = AiForecastImpact.medium,
    this.effortPoints = 1,
    this.money = 0,
  });

  /// Метка, которой помечается созданная задача. По ней система понимает,
  /// что по этому объекту работа уже поставлена, и перестаёт предлагать.
  String get tag => 'wesi-ai:fact:${kind.name}:$subjectId';

  /// Важность выводится из срочности, а не задаётся заранее: одна и та же
  /// просрочка на второй день и на двадцатый — это разные задачи.
  TaskPriority get priority {
    if (urgency >= .85) return TaskPriority.urgent;
    if (urgency >= .62) return TaskPriority.high;
    if (urgency >= .38) return TaskPriority.normal;
    return TaskPriority.low;
  }
}

/// Общие правила счёта, одинаковые для всех источников фактов.
class AiFactMath {
  AiFactMath._();

  /// Насыщающаяся кривая просрочки.
  ///
  /// Линейный рост врёт в обе стороны: на второй день просрочки он даёт
  /// почти ноль, а на сотый — бесконечность. Здесь первый день уже заметен,
  /// а разница между «просрочено 40 дней» и «просрочено 60» почти исчезает —
  /// потому что в жизни она и правда почти исчезает.
  static double lateness(int days, {double halfLife = 6}) {
    if (days <= 0) return 0;
    return 1 - pow(0.5, days / halfLife).toDouble();
  }

  /// Приближение срока: чем ближе дедлайн, тем выше, но без просрочки.
  static double approaching(int daysLeft, {int horizon = 14}) {
    if (daysLeft <= 0) return 1;
    if (daysLeft >= horizon) return 0;
    return 1 - daysLeft / horizon;
  }

  /// Вес суммы относительно обычного масштаба этой организации.
  ///
  /// Абсолютные пороги («больше 100 000 — важно») ломаются на каждой второй
  /// организации: у одной весь оборот 30 000, у другой это цена одного бита.
  /// Поэтому сумма сравнивается с масштабом самой организации и всегда
  /// остаётся в пределах 0..1.
  static double moneyWeight(double amount, double scale) {
    if (amount <= 0) return 0;
    if (scale <= 0) return .5;
    return amount / (amount + scale);
  }

  /// Масштаб организации — медиана сумм, а не среднее.
  ///
  /// Одна крупная сделка сдвигает среднее так, что все остальные становятся
  /// «мелочью». Медиана этого не делает.
  static double scaleOf(Iterable<double> amounts) {
    final values = amounts.where((value) => value > 0).toList()..sort();
    if (values.isEmpty) return 0;
    final middle = values.length ~/ 2;
    if (values.length.isOdd) return values[middle];
    return (values[middle - 1] + values[middle]) / 2;
  }

  /// Сведение нескольких сигналов в одну срочность.
  ///
  /// Сумма усиливает просрочку, но не заменяет её: дорогая сделка со сроком
  /// послезавтра не должна обгонять дешёвую, просроченную на месяц.
  static double blend(double base, double money, {double moneyShare = .30}) {
    final value = base * (1 - moneyShare) + base * money * moneyShare * 2;
    return value.clamp(0.0, 1.0).toDouble();
  }

  /// Календарные дни между датами — без ловушки перевода часов.
  static int daysBetween(DateTime from, DateTime to) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  /// Русское склонение дней: «1 день», «2 дня», «5 дней».
  static String days(int value) {
    final n = value.abs();
    final tail = n % 10;
    final teen = n % 100;
    if (teen >= 11 && teen <= 14) return '$value дней';
    if (tail == 1) return '$value день';
    if (tail >= 2 && tail <= 4) return '$value дня';
    return '$value дней';
  }
}
