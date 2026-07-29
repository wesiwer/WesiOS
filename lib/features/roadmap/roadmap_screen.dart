import 'package:flutter/material.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/widgets/module_scaffold.dart';

/// Roadmap — план проектов во времени (диаграмма Ганта).
class RoadmapScreen extends StatelessWidget {
  const RoadmapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    return ModuleScaffold(
      title: ru ? 'Roadmap' : 'Roadmap',
      subtitle: ru
          ? 'Проекты и этапы во времени — что за чем и когда'
          : 'Projects and milestones over time — what follows what, and when',
      icon: Icons.timeline,
      stage: ModuleStage.planned,
      plannedFeatures: [
        ru
            ? 'Диаграмма Ганта: полосы этапов по календарной шкале'
            : 'Gantt chart: milestone bars across a calendar axis',
        ru
            ? 'Зависимости между этапами («начать после»)'
            : 'Dependencies between milestones ("starts after")',
        ru
            ? 'Вехи и контрольные точки с датами'
            : 'Milestones and checkpoints with dates',
        ru
            ? 'Текущий прогресс каждого этапа в процентах'
            : 'Live progress percentage per milestone',
        ru
            ? 'Связь этапов с задачами из «Задач»'
            : 'Milestones linked to items in Tasks',
      ],
      child: StubBlock(
        icon: Icons.view_timeline,
        height: 220,
        label: ru
            ? 'Полосы этапов по горизонтальной шкале времени'
            : 'Milestone bars along a horizontal time axis',
      ),
    );
  }
}
