import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../team/models/employee_model.dart';
import '../../../team/services/team_service.dart';
import '../../models/task_model.dart';
import '../models/ai_task_suggestion.dart';
import '../models/ai_task_template.dart';

class AiSuggestionEditDialog extends StatefulWidget {
  final AiTaskSuggestion suggestion;

  const AiSuggestionEditDialog({super.key, required this.suggestion});

  static Future<AiTaskSuggestion?> show(
    BuildContext context,
    AiTaskSuggestion suggestion,
  ) =>
      showDialog<AiTaskSuggestion>(
        context: context,
        builder: (_) => AiSuggestionEditDialog(suggestion: suggestion),
      );

  @override
  State<AiSuggestionEditDialog> createState() => _AiSuggestionEditDialogState();
}

class _AiSuggestionEditDialogState extends State<AiSuggestionEditDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late TaskPriority _priority;
  late AiForecastImpact _impact;
  late String? _assigneeId;
  late DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.suggestion.title);
    _description = TextEditingController(text: widget.suggestion.description);
    _priority = widget.suggestion.priority;
    _impact = widget.suggestion.forecastImpact;
    _assigneeId = widget.suggestion.assigneeId;
    _dueDate = widget.suggestion.dueDate;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now.add(const Duration(days: 2)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _dueDate = picked);
  }

  void _save() {
    if (_title.text.trim().isEmpty) return;
    Navigator.pop(
      context,
      widget.suggestion.copyWith(
        title: _title.text.trim(),
        description: _description.text.trim(),
        assigneeId: _assigneeId,
        clearAssignee: _assigneeId == null,
        priority: _priority,
        forecastImpact: _impact,
        dueDate: _dueDate,
        clearDueDate: _dueDate == null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assignees = widget.suggestion.alternativeAssigneeIds
        .map(TeamService.byId)
        .whereType<EmployeeModel>()
        .toList();
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Изменить предложение Wesi AI'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Задача'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Описание'),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<TaskPriority>(
                      value: _priority,
                      decoration: const InputDecoration(labelText: 'Важность'),
                      items: TaskPriority.values
                          .map((priority) => DropdownMenuItem(
                                value: priority,
                                child: Text(_priorityLabel(priority)),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _priority = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<AiForecastImpact>(
                      value: _impact,
                      decoration: const InputDecoration(
                          labelText: 'Значимость'),
                      items: AiForecastImpact.values
                          .map((impact) => DropdownMenuItem(
                                value: impact,
                                child: Text(impact.ru),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _impact = value);
                      },
                    ),
                  ),
                ],
              ),
              if (assignees.isNotEmpty) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  value: _assigneeId,
                  decoration: const InputDecoration(labelText: 'Исполнитель'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Без исполнителя'),
                    ),
                    ...assignees.map((employee) => DropdownMenuItem<String?>(
                          value: employee.id,
                          child: Text(
                            '${employee.displayName} · ${employee.position}',
                          ),
                        )),
                  ],
                  onChanged: (value) => setState(() => _assigneeId = value),
                ),
              ],
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(_dueDate == null
                    ? 'Без срока'
                    : 'Срок: ${_date(_dueDate!)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_dueDate != null)
                      IconButton(
                        tooltip: 'Убрать срок',
                        onPressed: () => setState(() => _dueDate = null),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    TextButton(
                        onPressed: _pickDate, child: const Text('Изменить')),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Wesi AI сохранит ваши правки и создаст обычную задачу. '
                'После создания она полностью управляется как остальные задачи.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Применить'),
        ),
      ],
    );
  }

  static String _priorityLabel(TaskPriority priority) => switch (priority) {
        TaskPriority.low => 'Низкая',
        TaskPriority.normal => 'Обычная',
        TaskPriority.high => 'Высокая',
        TaskPriority.urgent => 'Срочная',
      };

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
}
