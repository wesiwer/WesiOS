import 'package:flutter/material.dart';

import '../team/services/team_service.dart';
import 'controllers/wesi_ai_chat_controller.dart';
import 'models/wesi_ai_chat_models.dart';
import 'storage/wesi_ai_local_store.dart';
import 'wesi_ai_handoff_controller.dart';
import 'wesi_ai_managed_controller.dart';
import 'wesi_ai_voice_controller.dart';
import 'wesi_ai_voice_devices.dart';
import 'wesi_ai_voice_session.dart';
import 'widgets/wesi_ai_message_content.dart';

/// Rich Wesi AI chat shell.
///
/// Kept as a separate screen while the original screen remains a safe
/// rollback target. The route can switch between implementations with one
/// small import change.
class AiAssistantV2Screen extends StatefulWidget {
  const AiAssistantV2Screen({super.key});

  @override
  State<AiAssistantV2Screen> createState() => _AiAssistantV2ScreenState();
}

class _AiAssistantV2ScreenState extends State<AiAssistantV2Screen> {
  WesiAiHandoffController? _controller;
  final TextEditingController _composer = TextEditingController();
  final WesiAiVoiceController _voice = WesiAiVoiceController();
  String _voicePrefix = '';
  WesiAiVoiceSession? _session;

  @override
  void initState() {
    super.initState();
    _voice.addListener(_onVoiceChanged);
    final employee = TeamService.current;
    if (employee != null) {
      _controller = WesiAiHandoffController(
        store: WesiAiLocalStore(employee.id),
      );
      _controller!.addListener(_refresh);
      _controller!.load();
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _onVoiceChanged() {
    if (!mounted) return;
    // В режиме разговора микрофон принадлежит сессии, а не полю ввода.
    // Иначе распознанное попадёт и в разговор, и в композер — и уйдёт
    // вторым сообщением, когда человек нажмёт «отправить».
    if (_session?.active == true) {
      setState(() {});
      return;
    }
    if (_voice.transcript.isNotEmpty || _voice.listening) {
      final next = <String>[
        _voicePrefix.trim(),
        _voice.transcript.trim(),
      ].where((part) => part.isNotEmpty).join(' ');
      if (_composer.text != next) {
        _composer.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    }
    setState(() {});
  }

  /// Включить или выключить голосовой разговор.
  Future<void> _toggleConversation(WesiAiChatController controller) async {
    final running = _session;
    if (running != null && running.active) {
      await running.stop();
      if (mounted) setState(() {});
      return;
    }
    final session = _session ??= WesiAiVoiceSession(
      ear: WesiAiDeviceEar(_voice),
      mouth: const WesiAiDeviceMouth(),
      onTurn: (text) => _speakableTurn(controller, text),
    )
      ..addListener(_refresh);
    await session.start();
    if (!mounted) return;
    if (!session.active && session.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(session.error!)),
      );
    }
    setState(() {});
  }

  /// Отправить услышанное и вернуть то, что нужно произнести.
  ///
  /// Ответ берётся из самого чата, а не из отдельного вызова: сообщение
  /// должно попасть в переписку ровно один раз, и озвучивать нужно именно
  /// то, что человек увидит на экране. В лобби ответов несколько — каждый
  /// со своим автором, и каждый прозвучит своим голосом.
  Future<List<WesiAiSpokenReply>> _speakableTurn(
    WesiAiChatController controller,
    String text,
  ) async {
    final conversationId = controller.state.activeConversation?.id;
    if (conversationId == null) return const [];
    final before = controller.state
        .messagesFor(conversationId)
        .map((m) => m.id)
        .toSet();

    await controller.addUserMessage(text);

    return spokenRepliesFrom(
      messages: controller.state.messagesFor(conversationId),
      alreadySeen: before,
    );
  }

  @override
  void dispose() {
    _controller?.removeListener(_refresh);
    _controller?.dispose();
    _session?.removeListener(_refresh);
    _session?.stop();
    _session?.dispose();
    _voice.removeListener(_onVoiceChanged);
    _voice.dispose();
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(
        body: Center(
          child: Text('Войдите в профиль сотрудника, чтобы открыть Wesi AI'),
        ),
      );
    }
    if (controller.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final active = controller.state.activeConversation;
    final messages = active == null
        ? const <WesiAiMessage>[]
        : controller.state.messagesFor(active.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wesi AI'),
        actions: [
          DropdownButton<WesiAiTier>(
            value: controller.state.tier,
            underline: const SizedBox(),
            onChanged: controller.sending
                ? null
                : (value) {
                    if (value != null) controller.setTier(value);
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final chat = _chat(controller, active, messages);
          if (!wide) return chat;
          return Row(
            children: [
              SizedBox(width: 280, child: _sidebar(controller)),
              const VerticalDivider(width: 1),
              Expanded(child: chat),
            ],
          );
        },
      ),
      drawer: MediaQuery.sizeOf(context).width < 760
          ? Drawer(child: SafeArea(child: _sidebar(controller)))
          : null,
    );
  }

  Widget _sidebar(WesiAiManagedChatController controller) {
    final visible = controller.visibleConversations;
    final archived = controller.archivedConversations;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              FilledButton.tonal(
                onPressed: controller.sending
                    ? null
                    : () => controller.createConversation(WesiAiPersona.zane),
                child: const Text('Зейн'),
              ),
              FilledButton.tonal(
                onPressed: controller.sending
                    ? null
                    : () => controller.createConversation(WesiAiPersona.nirvana),
                child: const Text('Нирвана'),
              ),
              OutlinedButton(
                onPressed: controller.sending
                    ? null
                    : () => controller.createConversation(WesiAiPersona.lobby),
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
                  selected: item.id == controller.state.activeConversationId,
                  enabled: !controller.sending,
                  personaName: _personaName(item.persona),
                  onTap: () => controller.selectConversation(item.id),
                  onAction: (action) =>
                      _conversationAction(controller, item, action),
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
                          enabled: !controller.sending,
                          onSelected: (action) =>
                              _archivedAction(controller, item, action),
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
    );
  }

  Widget _chat(
    WesiAiHandoffController controller,
    WesiAiConversation? active,
    List<WesiAiMessage> messages,
  ) {
    if (active == null) {
      return const Center(
        child: Text('Создайте чат с Зейном, Нирваной или откройте Lobby'),
      );
    }
    final hasLastError = messages.isNotEmpty &&
        messages.last.kind == WesiAiMessageKind.error;
    return Column(
      children: [
        _conversationHeader(controller, active),
        Expanded(
          child: messages.isEmpty
              ? const Center(
                  child: Text('История этого чата хранится локально'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) =>
                      _messageTile(messages[index], index == messages.length - 1),
                ),
        ),
        if (hasLastError && !controller.sending)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: controller.regenerateLastResponse,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Повторить ответ'),
                ),
                TextButton.icon(
                  onPressed: controller.clearLastError,
                  icon: const Icon(Icons.close),
                  label: const Text('Скрыть ошибку'),
                ),
              ],
            ),
          ),
        if (controller.sending) const LinearProgressIndicator(),
        if (_session?.active == true)
          _conversationStatus(_session!)
        else if (_voice.listening)
          _voiceStatus(),
        _composerBar(controller),
      ],
    );
  }

  Widget _conversationHeader(
    WesiAiHandoffController controller,
    WesiAiConversation active,
  ) {
    if (active.persona == WesiAiPersona.lobby) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(
          children: [
            const Text('Режим лобби: '),
            const SizedBox(width: 8),
            DropdownButton<WesiAiLobbyMode>(
              value: active.lobbyMode,
              onChanged: controller.sending
                  ? null
                  : (value) {
                      if (value != null) controller.setLobbyMode(value);
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
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Text('Сейчас: ${_personaName(active.persona)}'),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: controller.sending
                ? null
                : () => _handoff(controller, active),
            icon: const Icon(Icons.swap_horiz),
            label: Text(
              active.persona == WesiAiPersona.zane
                  ? 'Передать Нирване'
                  : 'Передать Зейну',
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageTile(WesiAiMessage message, bool latest) {
    final theme = Theme.of(context);
    final mine = message.author == WesiAiMessageAuthor.user;
    final error = message.kind == WesiAiMessageKind.error;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: error
              ? theme.colorScheme.errorContainer
              : mine
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest.withOpacity(0.55),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WesiAiMessageContent(
              key: ValueKey(message.id),
              message: message,
              animateText: latest,
            ),
            const SizedBox(height: 5),
            Text(
              _authorName(message.author),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Что делает разговор прямо сейчас.
  ///
  /// Без этой строки голосовой режим — чёрный ящик: человек не знает,
  /// слышат ли его, думает ли система или уже отвечает, и начинает говорить
  /// в тишину.
  Widget _conversationStatus(WesiAiVoiceSession session) {
    final (IconData icon, String label) = switch (session.phase) {
      WesiAiVoicePhase.listening => (Icons.mic, 'Слушаю…'),
      WesiAiVoicePhase.thinking => (Icons.more_horiz, 'Думаю…'),
      WesiAiVoicePhase.speaking => (
          Icons.graphic_eq,
          switch (session.speaker) {
            WesiAiMessageAuthor.zane => 'Говорит Зейн',
            WesiAiMessageAuthor.nirvana => 'Говорит Нирвана',
            _ => 'Отвечает Wesi AI',
          }
        ),
      WesiAiVoicePhase.off => (Icons.headset_off, 'Разговор завершён'),
    };
    final heard = session.heard.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              session.phase == WesiAiVoicePhase.listening && heard.isNotEmpty
                  ? heard
                  : label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (session.phase == WesiAiVoicePhase.speaking ||
              session.phase == WesiAiVoicePhase.thinking)
            TextButton(
              // Перебивание нажатием, а не голосом: микрофон во время
              // озвучки закрыт намеренно, иначе он услышит сам себя.
              onPressed: session.bargeIn,
              child: const Text('Перебить'),
            ),
        ],
      ),
    );
  }

  Widget _voiceStatus() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _voice.transcript.isEmpty ? 'Слушаю… говорите' : _voice.transcript,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );

  Widget _composerBar(WesiAiChatController controller) => Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _composer,
                enabled: !controller.sending,
                minLines: 1,
                maxLines: 5,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Сообщение Wesi AI',
                ),
                onSubmitted: controller.sending ? null : (_) => _send(controller),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: _voice.listening ? 'Остановить диктовку' : 'Голосовой ввод',
              // Диктовка и разговор делят один микрофон, поэтому во время
              // разговора диктовать нельзя: два хозяина у одного устройства
              // ввода — это застрявший микрофон.
              onPressed: controller.sending || _session?.active == true
                  ? null
                  : _toggleVoice,
              icon: Icon(_voice.listening ? Icons.stop : Icons.mic_none),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: _session?.active == true
                  ? 'Завершить голосовой разговор'
                  : 'Голосовой разговор',
              onPressed: () => _toggleConversation(controller),
              style: _session?.active == true
                  ? IconButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                    )
                  : null,
              icon: Icon(_session?.active == true
                  ? Icons.headset_off
                  : Icons.headset_mic_outlined),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              onPressed: controller.sending ? null : () => _send(controller),
              icon: controller.sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_upward),
            ),
          ],
        ),
      );

  Future<void> _toggleVoice() async {
    if (_voice.listening) {
      await _voice.stop();
      return;
    }
    _voicePrefix = _composer.text.trim();
    _voice.clearTranscript();
    await _voice.start();
    if (!_voice.available && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _voice.error ?? 'На этом устройстве голосовой ввод недоступен',
          ),
        ),
      );
    }
  }

  Future<void> _send(WesiAiChatController controller) async {
    if (_voice.listening) await _voice.stop();
    final text = _composer.text.trim();
    if (text.isEmpty || controller.sending) return;
    _composer.clear();
    _voicePrefix = '';
    _voice.clearTranscript();
    await controller.addUserMessage(text);
  }

  Future<void> _handoff(
    WesiAiHandoffController controller,
    WesiAiConversation source,
  ) async {
    final target = source.persona == WesiAiPersona.zane
        ? WesiAiPersona.nirvana
        : WesiAiPersona.zane;
    final accepted = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Передать задачу: ${_personaName(target)}?'),
            content: Text(
              'Wesi AI создаст отдельный чат с ${_personaName(target)} и передаст ему текущий текстовый контекст. Исходный чат останется без изменений.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Передать'),
              ),
            ],
          ),
        ) ??
        false;
    if (accepted) await controller.handoffTo(target);
  }

  Future<void> _conversationAction(
    WesiAiManagedChatController controller,
    WesiAiConversation conversation,
    String action,
  ) async {
    if (action == 'pin') {
      await controller.togglePinned(conversation.id);
    } else if (action == 'rename') {
      await _rename(controller, conversation);
    } else if (action == 'archive') {
      await controller.archiveConversation(conversation.id);
    } else if (action == 'delete' && await _confirmDelete(conversation.title)) {
      await controller.deleteConversation(conversation.id);
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
    if (result != null) {
      await controller.renameConversation(conversation.id, result);
    }
  }

  Future<bool> _confirmDelete(String title) async =>
      await showDialog<bool>(
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

  String _personaName(WesiAiPersona persona) => switch (persona) {
        WesiAiPersona.zane => 'Зейн',
        WesiAiPersona.nirvana => 'Нирвана',
        WesiAiPersona.lobby => 'Лобби',
      };

  String _authorName(WesiAiMessageAuthor author) => switch (author) {
        WesiAiMessageAuthor.user => 'Вы',
        WesiAiMessageAuthor.zane => 'Зейн',
        WesiAiMessageAuthor.nirvana => 'Нирвана',
        WesiAiMessageAuthor.system => 'Wesi AI',
        WesiAiMessageAuthor.tool => 'WesiOS',
      };
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
            const PopupMenuItem(
              value: 'rename',
              child: Text('Переименовать'),
            ),
            const PopupMenuItem(value: 'archive', child: Text('В архив')),
            const PopupMenuItem(value: 'delete', child: Text('Удалить')),
          ],
        ),
      );
}
