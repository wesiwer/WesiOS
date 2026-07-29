import 'package:flutter/material.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/widgets/module_scaffold.dart';

/// Задачи — рабочий трекер: доска, приоритеты, сроки, исполнители.
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    return ModuleScaffold(
      title: ru ? 'Задачи' : 'Tasks',
      subtitle: ru
          ? 'Что нужно сделать, кем и к какому сроку'
          : 'What needs doing, by whom, and by when',
      icon: Icons.task_alt,
      stage: ModuleStage.planned,
      plannedFeatures: [
        ru
            ? 'Канбан-доска: Бэклог → В работе → На проверке → Готово'
            : 'Kanban board: Backlog → In progress → Review → Done',
        ru
            ? 'Приоритеты, сроки и напоминания о дедлайнах'
            : 'Priorities, due dates, and deadline reminders',
        ru
            ? 'Подзадачи и чек-листы внутри задачи'
            : 'Subtasks and checklists inside a task',
        ru
            ? 'Исполнители и комментарии в обсуждении задачи'
            : 'Assignees and a comment thread per task',
        ru
            ? 'Связь с календарём: срок задачи виден на дате'
            : 'Calendar link: a task due date shows up on the day',
        ru
            ? 'Голосовое добавление задачи (Wesi Voice)'
            : 'Add a task by voice (Wesi Voice)',
      ],
      child: Row(
        children: [
          Expanded(
            child: StubBlock(
              icon: Icons.inbox,
              height: 160,
              label: ru ? 'Бэклог' : 'Backlog',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StubBlock(
              icon: Icons.play_circle_outline,
              height: 160,
              label: ru ? 'В работе' : 'In progress',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StubBlock(
              icon: Icons.rate_review_outlined,
              height: 160,
              label: ru ? 'На проверке' : 'Review',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StubBlock(
              icon: Icons.check_circle_outline,
              height: 160,
              label: ru ? 'Готово' : 'Done',
            ),
          ),
        ],
      ),
    );
  }
}
