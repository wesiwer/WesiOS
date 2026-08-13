import 'package:flutter/material.dart';
import '../team/services/team_service.dart';
import 'controllers/wesi_ai_chat_controller.dart';
import 'models/wesi_ai_chat_models.dart';
import 'storage/wesi_ai_local_store.dart';
import 'wesi_ai_managed_controller.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});
  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  WesiAiManagedChatController? controller;
  final composer = TextEditingController();

  @override
  void initState() {
    super.initState();
    final employee = TeamService.current;
    if (employee != null) {
      controller = WesiAiManagedChatController(
        store: WesiAiLocalStore(employee.id),
      );
      controller!.addListener(_refresh);
      controller!.load();
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller?.removeListener(_refresh);
    controller?.dispose();
    composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null) {
      return const Scaffold(
        body: Center(
          child: Text('Войдите в профиль сотрудника, чтобы открыть Wesi AI'),
        ),
      );
    }
    if (c.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final active = c.state.activeConversation;
    final messages = active == null
        ? const <WesiAiMessage>[]
        : c.state.messagesFor(active.id);
    final visible = c.visibleConversations;
    final archived = c.archivedConversations;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wesi AI'),
        actions: [
          DropdownButton<WesiAiTier>(
            value: c.state.tier,
            underline: const SizedBox(),
            onChanged: c.sending
                ? null
                : (v) {
                    if (v != null) c.setTier(v);
                  },
            items: const [
              DropdownMenuItem(
                value: WesiAiTier.fast,
                child: Text('Wesi AI Быстрый'),
              ),
              DropdownMenuItem(
                value: WesiAiTier.pro,
                child: Text('Wesi AI Pro'),
              ),
              DropdownMenuItem(
                value: WesiAiTier.maximum,
                child: Text('Wesi AI Максимальный'),
              ),
            ],
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 280,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      FilledButton.tonal(
                        onPressed: c.sending
                            ? null
                            : () => c.createConversation(WesiAiPersona.zane),
                        child: const Text('Зейн'),
                      ),
                      FilledButton.tonal(
                        onPressed: c.sending
                            ? null
                            : () => c.createConversation(WesiAiPersona.nirvana),
                        child: const Text('Нирвана'),
                      ),
                      OutlinedButton(
                        onPressed: c.sending
                            ? null
                            : () => c.createConversation(WesiAiPersona.lobby),
                        child: const Text('Лобби'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final item in visible)
                        _ConversationTile(
                          item: item,
                          selected: item.id == c.state.activeConversationId,
                          enabled: !c.sending,
                          personaName: _personaName(item.persona),
                          onTap: () => c.selectConversation(item.id),
                          onAction: (action) => _conversationAction(c, item, action),
                        ),
                      if (archived.isNotEmpty)
                        ExpansionTile(
                          title: Text('Архив (${archived.length})'),
                          children: [
                            for (final item in archived)
                              ListTile(
                                dense: true,
                                title: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(_personaName(item.persona)),
                                trailing: PopupMenuButton<String>(
                                  enabled: !c.sending,
                                  onSelected: (action) =>
                                      _archivedAction(c, item, action),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'restore',
                                      child: Text('Восстановить'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Удалить'),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: active == null
                ? const Center(
                    child: Text('Выберите Зейна или Нирвану и начните чат'),
                  )
                : Column(
                    children: [
                      if (active.persona == WesiAiPersona.lobby)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: Row(
                            children: [
                              const Text('Режим лобби: '),
                              const SizedBox(width: 8),
                              DropdownButton<WesiAiLobbyMode>(
                                value: active.lobbyMode,
                                onChanged: c.sending
                                    ? null
                                    : (v) {
                                        if (v != null) c.setLobbyMode(v);
                                      },
                                items: const [
                                  DropdownMenuItem(
                                    value: WesiAiLobbyMode.smart,
                                    child: Text('Умное Lobby'),
                                  ),
                                  DropdownMenuItem(
                                    value: WesiAiLobbyMode.both,
                                    child: Text('Оба отвечают'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: messages.isEmpty
                            ? const Center(
                                child: Text('История этого чата хранится локально'),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: messages.length,
                                itemBuilder: (_, i) {
                                  final m = messages[i];
                                  return ListTile(
                                    leading: m.kind == WesiAiMessageKind.error
                                        ? const Icon(Icons.error_outline)
                                        : null,
                                    title: Text(m.text),
                                    subtitle: Text(_authorName(m.author)),
                                  );
                                },
                              ),
                      ),
                      if (c.sending) const LinearProgressIndicator(),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: composer,
                                enabled: !c.sending,
                                minLines: 1,
                                maxLines: 5,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: 'Сообщение Wesi AI',
                                ),
                                onSubmitted:
                                    c.sending ? null : (_) => _send(c),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton.filled(
                              onPressed: c.sending ? null : () => _send(c),
                              icon: c.sending
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.arrow_upward),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _conversationAction(
    WesiAiManagedChatController controller,
    WesiAiConversation conversation,
    String action,
  ) async {
    switch (action) {
      case 'pin':
        await controller.togglePinned(conversation.id);
      case 'rename':
        await _rename(controller, conversation);
      case 'archive':
        await controller.archiveConversation(conversation.id);
      case 'delete':
        if (await _confirmDelete(conversation.title)) {
          await controller.deleteConversation(conversation.id);
        }
    }
  }

  Future<void> _archivedAction(
    WesiAiManagedChatController controller,
    WesiAiConversation conversation,
    String action,
  ) async {
    if (action == 'restore') {
      await controller.restoreConversation(conversation.id);
    } else if (action == 'delete' && await _confirmDelete(conversation.title)) {
      await controller.deleteConversation(conversation.id);
    }
  }

  Future<void> _rename(
    WesiAiManagedChatController controller,
    WesiAiConversation conversation,
  ) async {
    final editor = TextEditingController(text: conversation.title);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Переименовать чат'),
        content: TextField(
          controller: editor,
          autofocus: true,
          maxLength: 120,
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, editor.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    editor.dispose();
    if (result != null) await controller.renameConversation(conversation.id, result);
  }

  Future<bool> _confirmDelete(String title) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Удалить чат?'),
            content: Text('Локальная история «$title» будет удалена с этого устройства.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Удалить'),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _personaName(WesiAiPersona p) => switch (p) {
        WesiAiPersona.zane => 'Зейн',
        WesiAiPersona.nirvana => 'Нирвана',
        WesiAiPersona.lobby => 'Лобби',
      };

  String _authorName(WesiAiMessageAuthor a) => switch (a) {
        WesiAiMessageAuthor.user => 'Вы',
        WesiAiMessageAuthor.zane => 'Зейн',
        WesiAiMessageAuthor.nirvana => 'Нирвана',
        WesiAiMessageAuthor.system => 'Wesi AI',
        WesiAiMessageAuthor.tool => 'WesiOS',
      };

  Future<void> _send(WesiAiChatController c) async {
    final text = composer.text.trim();
    if (text.isEmpty || c.sending) return;
    composer.clear();
    await c.addUserMessage(text);
  }
}

class _ConversationTile extends StatelessWidget {
  final WesiAiConversation item;
  final bool selected;
  final bool enabled;
  final String personaName;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;

  const _ConversationTile({
    required this.item,
    required this.selected,
    required this.enabled,
    required this.personaName,
    required this.onTap,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        selected: selected,
        leading: item.pinned ? const Icon(Icons.push_pin, size: 18) : null,
        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(personaName),
        onTap: enabled ? onTap : null,
        trailing: PopupMenuButton<String>(
          enabled: enabled,
          onSelected: onAction,
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'pin',
              child: Text(item.pinned ? 'Открепить' : 'Закрепить'),
            ),
            const PopupMenuItem(value: 'rename', child: Text('Переименовать')),
            const PopupMenuItem(value: 'archive', child: Text('В архив')),
            const PopupMenuItem(value: 'delete', child: Text('Удалить')),
          ],
        ),
      );
}
