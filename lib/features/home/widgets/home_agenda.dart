import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/localization/wesi_locale.dart';
import '../../../widgets/glass_card.dart';
import '../../tasks/models/task_model.dart';
import '../../tasks/services/task_service.dart';
import '../../tasks/task_labels.dart';
import '../../tasks/widgets/task_editor_dialog.dart';

/// Карточки «Календарь» и «Задачи» на главной.
///
/// Раньше здесь стояли статичные заглушки («Событий нет», «Нет активных
/// задач») — они не зависели от данных вообще. Теперь обе карточки читают
/// реальные задачи: календарь показывает то, что назначено на сегодня, а
/// список задач — ближайшие сроки. Это и есть связь календаря с задачами:
/// срок задачи и есть событие дня, отдельной сущности «событие» пока нет.
class HomeAgenda extends StatefulWidget {
  const HomeAgenda({super.key});

  @override
  State<HomeAgenda> createState() => _HomeAgendaState();
}

class _HomeAgendaState extends State<HomeAgenda> {
  final TaskService _service = TaskService();

  List<TaskModel> _today = [];
  List<TaskModel> _upcoming = [];
  int _overdue = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Вкладки живут в IndexedStack и не пересоздаются: без подписки карточка
    // осталась бы такой, какой была при первом открытии приложения.
    TaskService.revision.addListener(_load);
  }

  @override
  void dispose() {
    TaskService.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final today = await _service.dueOn(now);
    var upcoming = await _service.upcoming(limit: 3);
    if (upcoming.isEmpty) {
      upcoming = await _service.activeWithoutDue(limit: 3);
    }
    final all = await _service.getAll();
    if (!mounted) return;
    setState(() {
      _today = today;
      _upcoming = upcoming;
      _overdue = all.where((t) => t.isOverdue).length;
      _loaded = true;
    });
  }

  Future<void> _createTask() async {
    final task = await TaskEditorDialog.show(context);
    if (task != null) await _service.save(task);
  }

  @override
  Widget build(BuildContext context) {
    // Обязательно слушаем тему: иначе после переключения light/dark
    // заголовки «Календарь»/«Задачи» остаются с цветом предыдущей темы
    // (белый на белом в light).
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, _, __) {
        final ru = WesiLocale.isRussian;
        return Column(
          children: [
            _calendarCard(ru),
            const SizedBox(height: 16),
            _tasksCard(ru),
          ],
        );
      },
    );
  }

  Widget _calendarCard(bool ru) {
    final now = DateTime.now();
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(
            title: WesiLocale.get('calendar'),
            trailing: '${now.day.toString().padLeft(2, '0')}.'
                '${now.month.toString().padLeft(2, '0')}',
            onAll: () => Navigator.pushNamed(context, '/calendar'),
          ),
          const SizedBox(height: 10),
          if (!_loaded)
            _placeholder(ru ? 'Загрузка…' : 'Loading…')
          else if (_today.isEmpty)
            _placeholder(ru
                ? 'На сегодня ничего не запланировано'
                : 'Nothing scheduled for today')
          else
            ..._today.map((t) => _row(
                  icon: TaskLabels.statusIcon(t.status),
                  color: TaskLabels.priorityColor(t.priority),
                  title: t.title,
                  subtitle: TaskLabels.status(t.status, ru),
                  done: t.status == TaskStatus.done,
                )),
        ],
      ),
    );
  }

  Widget _tasksCard(bool ru) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(
            title: WesiLocale.get('tasks'),
            trailing: _overdue > 0
                ? '$_overdue ${ru ? 'просрочено' : 'overdue'}'
                : null,
            trailingIsAlert: _overdue > 0,
            onAll: () => Navigator.pushNamed(context, '/tasks'),
          ),
          const SizedBox(height: 10),
          if (!_loaded)
            _placeholder(ru ? 'Загрузка…' : 'Loading…')
          else if (_upcoming.isEmpty) ...[
            _placeholder(ru
                ? 'Активных задач нет'
                : 'No active tasks'),
            SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _createTask,
                icon: Icon(Icons.add,
                    size: 16, color: AppTheme.accent),
                label: Text(
                  ru ? 'Создать первую задачу' : 'Create the first task',
                  style: TextStyle(color: AppTheme.accent),
                ),
              ),
            ),
          ] else
            ..._upcoming.map((t) => _row(
                  icon: TaskLabels.statusIcon(t.status),
                  color: t.isOverdue
                      ? AppTheme.accentRed
                      : TaskLabels.priorityColor(t.priority),
                  title: t.title,
                  subtitle: t.dueDate == null
                      ? TaskLabels.status(t.status, ru)
                      : '${TaskLabels.status(t.status, ru)} · '
                          '${TaskLabels.dueLabel(t.dueDate!, ru)}',
                  alert: t.isOverdue,
                )),
        ],
      ),
    );
  }

  Widget _header({
    required String title,
    String? trailing,
    bool trailingIsAlert = false,
    required VoidCallback onAll,
  }) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            // Серый на светлой теме, читаемый secondary на тёмной —
            // не textPrimary (белый), иначе «белый на белом».
            color: AppTheme.textSecondary,
          ),
        ),
        if (trailing != null) ...[
          SizedBox(width: 10),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (trailingIsAlert ? AppTheme.accentRed : AppTheme.accent)
                  .withOpacity(0.15),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              trailing,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color:
                    trailingIsAlert ? AppTheme.accentRed : AppTheme.accent,
              ),
            ),
          ),
        ],
        Spacer(),
        TextButton(
          onPressed: onAll,
          child: Text(WesiLocale.get('all'),
              style: TextStyle(color: AppTheme.accent)),
        ),
      ],
    );
  }

  Widget _placeholder(String text) => Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text(text,
            style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
      );

  Widget _row({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    bool done = false,
    bool alert = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: done ? AppTheme.textMuted : AppTheme.textPrimary,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: alert ? AppTheme.accentRed : AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
