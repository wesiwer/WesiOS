import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import '../tasks/models/task_model.dart';
import '../tasks/services/task_service.dart';
import 'models/roadmap_models.dart';
import 'services/roadmap_service.dart';

class RoadmapScreen extends StatefulWidget {
  const RoadmapScreen({super.key});

  @override
  State<RoadmapScreen> createState() => _RoadmapScreenState();
}

class _RoadmapScreenState extends State<RoadmapScreen> {
  int _tab = 0;
  String? _projectId;
  bool _showArchived = false;

  bool get _ru => WesiLocale.isRussian;

  Future<_RoadmapData> _load() async {
    final projects = await RoadmapService.projects();
    final items = await RoadmapService.items();
    final summary = await RoadmapService.summary();
    final tasks = await TaskService().getAll();
    return _RoadmapData(
      projects: projects,
      items: items,
      summary: summary,
      tasks: tasks,
    );
  }

  Future<void> _addProject() async {
    final value = await _ProjectEditorSheet.show(context);
    if (value != null) {
      await RoadmapService.saveProject(value);
      if (mounted) setState(() => _projectId = value.id);
    }
  }

  Future<void> _addItem(_RoadmapData data, {RoadmapItemKind? kind}) async {
    final projects = data.projects.where((value) => !value.archived).toList();
    if (projects.isEmpty) {
      _message(_ru
          ? 'Сначала создайте проект.'
          : 'Create a project first.');
      return;
    }
    final selected = data.projectById(_projectId) ?? projects.first;
    final item = await _ItemEditorSheet.show(
      context,
      project: selected,
      existingItems: data.itemsForProject(selected.id),
      tasks: data.tasks,
      initialKind: kind,
    );
    if (item != null) await RoadmapService.saveItem(item);
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, _, __) => ValueListenableBuilder<int>(
        valueListenable: RoadmapService.revision,
        builder: (context, __, ___) => ValueListenableBuilder<int>(
          valueListenable: TaskService.revision,
          builder: (context, ___, ____) => FutureBuilder<_RoadmapData>(
            future: _load(),
            builder: (context, snapshot) {
              final data = snapshot.data;
              if (data != null) _ensureSelected(data);
              return Scaffold(
                backgroundColor: AppTheme.background,
                appBar: AppBar(
                  backgroundColor: AppTheme.background,
                  title: const WesiTitle('Roadmap', size: 20),
                  actions: [
                    if (data != null)
                      PopupMenuButton<String>(
                        tooltip: _ru ? 'Добавить' : 'Add',
                        icon: Icon(Icons.add_circle_outline,
                            color: AppTheme.accent),
                        onSelected: (value) {
                          if (value == 'project') _addProject();
                          if (value == 'phase') {
                            _addItem(data, kind: RoadmapItemKind.phase);
                          }
                          if (value == 'milestone') {
                            _addItem(data, kind: RoadmapItemKind.milestone);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'project',
                            child: _menu(Icons.folder_open_outlined,
                                _ru ? 'Новый проект' : 'New project'),
                          ),
                          PopupMenuItem(
                            value: 'phase',
                            child: _menu(Icons.view_timeline_outlined,
                                _ru ? 'Новый этап' : 'New phase'),
                          ),
                          PopupMenuItem(
                            value: 'milestone',
                            child: _menu(Icons.diamond_outlined,
                                _ru ? 'Новая веха' : 'New milestone'),
                          ),
                        ],
                      ),
                    SizedBox(width: kHasCustomTitleBar ? 140 : 4),
                  ],
                ),
                floatingActionButton: data == null
                    ? null
                    : FloatingActionButton.extended(
                        onPressed: () => _addItem(data),
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                        icon: const Icon(Icons.add_task),
                        label: Text(_ru ? 'Этап' : 'Phase'),
                      ),
                body: snapshot.connectionState == ConnectionState.waiting &&
                        data == null
                    ? Center(
                        child:
                            CircularProgressIndicator(color: AppTheme.accent))
                    : data == null
                        ? Center(
                            child: Text('${_ru ? 'Ошибка' : 'Error'}: ${snapshot.error}'))
                        : Column(
                            children: [
                              _summary(data.summary),
                              _projectPicker(data),
                              _tabs(),
                              Expanded(
                                child: IndexedStack(
                                  index: _tab,
                                  children: [
                                    _overview(data),
                                    _timeline(data),
                                    _list(data),
                                  ],
                                ),
                              ),
                            ],
                          ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _ensureSelected(_RoadmapData data) {
    final visible = data.projects
        .where((value) => _showArchived || !value.archived)
        .toList();
    if (visible.isEmpty) {
      _projectId = null;
      return;
    }
    if (_projectId == null || !visible.any((value) => value.id == _projectId)) {
      _projectId = visible.first.id;
    }
  }

  Widget _menu(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.accent),
          const SizedBox(width: 10),
          Text(text),
        ],
      );

  Widget _summary(RoadmapSummary summary) {
    final metrics = [
      _RoadMetric(
        Icons.folder_copy_outlined,
        _ru ? 'Активные проекты' : 'Active projects',
        '${summary.activeProjects}',
        _ru ? '${summary.projects} всего' : '${summary.projects} total',
      ),
      _RoadMetric(
        Icons.auto_graph,
        _ru ? 'Общий прогресс' : 'Overall progress',
        '${(summary.averageProgress * 100).round()}%',
        _ru ? '${summary.completed}/${summary.items} завершено' : '${summary.completed}/${summary.items} complete',
      ),
      _RoadMetric(
        Icons.diamond_outlined,
        _ru ? 'Контрольные точки' : 'Milestones',
        '${summary.milestones}',
        _ru ? 'вех в планах' : 'planned checkpoints',
      ),
      _RoadMetric(
        Icons.warning_amber_rounded,
        _ru ? 'Требуют внимания' : 'Need attention',
        '${summary.blocked + summary.overdue}',
        _ru ? '${summary.blocked} блоков · ${summary.overdue} просрочек' : '${summary.blocked} blocked · ${summary.overdue} overdue',
        warning: summary.blocked + summary.overdue > 0,
      ),
    ];
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        itemCount: metrics.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, index) => _metric(metrics[index]),
      ),
    );
  }

  Widget _metric(_RoadMetric value) {
    final color = value.warning ? AppTheme.accentRed : AppTheme.accent;
    return Container(
      width: 220,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(.56),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value.warning
              ? AppTheme.accentRed.withOpacity(.32)
              : AppTheme.glassBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: color.withOpacity(.12),
            ),
            child: Icon(value.icon, size: 19, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
                const SizedBox(height: 2),
                Text(value.value,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textPrimary)),
                Text(value.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9.5, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _projectPicker(_RoadmapData data) {
    final visible = data.projects
        .where((value) => _showArchived || !value.archived)
        .toList();
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: visible.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final project = visible[index];
                final selected = project.id == _projectId;
                final color = Color(project.colorValue);
                return InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: () => setState(() => _projectId = project.id),
                  onLongPress: () => _editProject(project),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    constraints: const BoxConstraints(maxWidth: 230),
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      color: selected
                          ? color.withOpacity(.14)
                          : AppTheme.surface.withOpacity(.36),
                      border: Border.all(
                        color: selected
                            ? color.withOpacity(.5)
                            : AppTheme.glassBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration:
                              BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(project.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: selected
                                      ? AppTheme.textPrimary
                                      : AppTheme.textMuted)),
                        ),
                        if (project.archived) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.archive_outlined,
                              size: 14, color: AppTheme.textMuted),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: _ru ? 'Показывать архив' : 'Show archived',
            onPressed: () => setState(() => _showArchived = !_showArchived),
            icon: Icon(
              _showArchived ? Icons.inventory_2 : Icons.inventory_2_outlined,
              color: _showArchived ? AppTheme.accent : AppTheme.textMuted,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _tabs() {
    final tabs = [
      (_ru ? 'Обзор' : 'Overview', Icons.dashboard_outlined),
      (_ru ? 'Шкала времени' : 'Timeline', Icons.view_timeline_outlined),
      (_ru ? 'Список' : 'List', Icons.format_list_bulleted),
    ];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final selected = index == _tab;
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _tab = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: selected
                    ? AppTheme.accent.withOpacity(.15)
                    : AppTheme.surface.withOpacity(.34),
                border: Border.all(
                  color: selected
                      ? AppTheme.accent.withOpacity(.5)
                      : AppTheme.glassBorder,
                ),
              ),
              child: Row(
                children: [
                  Icon(tabs[index].$2,
                      size: 16,
                      color: selected ? AppTheme.accent : AppTheme.textMuted),
                  const SizedBox(width: 7),
                  Text(tabs[index].$1,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w500,
                          color: selected
                              ? AppTheme.textPrimary
                              : AppTheme.textMuted)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _overview(_RoadmapData data) {
    if (data.projects.isEmpty) return _emptyProjects();
    final project = data.projectById(_projectId);
    if (project == null) return _emptyProjects();
    final items = data.itemsForProject(project.id);
    final progress = _projectProgress(items);
    final next = items
        .where((value) => !value.isDone)
        .toList()
      ..sort((a, b) => a.endDate.compareTo(b.endDate));
    final blocked = items.where((value) => value.isBlocked).toList();
    final overdue = items.where((value) => value.isOverdue).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _projectHero(project, items, progress),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 800;
            final schedule = _panel(
              _ru ? 'Ближайшие этапы' : 'Upcoming work',
              Icons.upcoming_outlined,
              next.isEmpty
                  ? _emptyLine(_ru ? 'Всё завершено' : 'Everything is complete')
                  : Column(
                      children: [
                        for (final item in next.take(6))
                          _upcomingRow(item, data),
                      ],
                    ),
            );
            final risks = _panel(
              _ru ? 'Риски и блокировки' : 'Risks and blockers',
              Icons.warning_amber_rounded,
              blocked.isEmpty && overdue.isEmpty
                  ? _emptyLine(_ru
                      ? 'Критических отклонений нет'
                      : 'No critical deviations')
                  : Column(
                      children: [
                        for (final item in [...blocked, ...overdue].toSet())
                          _riskRow(item, data),
                      ],
                    ),
            );
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: schedule),
                      const SizedBox(width: 12),
                      Expanded(child: risks),
                    ],
                  )
                : Column(children: [schedule, const SizedBox(height: 12), risks]);
          },
        ),
        const SizedBox(height: 12),
        _panel(
          _ru ? 'Структура проекта' : 'Project structure',
          Icons.account_tree_outlined,
          items.isEmpty
              ? _emptyLine(_ru
                  ? 'Добавьте этапы и контрольные точки'
                  : 'Add phases and milestones')
              : Column(
                  children: [
                    for (final item in items) _structureRow(item, data),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _projectHero(
      RoadmapProject project, List<RoadmapItem> items, double progress) {
    final color = Color(project.colorValue);
    final milestones =
        items.where((value) => value.kind == RoadmapItemKind.milestone).length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(.18), AppTheme.surface.withOpacity(.58)],
        ),
        border: Border.all(color: color.withOpacity(.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  color: color.withOpacity(.16),
                ),
                child: Icon(Icons.rocket_launch_outlined, color: color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.title,
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.textPrimary)),
                    if (project.description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(project.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              height: 1.35,
                              color: AppTheme.textSecondary)),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _editProject(project),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_date(project.startDate)} — ${_date(project.endDate)}',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ),
              Text('${(progress * 100).round()}%',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: color)),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: AppTheme.background.withOpacity(.42),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _heroChip(Icons.layers_outlined,
                  _ru ? '${items.length} элементов' : '${items.length} items'),
              _heroChip(Icons.diamond_outlined,
                  _ru ? '$milestones вех' : '$milestones milestones'),
              if (project.owner.isNotEmpty)
                _heroChip(Icons.person_outline, project.owner),
              for (final tag in project.tags.take(3))
                _heroChip(Icons.tag, tag),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroChip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.background.withOpacity(.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppTheme.textMuted),
            const SizedBox(width: 5),
            Text(text,
                style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
          ],
        ),
      );

  Widget _upcomingRow(RoadmapItem item, _RoadmapData data) {
    final statusColor = _statusColor(item.status);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _editItem(item, data),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 3),
        child: Row(
          children: [
            _kindIcon(item, statusColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  Text(
                    '${_statusLabel(item.status, _ru)} · ${item.progress}%',
                    style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            Text(_date(item.endDate),
                style: TextStyle(
                    fontSize: 10,
                    color: item.isOverdue
                        ? AppTheme.accentRed
                        : AppTheme.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _riskRow(RoadmapItem item, _RoadmapData data) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _editItem(item, data),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: AppTheme.accentRed.withOpacity(.07),
            border: Border.all(color: AppTheme.accentRed.withOpacity(.18)),
          ),
          child: Row(
            children: [
              Icon(item.isBlocked ? Icons.block : Icons.schedule,
                  size: 17, color: AppTheme.accentRed),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary)),
                    Text(
                      item.isBlocked
                          ? (_ru ? 'Работа заблокирована' : 'Work is blocked')
                          : (_ru
                              ? 'Срок прошёл ${_date(item.endDate)}'
                              : 'Due date passed ${_date(item.endDate)}'),
                      style:
                          TextStyle(fontSize: 9.8, color: AppTheme.accentRed),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _structureRow(RoadmapItem item, _RoadmapData data) {
    final color = _statusColor(item.status);
    final dependencies = item.dependencyIds
        .map(data.itemById)
        .whereType<RoadmapItem>()
        .toList();
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: () => _editItem(item, data),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: AppTheme.background.withOpacity(.28),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Row(
          children: [
            _kindIcon(item, color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.8,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary)),
                      ),
                      Text('${item.progress}%',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: color)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: item.progress / 100,
                      minHeight: 4,
                      backgroundColor: AppTheme.surfaceLight,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 9,
                    runSpacing: 4,
                    children: [
                      _tiny(Icons.date_range,
                          '${_date(item.startDate)} — ${_date(item.endDate)}'),
                      if (dependencies.isNotEmpty)
                        _tiny(Icons.account_tree,
                            '${_ru ? 'После' : 'After'}: ${dependencies.map((e) => e.title).join(', ')}'),
                      if (item.linkedTaskIds.isNotEmpty)
                        _tiny(Icons.task_alt,
                            '${item.linkedTaskIds.length} ${_ru ? 'задач' : 'tasks'}'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeline(_RoadmapData data) {
    final project = data.projectById(_projectId);
    if (project == null) return _emptyProjects();
    final items = data.itemsForProject(project.id);
    if (items.isEmpty) {
      return _emptyWithAction(
        _ru
            ? 'Добавьте этапы — диаграмма Ганта построится автоматически'
            : 'Add phases and the Gantt chart appears automatically',
        () => _addItem(data),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _ru
                    ? 'Диаграмма Ганта · нажмите элемент для редактирования'
                    : 'Gantt chart · tap an item to edit',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ),
            _legend(AppTheme.accentGreen, _ru ? 'Готово' : 'Done'),
            const SizedBox(width: 10),
            _legend(AppTheme.accentRed, _ru ? 'Риск' : 'Risk'),
          ],
        ),
        const SizedBox(height: 10),
        _TimelineBoard(
          project: project,
          items: items,
          russian: _ru,
          onTap: (item) => _editItem(item, data),
        ),
      ],
    );
  }

  Widget _legend(Color color, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
        ],
      );

  Widget _list(_RoadmapData data) {
    final project = data.projectById(_projectId);
    if (project == null) return _emptyProjects();
    final items = data.itemsForProject(project.id);
    if (items.isEmpty) {
      return _emptyWithAction(
        _ru ? 'В проекте пока нет этапов' : 'This project has no phases yet',
        () => _addItem(data),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        for (final status in RoadmapItemStatus.values) ...[
          _groupHeader(
            _statusLabel(status, _ru),
            items.where((value) => value.status == status).length,
            _statusColor(status),
          ),
          const SizedBox(height: 8),
          if (!items.any((value) => value.status == status))
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: Text(_ru ? 'Нет элементов' : 'No items',
                  style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
            )
          else
            for (final item in items.where((value) => value.status == status))
              _listCard(item, data),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _groupHeader(String title, int count, Color color) => Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title.toUpperCase(),
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: AppTheme.textMuted)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: color.withOpacity(.12),
            ),
            child: Text('$count',
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: color)),
          ),
        ],
      );

  Widget _listCard(RoadmapItem item, _RoadmapData data) {
    final color = _statusColor(item.status);
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () => _editItem(item, data),
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(.46),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: item.isOverdue
                ? AppTheme.accentRed.withOpacity(.34)
                : AppTheme.glassBorder,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kindIcon(item, color),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary)),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10.5,
                            height: 1.35,
                            color: AppTheme.textMuted)),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: item.progress / 100,
                            minHeight: 5,
                            backgroundColor: AppTheme.surfaceLight,
                            valueColor: AlwaysStoppedAnimation(color),
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Text('${item.progress}%',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: color)),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 10,
                    runSpacing: 5,
                    children: [
                      _tiny(Icons.date_range,
                          '${_date(item.startDate)} — ${_date(item.endDate)}'),
                      if (item.assignee.isNotEmpty)
                        _tiny(Icons.person_outline, item.assignee),
                      if (item.linkedTaskIds.isNotEmpty)
                        _tiny(Icons.task_alt,
                            '${item.linkedTaskIds.length} ${_ru ? 'задач' : 'tasks'}'),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz, color: AppTheme.textMuted),
              onSelected: (value) async {
                if (value == 'delete') await RoadmapService.deleteItem(item.id);
                if (value == 'done') {
                  await RoadmapService.updateProgress(item.id, 100);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'done', child: Text(_ru ? 'Завершить' : 'Complete')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(_ru ? 'Удалить' : 'Delete',
                      style: TextStyle(color: AppTheme.accentRed)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(String title, IconData icon, Widget child) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(.46),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppTheme.accent),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  Widget _kindIcon(RoadmapItem item, Color color) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          color: color.withOpacity(.12),
          border: Border.all(color: color.withOpacity(.18)),
        ),
        child: Icon(
          item.kind == RoadmapItemKind.milestone
              ? Icons.diamond_outlined
              : Icons.view_timeline_outlined,
          size: 18,
          color: color,
        ),
      );

  Widget _tiny(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textMuted),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
        ],
      );

  Widget _emptyLine(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ),
      );

  Widget _emptyProjects() => _emptyWithAction(
        _ru
            ? 'Создайте первый проект: задайте цель, сроки, владельца и цвет. Затем добавьте этапы и вехи.'
            : 'Create the first project: set its goal, dates, owner, and color. Then add phases and milestones.',
        _addProject,
        icon: Icons.rocket_launch_outlined,
        button: _ru ? 'Создать проект' : 'Create project',
      );

  Widget _emptyWithAction(
    String text,
    VoidCallback action, {
    IconData icon = Icons.view_timeline_outlined,
    String? button,
  }) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 46, color: AppTheme.textMuted.withOpacity(.62)),
              const SizedBox(height: 14),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppTheme.textMuted)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: action,
                icon: const Icon(Icons.add),
                label: Text(button ?? (_ru ? 'Добавить этап' : 'Add phase')),
              ),
            ],
          ),
        ),
      );

  Future<void> _editProject(RoadmapProject project) async {
    final value = await _ProjectEditorSheet.show(context, existing: project);
    if (value != null) await RoadmapService.saveProject(value);
  }

  Future<void> _editItem(RoadmapItem item, _RoadmapData data) async {
    final project = data.projectById(item.projectId);
    if (project == null) return;
    final value = await _ItemEditorSheet.show(
      context,
      project: project,
      existingItems: data.itemsForProject(project.id),
      tasks: data.tasks,
      existing: item,
    );
    if (value != null) await RoadmapService.saveItem(value);
  }

  double _projectProgress(List<RoadmapItem> items) {
    if (items.isEmpty) return 0;
    final phases = items.where((value) => value.kind == RoadmapItemKind.phase).toList();
    final source = phases.isEmpty ? items : phases;
    return source.fold<double>(0, (sum, value) => sum + value.progress) /
        source.length /
        100;
  }

  String _date(DateTime value) =>
      DateFormat(_ru ? 'dd.MM.yyyy' : 'MMM d, yyyy').format(value.toLocal());
}

