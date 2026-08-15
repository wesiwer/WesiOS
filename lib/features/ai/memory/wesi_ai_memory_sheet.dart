import 'package:flutter/material.dart';

import '../controllers/wesi_ai_chat_controller.dart';
import 'wesi_ai_memory_models.dart';

class WesiAiMemorySheet extends StatelessWidget {
  final WesiAiChatController controller;

  const WesiAiMemorySheet({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final state = controller.state;
          final active = state.activeConversation;
          final activeMemory = active == null
              ? null
              : state.conversationMemory[active.id] ??
                  WesiAiConversationMemoryState(conversationId: active.id);
          final entries = <WesiAiMemoryEntry>[...state.memoryEntries]
            ..sort((a, b) {
              if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
              if (a.manual != b.manual) return a.manual ? -1 : 1;
              return b.updatedAt.compareTo(a.updatedAt);
            });

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.memory_rounded),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Память Wesi AI',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Добавить вручную',
                        onPressed: () => _addMemory(context),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Автоматически запоминать важное'),
                    subtitle: const Text(
                      'История остаётся local-first; сервер получает только ограниченный context package.',
                    ),
                    value: state.memorySettings.autoMemoryEnabled,
                    onChanged: controller.setAutoMemoryEnabled,
                  ),
                  if (activeMemory != null)
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Память в текущем чате'),
                      value: activeMemory.memoryEnabled,
                      onChanged: controller.setActiveConversationMemoryEnabled,
                    ),
                  const Divider(),
                  Flexible(
                    child: entries.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Text(
                              'Пока ничего не сохранено. Wesi AI будет добавлять только устойчивые факты, решения и важный контекст.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(_scopeIcon(entry.scope)),
                                title: Text(entry.text),
                                subtitle: Text(
                                  '${_scopeLabel(entry.scope)}${entry.manual ? ' · вручную' : ''}',
                                ),
                                trailing: IconButton(
                                  tooltip: 'Удалить из памяти',
                                  onPressed: () => controller.deleteMemory(entry.id),
                                  icon: const Icon(Icons.delete_outline_rounded),
                                ),
                              );
                            },
                          ),
                  ),
                  if (entries.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _clearScope(context),
                        icon: const Icon(Icons.cleaning_services_outlined),
                        label: const Text('Очистить раздел памяти'),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );

  Future<void> _addMemory(BuildContext context) async {
    final textController = TextEditingController();
    var scope = WesiAiMemoryScope.shared;
    final result = await showDialog<(WesiAiMemoryScope, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Добавить в память'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<WesiAiMemoryScope>(
                value: scope,
                decoration: const InputDecoration(labelText: 'Раздел'),
                items: WesiAiMemoryScope.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(_scopeLabel(value)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setState(() => scope = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Что запомнить',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                (scope, textController.text.trim()),
              ),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    textController.dispose();
    if (result == null || result.$2.isEmpty) return;
    final ok = await controller.addManualMemory(result.$1, result.$2);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Не удалось сохранить запись. Проверьте раздел, длину текста и отсутствие секретов.',
          ),
        ),
      );
    }
  }

  Future<void> _clearScope(BuildContext context) async {
    final scope = await showDialog<WesiAiMemoryScope>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Очистить раздел'),
        children: WesiAiMemoryScope.values
            .map(
              (value) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, value),
                child: Text(_scopeLabel(value)),
              ),
            )
            .toList(growable: false),
      ),
    );
    if (scope == null) return;
    await controller.clearMemoryScope(scope);
  }

  static String _scopeLabel(WesiAiMemoryScope scope) => switch (scope) {
        WesiAiMemoryScope.shared => 'Общая',
        WesiAiMemoryScope.zane => 'Зейн',
        WesiAiMemoryScope.nirvana => 'Нирвана',
        WesiAiMemoryScope.project => 'Проект',
      };

  static IconData _scopeIcon(WesiAiMemoryScope scope) => switch (scope) {
        WesiAiMemoryScope.shared => Icons.people_alt_outlined,
        WesiAiMemoryScope.zane => Icons.bolt_outlined,
        WesiAiMemoryScope.nirvana => Icons.spa_outlined,
        WesiAiMemoryScope.project => Icons.folder_outlined,
      };
}
