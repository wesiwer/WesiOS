import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/localization/wesi_locale.dart';
import '../../../core/widgets/hover_button.dart';
import '../../../core/widgets/window_controls.dart';
import '../models/task_model.dart';
import '../task_labels.dart';

/// Создание и редактирование задачи: название, описание, приоритет, срок,
/// исполнитель, чек-лист.
class TaskEditorDialog extends StatefulWidget {
  final TaskModel? initial;
  final TaskStatus initialStatus;

  const TaskEditorDialog({
    super.key,
    this.initial,
    this.initialStatus = TaskStatus.backlog,
  });

  static Future<TaskModel?> show(
    BuildContext context, {
    TaskModel? initial,
    TaskStatus initialStatus = TaskStatus.backlog,
  }) {
    return showDialog<TaskModel>(
      context: context,
      builder: (_) =>
          TaskEditorDialog(initial: initial, initialStatus: initialStatus),
    );
  }

  @override
  State<TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends State<TaskEditorDialog> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _assigneeCtrl = TextEditingController();
  final _subtaskCtrl = TextEditingController();

  late TaskStatus _status;
  late TaskPriority _priority;
  DateTime? _dueDate;
  late List<SubTask> _subtasks;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _status = t?.status ?? widget.initialStatus;
    _priority = t?.priority ?? TaskPriority.normal;
    _dueDate = t?.dueDate;
    _subtasks = List<SubTask>.from(t?.subtasks ?? const []);
    if (t != null) {
      _titleCtrl.text = t.title;
      _descCtrl.text = t.description ?? '';
      _assigneeCtrl.text = t.assignee ?? '';
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _assigneeCtrl.dispose();
    _subtaskCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      locale: WesiLocale.isRussian ? const Locale('ru') : const Locale('en'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.accentOrange,
            onPrimary: AppTheme.background,
            surface: AppTheme.surface,
            onSurface: AppTheme.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  void _addSubtask() {
    final text = _subtaskCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _subtasks.add(SubTask(title: text));
      _subtaskCtrl.clear();
    });
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final base = widget.initial;
    final task = base == null
        ? TaskModel(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            title: title,
            description: _descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim(),
            status: _status,
            priority: _priority,
            createdAt: DateTime.now(),
            dueDate: _dueDate,
            assignee: _assigneeCtrl.text.trim().isEmpty
                ? null
                : _assigneeCtrl.text.trim(),
            subtasks: _subtasks,
          )
        : base.copyWith(
            title: title,
            description: _descCtrl.text.trim(),
            status: _status,
            priority: _priority,
            dueDate: _dueDate,
            clearDueDate: _dueDate == null,
            assignee: _assigneeCtrl.text.trim(),
            subtasks: _subtasks,
          );
    Navigator.pop(context, task);
  }

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.fromLTRB(40, kTitleBarHeight + 24, 40, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.initial == null
                    ? (ru ? 'Новая задача' : 'New task')
                    : (ru ? 'Редактировать задачу' : 'Edit task'),
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _titleCtrl,
                autofocus: true,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                    labelText: ru ? 'Название' : 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                maxLines: 3,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                    labelText: ru ? 'Описание' : 'Description'),
              ),
              const SizedBox(height: 16),
              Text(ru ? 'Приоритет' : 'Priority',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: TaskPriority.values.map((p) {
                  final sel = p == _priority;
                  final color = TaskLabels.priorityColor(p);
                  return GestureDetector(
                    onTap: () => setState(() => _priority = p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel
                            ? color.withOpacity(0.18)
                            : AppTheme.background,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                            color: sel
                                ? color.withOpacity(0.6)
                                : AppTheme.glassBorder),
                      ),
                      child: Text(
                        TaskLabels.priority(p, ru),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                          color: sel ? color : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text(ru ? 'Колонка' : 'Column',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TaskStatus.values.map((s) {
                  final sel = s == _status;
                  return GestureDetector(
                    onTap: () => setState(() => _status = s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel
                            ? AppTheme.accentOrange.withOpacity(0.18)
                            : AppTheme.background,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                            color: sel
                                ? AppTheme.accentOrange.withOpacity(0.6)
                                : AppTheme.glassBorder),
                      ),
                      child: Text(
                        TaskLabels.status(s, ru),
                        style: TextStyle(
                          fontSize: 12,
                          color: sel
                              ? AppTheme.accentOrange
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickDue,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.glassBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event,
                                size: 17, color: AppTheme.textMuted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _dueDate == null
                                    ? (ru ? 'Срок не задан' : 'No due date')
                                    : TaskLabels.date(_dueDate!),
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textPrimary),
                              ),
                            ),
                            if (_dueDate != null)
                              GestureDetector(
                                onTap: () => setState(() => _dueDate = null),
                                child: const Icon(Icons.close,
                                    size: 16, color: AppTheme.textMuted),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _assigneeCtrl,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                          labelText: ru ? 'Исполнитель' : 'Assignee'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(ru ? 'Чек-лист' : 'Checklist',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 6),
              ...List.generate(_subtasks.length, (i) {
                final st = _subtasks[i];
                return Row(
                  children: [
                    Checkbox(
                      value: st.done,
                      activeColor: AppTheme.accentOrange,
                      onChanged: (v) => setState(
                          () => _subtasks[i] = st.copyWith(done: v ?? false)),
                    ),
                    Expanded(
                      child: Text(
                        st.title,
                        style: TextStyle(
                          fontSize: 13,
                          color: st.done
                              ? AppTheme.textMuted
                              : AppTheme.textPrimary,
                          decoration:
                              st.done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 15, color: AppTheme.textMuted),
                      onPressed: () => setState(() => _subtasks.removeAt(i)),
                    ),
                  ],
                );
              }),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _subtaskCtrl,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      onSubmitted: (_) => _addSubtask(),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: ru ? 'Добавить пункт' : 'Add an item',
                        hintStyle: const TextStyle(color: AppTheme.textMuted),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle,
                        color: AppTheme.accentOrange),
                    onPressed: _addSubtask,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(WesiLocale.get('cancel'),
                        style: const TextStyle(color: AppTheme.textMuted)),
                  ),
                  const Spacer(),
                  HoverButton(
                    onTap: _submit,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 26, vertical: 12),
                    backgroundColor: AppTheme.accentOrange,
                    child: Text(WesiLocale.get('save'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
