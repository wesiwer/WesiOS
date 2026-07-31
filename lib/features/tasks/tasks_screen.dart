import 'package:flutter/material.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/widgets/window_controls.dart';
import 'models/task_model.dart';
import 'services/task_service.dart';
import 'task_labels.dart';
import 'widgets/task_editor_dialog.dart';

/// Задачи — канбан-доска с приоритетами, сроками, исполнителями и
/// чек-листами.
///
/// Карточки переносятся между колонками перетаскиванием (на десктопе) и
/// через меню на карточке (на телефоне, где четыре колонки в ряд не
/// помещаются и драг между ними неудобен).
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final TaskService _service = TaskService();
  List<TaskModel> _tasks = [];
  bool _loading = true;

  /// Фильтры. null — показывать всё.
  TaskPriority? _priorityFilter;
  bool _onlyOverdue = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
    TaskService.revision.addListener(_load);
  }

  @override
  void dispose() {
    TaskService.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final all = await _service.getAll();
    if (!mounted) return;
    setState(() {
      _tasks = all;
      _loading = false;
    });
  }

  List<TaskModel> _column(TaskStatus s) {
    return _tasks.where((t) {
      if (t.status != s) return false;
      if (_priorityFilter != null && t.priority != _priorityFilter) {
        return false;
      }
      if (_onlyOverdue && !t.isOverdue) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        final inTitle = t.title.toLowerCase().contains(q);
        final inDesc = (t.description ?? '').toLowerCase().contains(q);
        final inAssignee = (t.assignee ?? '').toLowerCase().contains(q);
        if (!inTitle && !inDesc && !inAssignee) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _create([TaskStatus status = TaskStatus.backlog]) async {
    final task =
        await TaskEditorDialog.show(context, initialStatus: status);
    if (task != null) await _service.save(task);
  }

  Future<void> _edit(TaskModel task) async {
    final updated = await TaskEditorDialog.show(context, initial: task);
    if (updated != null) await _service.save(updated);
  }

  Future<void> _confirmDelete(TaskModel task) async {
    final ru = WesiLocale.isRussian;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding:
            const EdgeInsets.fromLTRB(40, kTitleBarHeight + 24, 40, 24),
        title: Text(ru ? 'Удалить задачу?' : 'Delete task?',
            style: TextStyle(fontSize: 17, color: AppTheme.textPrimary)),
        content: Text('«${task.title}»',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(WesiLocale.get('cancel'),
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ru ? 'Удалить' : 'Delete',
                style: TextStyle(color: AppTheme.accentRed)),
          ),
        ],
      ),
    );
    if (ok == true) await _service.delete(task.id);
  }

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: CircularProgressIndicator(
              color: AppTheme.accentOrange.withOpacity(0.5)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: AppTheme.accentOrange,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(ru ? 'Задача' : 'Task',
            style: const TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, kTitleBarInset + 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(ru),
              const SizedBox(height: 12),
              _filters(ru),
              const SizedBox(height: 14),
              Expanded(child: _board(ru)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(bool ru) {
    final overdue = _tasks.where((t) => t.isOverdue).length;
    final today = _tasks.where((t) => t.isDueToday).length;
    final done = _tasks.where((t) => t.status == TaskStatus.done).length;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WesiTitle(ru ? 'Задачи' : 'Tasks'),
              const SizedBox(height: 2),
              Text(
                _tasks.isEmpty
                    ? (ru
                        ? 'Пока пусто — создайте первую задачу'
                        : 'Nothing yet — create the first task')
                    : '${_tasks.length} ${ru ? 'всего' : 'total'} · '
                        '$done ${ru ? 'готово' : 'done'}'
                        '${overdue > 0 ? ' · $overdue ${ru ? 'просрочено' : 'overdue'}' : ''}'
                        '${today > 0 ? ' · $today ${ru ? 'на сегодня' : 'due today'}' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: overdue > 0
                      ? AppTheme.accentRed
                      : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filters(bool ru) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 38,
            child: TextField(
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textPrimary),
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search,
                    size: 17, color: AppTheme.textMuted),
                hintText: ru ? 'Поиск по задачам' : 'Search tasks',
                hintStyle:
                    TextStyle(fontSize: 13, color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.surface.withOpacity(0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _chip(
          label: ru ? 'Просроченные' : 'Overdue',
          selected: _onlyOverdue,
          color: AppTheme.accentRed,
          onTap: () => setState(() => _onlyOverdue = !_onlyOverdue),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<TaskPriority?>(
          color: AppTheme.surface,
          tooltip: ru ? 'Приоритет' : 'Priority',
          onSelected: (v) => setState(() => _priorityFilter = v),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: null,
              child: Text(ru ? 'Любой приоритет' : 'Any priority',
                  style: TextStyle(color: AppTheme.textPrimary)),
            ),
            ...TaskPriority.values.map((p) => PopupMenuItem(
                  value: p,
                  child: Text(TaskLabels.priority(p, ru),
                      style: TextStyle(
                          color: TaskLabels.priorityColor(p))),
                )),
          ],
          child: _chip(
            label: _priorityFilter == null
                ? (ru ? 'Приоритет' : 'Priority')
                : TaskLabels.priority(_priorityFilter!, ru),
            selected: _priorityFilter != null,
            color: _priorityFilter == null
                ? AppTheme.accentOrange
                : TaskLabels.priorityColor(_priorityFilter!),
            onTap: null,
          ),
        ),
      ],
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required Color color,
    VoidCallback? onTap,
  }) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? color.withOpacity(0.16) : AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: selected ? color.withOpacity(0.5) : AppTheme.glassBorder),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? color : AppTheme.textSecondary)),
    );
    return onTap == null
        ? content
        : GestureDetector(onTap: onTap, child: content);
  }

  Widget _board(bool ru) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Четыре колонки в ряд требуют ширины: на телефоне вместо доски
        // показываем колонки одну под другой, иначе карточки нечитаемы.
        final narrow = constraints.maxWidth < 720;
        if (narrow) {
          return ListView(
            children: [
              for (final s in TaskStatus.values) ...[
                _columnWidget(s, ru, narrow: true),
                const SizedBox(height: 14),
              ],
              const SizedBox(height: 70),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < TaskStatus.values.length; i++) ...[
              Expanded(child: _columnWidget(TaskStatus.values[i], ru)),
              if (i != TaskStatus.values.length - 1)
                const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }

  Widget _columnWidget(TaskStatus status, bool ru, {bool narrow = false}) {
    final items = _column(status);

    // DragTarget принимает карточку из другой колонки — перенос
    // перетаскиванием на десктопе.
    return DragTarget<TaskModel>(
      onWillAcceptWithDetails: (d) => d.data.status != status,
      onAcceptWithDetails: (d) => _service.move(d.data, status),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: hovering
                ? AppTheme.accentOrange.withOpacity(0.08)
                : AppTheme.surface.withOpacity(0.3),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hovering
                  ? AppTheme.accentOrange.withOpacity(0.5)
                  : AppTheme.glassBorder,
            ),
          ),
          child: Column(
            // На телефоне колонка обжимается по содержимому — скроллит общий
            // ListView снаружи. На доске колонка занимает всю высоту и
            // скроллится внутри себя, иначе четыре колонки разной высоты
            // выглядят рвано.
            mainAxisSize: narrow ? MainAxisSize.min : MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(TaskLabels.statusIcon(status),
                      size: 15, color: AppTheme.textMuted),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      TaskLabels.status(status, ru),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary),
                    ),
                  ),
                  Text('${items.length}',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textMuted)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _create(status),
                    child: const Icon(Icons.add,
                        size: 16, color: AppTheme.accentOrange),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: Text(
                      ru ? 'Пусто' : 'Empty',
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ),
                )
              else if (narrow)
                ...items.map((t) => _card(t, ru))
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) => _card(items[i], ru),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _card(TaskModel task, bool ru) {
    final card = _cardBody(task, ru);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Draggable<TaskModel>(
        data: task,
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(
            opacity: 0.9,
            child: SizedBox(width: 240, child: _cardBody(task, ru)),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: card),
        child: card,
      ),
    );
  }

  Widget _cardBody(TaskModel task, bool ru) {
    final pColor = TaskLabels.priorityColor(task.priority);
    return GestureDetector(
      onTap: () => _edit(task),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: task.isOverdue
                ? AppTheme.accentRed.withOpacity(0.45)
                : AppTheme.glassBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 5),
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: pColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: task.status == TaskStatus.done
                          ? AppTheme.textMuted
                          : AppTheme.textPrimary,
                      decoration: task.status == TaskStatus.done
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                _cardMenu(task, ru),
              ],
            ),
            if (task.subtasks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: task.checklistProgress,
                        minHeight: 3,
                        backgroundColor: AppTheme.background,
                        valueColor: const AlwaysStoppedAnimation(
                            AppTheme.accentOrange),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${task.subtasks.where((s) => s.done).length}/${task.subtasks.length}',
                    style: TextStyle(
                        fontSize: 10, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ],
            if (task.dueDate != null || task.assignee != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (task.dueDate != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule,
                            size: 11,
                            color: task.isOverdue
                                ? AppTheme.accentRed
                                : AppTheme.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          TaskLabels.dueLabel(task.dueDate!, ru),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: task.isOverdue
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: task.isOverdue
                                ? AppTheme.accentRed
                                : AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  if (task.assignee != null && task.assignee!.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_outline,
                            size: 11, color: AppTheme.textMuted),
                        const SizedBox(width: 4),
                        Text(task.assignee!,
                            style: TextStyle(
                                fontSize: 10, color: AppTheme.textMuted)),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Меню на карточке — способ перенести задачу там, где перетаскивание
  /// неудобно (телефон), плюс удаление.
  Widget _cardMenu(TaskModel task, bool ru) {
    return PopupMenuButton<String>(
      color: AppTheme.surface,
      padding: EdgeInsets.zero,
      iconSize: 15,
      icon: const Icon(Icons.more_vert, color: AppTheme.textMuted),
      onSelected: (value) {
        if (value == 'edit') {
          _edit(task);
        } else if (value == 'delete') {
          _confirmDelete(task);
        } else {
          final target = TaskStatus.values
              .firstWhere((s) => s.name == value, orElse: () => task.status);
          _service.move(task, target);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'edit',
          child: Text(ru ? 'Изменить' : 'Edit',
              style: TextStyle(color: AppTheme.textPrimary)),
        ),
        const PopupMenuDivider(),
        ...TaskStatus.values.where((s) => s != task.status).map(
              (s) => PopupMenuItem(
                value: s.name,
                child: Text(
                  '${ru ? 'В' : 'To'} «${TaskLabels.status(s, ru)}»',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Text(ru ? 'Удалить' : 'Delete',
              style: TextStyle(color: AppTheme.accentRed)),
        ),
      ],
    );
  }
}