class _TimelineBoard extends StatelessWidget {
  final RoadmapProject project;
  final List<RoadmapItem> items;
  final bool russian;
  final ValueChanged<RoadmapItem> onTap;

  const _TimelineBoard({
    required this.project,
    required this.items,
    required this.russian,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    var start = project.startDate;
    var end = project.endDate;
    for (final item in items) {
      if (item.startDate.isBefore(start)) start = item.startDate;
      if (item.endDate.isAfter(end)) end = item.endDate;
    }
    start = DateTime(start.year, start.month, start.day);
    end = DateTime(end.year, end.month, end.day);
    final days = end.difference(start).inDays + 1;
    final dayWidth = days <= 45 ? 25.0 : days <= 120 ? 16.0 : 10.0;
    final labelWidth = 190.0;
    final timelineWidth = days * dayWidth;
    final totalWidth = labelWidth + timelineWidth;
    final todayIndex = DateTime.now().difference(start).inDays;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(.46),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalWidth,
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  children: [
                    Container(
                      width: labelWidth,
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: AppTheme.background.withOpacity(.3),
                        border: Border(
                          right: BorderSide(color: AppTheme.glassBorder),
                          bottom: BorderSide(color: AppTheme.glassBorder),
                        ),
                      ),
                      child: Text(
                        russian ? 'ЭТАП / ВЕХА' : 'PHASE / MILESTONE',
                        style: TextStyle(
                            fontSize: 9.5,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textMuted),
                      ),
                    ),
                    SizedBox(
                      width: timelineWidth,
                      child: Stack(
                        children: [
                          for (var i = 0; i < days; i++)
                            if (i == 0 ||
                                start.add(Duration(days: i)).day == 1 ||
                                start.add(Duration(days: i)).weekday == DateTime.monday)
                              Positioned(
                                left: i * dayWidth,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  width: 1,
                                  color: AppTheme.glassBorder,
                                ),
                              ),
                          for (var i = 0; i < days; i++)
                            if (i == 0 ||
                                start.add(Duration(days: i)).day == 1 ||
                                (days <= 60 &&
                                    start.add(Duration(days: i)).weekday ==
                                        DateTime.monday))
                              Positioned(
                                left: i * dayWidth + 5,
                                top: 8,
                                child: Text(
                                  DateFormat(days <= 60
                                          ? (russian ? 'dd MMM' : 'MMM d')
                                          : 'MMM yy')
                                      .format(start.add(Duration(days: i))),
                                  style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textMuted),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              for (final item in items)
                _row(
                  item,
                  start,
                  days,
                  dayWidth,
                  labelWidth,
                  timelineWidth,
                  todayIndex,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    RoadmapItem item,
    DateTime start,
    int days,
    double dayWidth,
    double labelWidth,
    double timelineWidth,
    int todayIndex,
  ) {
    final color = _statusColor(item.status);
    final left = item.startDate.difference(start).inDays.clamp(0, days - 1) * dayWidth;
    final rawLength = item.endDate.difference(item.startDate).inDays + 1;
    final width = item.kind == RoadmapItemKind.milestone
        ? 18.0
        : (rawLength * dayWidth).clamp(24.0, timelineWidth - left);
    return InkWell(
      onTap: () => onTap(item),
      child: SizedBox(
        height: 62,
        child: Row(
          children: [
            Container(
              width: labelWidth,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: AppTheme.glassBorder),
                  bottom: BorderSide(color: AppTheme.glassBorder),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    item.kind == RoadmapItemKind.milestone
                        ? Icons.diamond_outlined
                        : Icons.view_timeline_outlined,
                    size: 16,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary)),
                        const SizedBox(height: 2),
                        Text('${item.progress}% · ${_statusLabel(item.status, russian)}',
                            style: TextStyle(
                                fontSize: 9, color: AppTheme.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: timelineWidth,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < days; i++)
                    if (i == 0 ||
                        start.add(Duration(days: i)).day == 1 ||
                        start.add(Duration(days: i)).weekday == DateTime.monday)
                      Positioned(
                        left: i * dayWidth,
                        top: 0,
                        bottom: 0,
                        child: Container(width: 1, color: AppTheme.glassBorder),
                      ),
                  if (todayIndex >= 0 && todayIndex < days)
                    Positioned(
                      left: todayIndex * dayWidth,
                      top: 0,
                      bottom: 0,
                      child: Container(
                          width: 1.5, color: AppTheme.accent.withOpacity(.65)),
                    ),
                  if (item.kind == RoadmapItemKind.milestone)
                    Positioned(
                      left: left,
                      top: 22,
                      child: Transform.rotate(
                        angle: .785398,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: [
                              BoxShadow(
                                color: color.withOpacity(.28),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    Positioned(
                      left: left,
                      top: 17,
                      child: Container(
                        width: width,
                        height: 28,
                        decoration: BoxDecoration(
                          color: color.withOpacity(.18),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: color.withOpacity(.45)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            FractionallySizedBox(
                              widthFactor: item.progress / 100,
                              child: Container(color: color.withOpacity(.78)),
                            ),
                            Center(
                              child: Text('${item.progress}%',
                                  style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectEditorSheet extends StatefulWidget {
  final RoadmapProject? existing;
  const _ProjectEditorSheet({this.existing});

  static Future<RoadmapProject?> show(
    BuildContext context, {
    RoadmapProject? existing,
  }) =>
      showModalBottomSheet<RoadmapProject>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ProjectEditorSheet(existing: existing),
      );

  @override
  State<_ProjectEditorSheet> createState() => _ProjectEditorSheetState();
}

class _ProjectEditorSheetState extends State<_ProjectEditorSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _owner;
  late final TextEditingController _tags;
  late DateTime _start;
  late DateTime _end;
  late int _color;
  late bool _archived;

  bool get _ru => WesiLocale.isRussian;

  static const _colors = [
    0xFFF97316,
    0xFF3B82F6,
    0xFF8B5CF6,
    0xFF22C55E,
    0xFF06B6D4,
    0xFFEF4444,
    0xFFF59E0B,
  ];

  @override
  void initState() {
    super.initState();
    final value = widget.existing;
    final now = DateTime.now();
    _title = TextEditingController(text: value?.title ?? '');
    _description = TextEditingController(text: value?.description ?? '');
    _owner = TextEditingController(text: value?.owner ?? '');
    _tags = TextEditingController(text: value?.tags.join(', ') ?? '');
    _start = value?.startDate ?? DateTime(now.year, now.month, now.day);
    _end = value?.endDate ?? _start.add(const Duration(days: 90));
    _color = value?.colorValue ?? _colors.first;
    _archived = value?.archived ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _owner.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _roadSheet(
      context,
      title: widget.existing == null
          ? (_ru ? 'Новый проект' : 'New project')
          : (_ru ? 'Редактировать проект' : 'Edit project'),
      child: Form(
        key: _form,
        child: Column(
          children: [
            _roadField(_title, _ru ? 'Название проекта' : 'Project title',
                required: true),
            _roadField(_description, _ru ? 'Цель и описание' : 'Goal and description',
                lines: 4),
            _roadField(_owner, _ru ? 'Владелец проекта' : 'Project owner'),
            _roadField(_tags, _ru ? 'Теги через запятую' : 'Comma-separated tags'),
            Row(
              children: [
                Expanded(
                  child: _roadDate(
                    context,
                    _ru ? 'Начало' : 'Start',
                    _start,
                    (value) => setState(() {
                      _start = value;
                      if (_end.isBefore(_start)) _end = _start;
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _roadDate(
                    context,
                    _ru ? 'Завершение' : 'Finish',
                    _end,
                    (value) => setState(() => _end = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_ru ? 'Цвет проекта' : 'Project color',
                  style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in _colors)
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() => _color = color),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color(color),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == color
                              ? Colors.white
                              : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: _color == color
                            ? [BoxShadow(color: Color(color).withOpacity(.4), blurRadius: 10)]
                            : null,
                      ),
                      child: _color == color
                          ? const Icon(Icons.check, size: 18, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                value: _archived,
                contentPadding: EdgeInsets.zero,
                title: Text(_ru ? 'Проект в архиве' : 'Project archived'),
                subtitle: Text(
                  _ru
                      ? 'Архивные проекты скрыты по умолчанию'
                      : 'Archived projects are hidden by default',
                ),
                onChanged: (value) => setState(() => _archived = value),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.existing != null)
                  IconButton.filledTonal(
                    tooltip: _ru ? 'Удалить проект' : 'Delete project',
                    onPressed: () async {
                      await RoadmapService.deleteProject(widget.existing!.id);
                      if (mounted) Navigator.pop(context);
                    },
                    icon: Icon(Icons.delete_outline, color: AppTheme.accentRed),
                  ),
                if (widget.existing != null) const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_ru ? 'Сохранить проект' : 'Save project'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final now = DateTime.now();
    final existing = widget.existing;
    Navigator.pop(
      context,
      RoadmapProject(
        id: existing?.id ?? RoadmapService.newId('project'),
        title: _title.text.trim(),
        description: _description.text.trim(),
        owner: _owner.text.trim(),
        tags: _tags.text
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(),
        colorValue: _color,
        startDate: _start,
        endDate: _end.isBefore(_start) ? _start : _end,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        archived: _archived,
      ),
    );
  }
}

class _ItemEditorSheet extends StatefulWidget {
  final RoadmapProject project;
  final List<RoadmapItem> existingItems;
  final List<TaskModel> tasks;
  final RoadmapItem? existing;
  final RoadmapItemKind? initialKind;

  const _ItemEditorSheet({
    required this.project,
    required this.existingItems,
    required this.tasks,
    this.existing,
    this.initialKind,
  });

  static Future<RoadmapItem?> show(
    BuildContext context, {
    required RoadmapProject project,
    required List<RoadmapItem> existingItems,
    required List<TaskModel> tasks,
    RoadmapItem? existing,
    RoadmapItemKind? initialKind,
  }) =>
      showModalBottomSheet<RoadmapItem>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ItemEditorSheet(
          project: project,
          existingItems: existingItems,
          tasks: tasks,
          existing: existing,
          initialKind: initialKind,
        ),
      );

  @override
  State<_ItemEditorSheet> createState() => _ItemEditorSheetState();
}

class _ItemEditorSheetState extends State<_ItemEditorSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _assignee;
  late RoadmapItemKind _kind;
  late RoadmapItemStatus _status;
  late DateTime _start;
  late DateTime _end;
  late double _progress;
  late Set<String> _dependencies;
  late Set<String> _taskIds;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    final value = widget.existing;
    _title = TextEditingController(text: value?.title ?? '');
    _description = TextEditingController(text: value?.description ?? '');
    _assignee = TextEditingController(text: value?.assignee ?? '');
    _kind = value?.kind ?? widget.initialKind ?? RoadmapItemKind.phase;
    _status = value?.status ?? RoadmapItemStatus.planned;
    _start = value?.startDate ?? widget.project.startDate;
    _end = value?.endDate ?? _start.add(const Duration(days: 14));
    _progress = (value?.progress ?? 0).toDouble();
    _dependencies = value?.dependencyIds.toSet() ?? <String>{};
    _taskIds = value?.linkedTaskIds.toSet() ?? <String>{};
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _assignee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dependencyOptions = widget.existingItems
        .where((value) => value.id != widget.existing?.id)
        .toList();
    return _roadSheet(
      context,
      title: widget.existing == null
          ? (_ru ? 'Новый элемент roadmap' : 'New roadmap item')
          : (_ru ? 'Редактировать элемент' : 'Edit roadmap item'),
      child: Form(
        key: _form,
        child: Column(
          children: [
            SegmentedButton<RoadmapItemKind>(
              segments: [
                ButtonSegment(
                  value: RoadmapItemKind.phase,
                  icon: const Icon(Icons.view_timeline_outlined),
                  label: Text(_ru ? 'Этап' : 'Phase'),
                ),
                ButtonSegment(
                  value: RoadmapItemKind.milestone,
                  icon: const Icon(Icons.diamond_outlined),
                  label: Text(_ru ? 'Веха' : 'Milestone'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (value) => setState(() {
                _kind = value.first;
                if (_kind == RoadmapItemKind.milestone) _end = _start;
              }),
            ),
            const SizedBox(height: 12),
            _roadField(_title, _ru ? 'Название' : 'Title', required: true),
            _roadField(_description, _ru ? 'Описание результата' : 'Outcome description',
                lines: 3),
            _roadField(_assignee, _ru ? 'Ответственный' : 'Assignee'),
            Row(
              children: [
                Expanded(
                  child: _roadDate(
                    context,
                    _ru ? 'Начало' : 'Start',
                    _start,
                    (value) => setState(() {
                      _start = value;
                      if (_kind == RoadmapItemKind.milestone || _end.isBefore(value)) {
                        _end = value;
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _roadDate(
                    context,
                    _ru ? 'Завершение' : 'Finish',
                    _end,
                    (value) => setState(() => _end = value),
                    enabled: _kind == RoadmapItemKind.phase,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<RoadmapItemStatus>(
              value: _status,
              decoration: _roadDecoration(_ru ? 'Статус' : 'Status'),
              items: [
                for (final value in RoadmapItemStatus.values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(_statusLabel(value, _ru)),
                  ),
              ],
              onChanged: (value) => setState(() {
                _status = value!;
                if (_status == RoadmapItemStatus.done) _progress = 100;
              }),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(_ru ? 'Прогресс' : 'Progress',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                ),
                Text('${_progress.round()}%',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: _statusColor(_status))),
              ],
            ),
            Slider(
              value: _progress,
              min: 0,
              max: 100,
              divisions: 20,
              onChanged: (value) => setState(() {
                _progress = value;
                if (value >= 100) {
                  _status = RoadmapItemStatus.done;
                } else if (value > 0 && _status == RoadmapItemStatus.planned) {
                  _status = RoadmapItemStatus.inProgress;
                }
              }),
            ),
            if (dependencyOptions.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_ru ? 'Начать после' : 'Starts after',
                    style: TextStyle(
                        fontSize: 11.5, color: AppTheme.textSecondary)),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final item in dependencyOptions)
                    FilterChip(
                      selected: _dependencies.contains(item.id),
                      label: Text(item.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10)),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _dependencies.add(item.id);
                        } else {
                          _dependencies.remove(item.id);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (widget.tasks.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_ru ? 'Связанные задачи' : 'Linked tasks',
                    style: TextStyle(
                        fontSize: 11.5, color: AppTheme.textSecondary)),
              ),
              const SizedBox(height: 7),
              Container(
                constraints: const BoxConstraints(maxHeight: 190),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: AppTheme.glassBorder),
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final task in widget.tasks)
                      CheckboxListTile(
                        dense: true,
                        value: _taskIds.contains(task.id),
                        title: Text(task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11)),
                        subtitle: Text(_taskStatus(task.status, _ru),
                            style: TextStyle(
                                fontSize: 9.5, color: AppTheme.textMuted)),
                        onChanged: (selected) => setState(() {
                          if (selected == true) {
                            _taskIds.add(task.id);
                          } else {
                            _taskIds.remove(task.id);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                if (widget.existing != null)
                  IconButton.filledTonal(
                    tooltip: _ru ? 'Удалить' : 'Delete',
                    onPressed: () async {
                      await RoadmapService.deleteItem(widget.existing!.id);
                      if (mounted) Navigator.pop(context);
                    },
                    icon: Icon(Icons.delete_outline, color: AppTheme.accentRed),
                  ),
                if (widget.existing != null) const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_ru ? 'Сохранить' : 'Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final now = DateTime.now();
    final existing = widget.existing;
    final end = _kind == RoadmapItemKind.milestone || _end.isBefore(_start)
        ? _start
        : _end;
    Navigator.pop(
      context,
      RoadmapItem(
        id: existing?.id ?? RoadmapService.newId('road'),
        projectId: widget.project.id,
        title: _title.text.trim(),
        description: _description.text.trim(),
        kind: _kind,
        status: _status,
        assignee: _assignee.text.trim(),
        startDate: _start,
        endDate: end,
        progress: _progress.round(),
        order: existing?.order ?? widget.existingItems.length,
        dependencyIds: _dependencies.toList(),
        linkedTaskIds: _taskIds.toList(),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }
}

class _RoadmapData {
  final List<RoadmapProject> projects;
  final List<RoadmapItem> items;
  final RoadmapSummary summary;
  final List<TaskModel> tasks;

  const _RoadmapData({
    required this.projects,
    required this.items,
    required this.summary,
    required this.tasks,
  });

  RoadmapProject? projectById(String? id) {
    if (id == null) return null;
    for (final value in projects) {
      if (value.id == id) return value;
    }
    return null;
  }

  RoadmapItem? itemById(String id) {
    for (final value in items) {
      if (value.id == id) return value;
    }
    return null;
  }

  List<RoadmapItem> itemsForProject(String projectId) =>
      items.where((value) => value.projectId == projectId).toList()
        ..sort((a, b) {
          final byOrder = a.order.compareTo(b.order);
          return byOrder != 0 ? byOrder : a.startDate.compareTo(b.startDate);
        });
}

class _RoadMetric {
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final bool warning;

  const _RoadMetric(
    this.icon,
    this.label,
    this.value,
    this.detail, {
    this.warning = false,
  });
}

Widget _roadSheet(
  BuildContext context, {
  required String title,
  required Widget child,
}) =>
    Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .92),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            18,
            12,
            18,
            18 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textMuted.withOpacity(.4),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: WesiTitle(title, size: 18)),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );

Widget _roadField(
  TextEditingController controller,
  String label, {
  bool required = false,
  int lines = 1,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        maxLines: lines,
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                ? '$label — обязательное поле'
                : null
            : null,
        decoration: _roadDecoration(label),
      ),
    );

InputDecoration _roadDecoration(String label) => InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppTheme.surface.withOpacity(.52),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: AppTheme.glassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: AppTheme.glassBorder),
      ),
    );

Widget _roadDate(
  BuildContext context,
  String label,
  DateTime value,
  ValueChanged<DateTime> onChanged, {
  bool enabled = true,
}) {
  final ru = WesiLocale.isRussian;
  return InkWell(
    borderRadius: BorderRadius.circular(13),
    onTap: !enabled
        ? null
        : () async {
            final chosen = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (chosen != null) onChanged(chosen);
          },
    child: InputDecorator(
      decoration: _roadDecoration(label).copyWith(
        enabled: enabled,
        suffixIcon: const Icon(Icons.calendar_month_outlined),
      ),
      child: Text(
        DateFormat(ru ? 'dd.MM.yyyy' : 'MMM d, yyyy').format(value),
        style: TextStyle(
            color: enabled ? AppTheme.textPrimary : AppTheme.textMuted),
      ),
    ),
  );
}

String _statusLabel(RoadmapItemStatus status, bool ru) => switch (status) {
      RoadmapItemStatus.planned => ru ? 'Запланировано' : 'Planned',
      RoadmapItemStatus.inProgress => ru ? 'В работе' : 'In progress',
      RoadmapItemStatus.blocked => ru ? 'Заблокировано' : 'Blocked',
      RoadmapItemStatus.done => ru ? 'Завершено' : 'Done',
    };

Color _statusColor(RoadmapItemStatus status) => switch (status) {
      RoadmapItemStatus.planned => const Color(0xFF60A5FA),
      RoadmapItemStatus.inProgress => AppTheme.accent,
      RoadmapItemStatus.blocked => AppTheme.accentRed,
      RoadmapItemStatus.done => AppTheme.accentGreen,
    };

String _taskStatus(TaskStatus status, bool ru) => switch (status) {
      TaskStatus.backlog => ru ? 'Бэклог' : 'Backlog',
      TaskStatus.inProgress => ru ? 'В работе' : 'In progress',
      TaskStatus.review => ru ? 'Проверка' : 'Review',
      TaskStatus.done => ru ? 'Готово' : 'Done',
    };
