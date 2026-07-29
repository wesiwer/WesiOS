import 'package:flutter/material.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/widgets/module_scaffold.dart';

/// Аналитика — сводная картина по всем модулям.
///
/// Финансовая часть уже живёт в Treasury (там настоящие графики и прогноз);
/// этот раздел задуман как верхнеуровневый срез, объединяющий финансы,
/// задачи и клиентов.
class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    return ModuleScaffold(
      title: ru ? 'Аналитика' : 'Analytics',
      subtitle: ru
          ? 'Сводная картина бизнеса: деньги, работа, клиенты в одном месте'
          : 'The whole business at a glance: money, work, and clients',
      icon: Icons.analytics,
      stage: ModuleStage.planned,
      plannedFeatures: [
        ru
            ? 'Ключевые показатели за период с изменением к прошлому'
            : 'Headline metrics for a period, with change vs. the previous one',
        ru
            ? 'Выручка и расходы по месяцам и категориям'
            : 'Revenue and costs by month and by category',
        ru
            ? 'Продуктивность: закрытые задачи, сроки, просрочки'
            : 'Throughput: tasks closed, deadlines met and missed',
        ru
            ? 'Воронка клиентов из CRM'
            : 'Client funnel pulled from CRM',
        ru
            ? 'Экспорт отчёта в PDF'
            : 'Export a report to PDF',
        ru
            ? 'Финансовые графики и прогноз уже работают в Wesi Treasury'
            : 'Financial charts and forecasting already live in Wesi Treasury',
      ],
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: StubBlock(
                  icon: Icons.trending_up,
                  height: 90,
                  label: ru ? 'Выручка' : 'Revenue',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StubBlock(
                  icon: Icons.trending_down,
                  height: 90,
                  label: ru ? 'Расходы' : 'Costs',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StubBlock(
                  icon: Icons.speed,
                  height: 90,
                  label: ru ? 'Продуктивность' : 'Throughput',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StubBlock(
            icon: Icons.bar_chart,
            height: 170,
            label: ru
                ? 'Сводный график по месяцам'
                : 'Combined month-over-month chart',
          ),
        ],
      ),
    );
  }
}
