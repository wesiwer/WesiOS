import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_avatar.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import '../organizations/services/organization_access_service.dart';
import '../organizations/services/organization_context.dart';
import '../tasks/models/task_model.dart';
import '../tasks/services/task_service.dart';
import 'models/employee_model.dart';
import 'services/team_service.dart';

/// Реальные показатели людей, рассчитанные только по существующим задачам.
/// Никаких случайных/demo финансовых цифр здесь больше нет.
class TeamStatsScreen extends StatefulWidget {
  const TeamStatsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TeamStatsScreen()),
      );

  @override
  State<TeamStatsScreen> createState() => _TeamStatsScreenState();
}

class _TeamStatsScreenState extends State<TeamStatsScreen> {
  bool get _ru => WesiLocale.isRussian;
  List<TaskModel> _tasks = const [];
  int _loadEpoch = 0;

  List<EmployeeModel> get _people {
    final p = TeamService.currentPermissions;
    if (p.canSeeOthersStats) return TeamService.all;
    final me = TeamService.current;
    return me == null ? const [] : [me];
  }

  @override
  void initState() {
    super.initState();
    TeamService.revision.addListener(_changed);
    TaskService.revision.addListener(_changed);
    OrganizationContext.revision.addListener(_changed);
    OrganizationAccessService.revision.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    TeamService.revision.removeListener(_changed);
    TaskService.revision.removeListener(_changed);
    OrganizationContext.revision.removeListener(_changed);
    OrganizationAccessService.revision.removeListener(_changed);
    super.dispose();
  }

  void _changed() => _load();

  Future<void> _load() async {
    final epoch = ++_loadEpoch;
    final tasks = await TaskService().getAll();
    if (mounted && epoch == _loadEpoch) {
      setState(() => _tasks = tasks);
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    final everyone = TeamService.currentPermissions.canSeeOthersStats;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  8, kTitleBarInset + 12, kHasCustomTitleBar ? 148 : 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        WesiTitle(_ru ? 'Показатели' : 'Performance', size: 22),
                        const SizedBox(height: 2),
                        Text(
                          everyone
                              ? (_ru ? 'Реальные данные по задачам' : 'Real task data')
                              : (_ru ? 'Только ваши реальные данные' : 'Your real data only'),
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surface.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.glassBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.verified_outlined,
                        size: 16, color: AppTheme.accentGreen),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _ru
                            ? 'Показатели считаются из реально созданных задач. Если данных нет, WesiOS ничего не генерирует и показывает «данных пока нет».'
                            : 'Metrics are calculated from actual tasks. WesiOS no longer generates placeholder numbers.',
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.45,
                            color: AppTheme.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: people.length,
                itemBuilder: (context, i) => _card(people[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(EmployeeModel employee) {
    final assigned = _tasks.where((task) => task.assignee == employee.id).toList();
    final done = assigned.where((task) => task.status == TaskStatus.done).length;
    final open = assigned.length - done;
    final overdue = assigned.where((task) => task.isOverdue).length;
    final completion = assigned.isEmpty ? 0.0 : done / assigned.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                WesiAvatar(size: 36, index: employee.avatarIndex, photo: employee.photo),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(employee.displayName,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary)),
                      if (employee.position.isNotEmpty)
                        Text(employee.position,
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
            if (assigned.isEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _ru ? 'Данных пока нет — сотруднику ещё не назначены задачи.' : 'No data yet — no tasks are assigned.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _metric(_ru ? 'Назначено' : 'Assigned', '${assigned.length}'),
                  const SizedBox(width: 8),
                  _metric(_ru ? 'Завершено' : 'Done', '$done'),
                  const SizedBox(width: 8),
                  _metric(_ru ? 'В работе' : 'Open', '$open'),
                  const SizedBox(width: 8),
                  _metric(_ru ? 'Просрочено' : 'Overdue', '$overdue'),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: completion.clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: AppTheme.surfaceLight,
                        valueColor: AlwaysStoppedAnimation(AppTheme.accentGreen),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(completion * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLight.withOpacity(0.5),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
              const SizedBox(height: 3),
              Text(value,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
            ],
          ),
        ),
      );
}
