import 'package:flutter/material.dart';

import '../models/wesi_ai_chat_models.dart';
import '../wesi_ai_managed_controller.dart';

class WesiAiSubagentsSheet extends StatefulWidget {
  final WesiAiManagedChatController controller;

  const WesiAiSubagentsSheet({
    super.key,
    required this.controller,
  });

  @override
  State<WesiAiSubagentsSheet> createState() => _WesiAiSubagentsSheetState();
}

class _WesiAiSubagentsSheetState extends State<WesiAiSubagentsSheet> {
  static const _agents = <_SubagentDefinition>[
    _SubagentDefinition(
      name: 'Coding / Flutter Agent',
      description: 'Код, Flutter, архитектура и точечная реализация.',
      icon: Icons.code_rounded,
    ),
    _SubagentDefinition(
      name: 'QA Agent',
      description: 'Тесты, регрессии, edge cases и воспроизведение ошибок.',
      icon: Icons.fact_check_outlined,
    ),
    _SubagentDefinition(
      name: 'Build Agent',
      description: 'CI/CD, сборки, зависимости и релизные проблемы.',
      icon: Icons.build_circle_outlined,
    ),
    _SubagentDefinition(
      name: 'Research Agent',
      description: 'Исследование вариантов, документации и фактов.',
      icon: Icons.manage_search_rounded,
    ),
    _SubagentDefinition(
      name: 'Documents Agent',
      description: 'Документы, спецификации, отчёты и структурирование.',
      icon: Icons.description_outlined,
    ),
    _SubagentDefinition(
      name: 'Media Agent',
      description: 'Медиа-задачи, ассеты и анализ материалов.',
      icon: Icons.perm_media_outlined,
    ),
    _SubagentDefinition(
      name: 'Review Agent',
      description: 'Независимая проверка решения и поиск слабых мест.',
      icon: Icons.rate_review_outlined,
    ),
    _SubagentDefinition(
      name: 'Security Reviewer',
      description: 'Авторизация, секреты, права и security-регрессии.',
      icon: Icons.security_outlined,
    ),
  ];

  WesiAiManagedChatController get controller => widget.controller;

  bool get _tierSupportsSubagents => controller.state.tier != WesiAiTier.fast;

  bool get _directPersonaSelected {
    final persona = controller.state.activeConversation?.persona;
    return persona == WesiAiPersona.zane || persona == WesiAiPersona.nirvana;
  }

  String? get _unavailableReason {
    if (!_tierSupportsSubagents) {
      return 'Субагенты доступны в Pro и Maximum. Переключите уровень в верхней панели.';
    }
    if (controller.state.activeConversation == null) {
      return 'Сначала откройте чат с Зейном или Нирваной.';
    }
    if (!_directPersonaSelected) {
      return 'Для ручного вызова откройте прямой чат с Зейном или Нирваной. В Lobby ведущая персона выбирается автоматически.';
    }
    return null;
  }

  Future<void> _invoke(_SubagentDefinition agent) async {
    if (_unavailableReason != null) return;
    final taskController = TextEditingController();
    final task = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Задача для ${agent.name}'),
        content: TextField(
          controller: taskController,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'Что именно нужно проверить или сделать?',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final value = taskController.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Позвать'),
          ),
        ],
      ),
    );
    taskController.dispose();
    if (task == null || !mounted) return;

    final result = await controller.submitUserMessage(
      'Позови субагента «${agent.name}» и поручи ему: $task',
      thinkingMode: true,
    );
    if (!mounted) return;
    if (result == WesiAiMessageSubmitResult.accepted) {
      Navigator.of(context).pop();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_submitError(result))),
    );
  }

  String _submitError(WesiAiMessageSubmitResult result) => switch (result) {
        WesiAiMessageSubmitResult.queueFull => 'Очередь Wesi AI заполнена.',
        WesiAiMessageSubmitResult.invalidAttachments =>
          'Некорректные вложения.',
        WesiAiMessageSubmitResult.persistenceFailed =>
          'Не удалось сохранить задачу в очередь.',
        WesiAiMessageSubmitResult.unavailable => 'Сейчас субагент недоступен.',
        WesiAiMessageSubmitResult.accepted => '',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reason = _unavailableReason;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Субагенты',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Выберите специалиста вручную. В Pro и Maximum Wesi AI также может создавать узких Dynamic Sub-Agents автоматически.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (reason != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(reason),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: _agents.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final agent = _agents[index];
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: CircleAvatar(child: Icon(agent.icon)),
                      title: Text(agent.name),
                      subtitle: Text(agent.description),
                      trailing: FilledButton.tonal(
                        onPressed: reason == null ? () => _invoke(agent) : null,
                        child: const Text('Позвать'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubagentDefinition {
  final String name;
  final String description;
  final IconData icon;

  const _SubagentDefinition({
    required this.name,
    required this.description,
    required this.icon,
  });
}
