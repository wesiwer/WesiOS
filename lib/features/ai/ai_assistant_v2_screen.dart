import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../team/services/team_service.dart';
import 'controllers/wesi_ai_chat_controller.dart';
import 'models/wesi_ai_attachment.dart';
import 'models/wesi_ai_chat_models.dart';
import 'storage/wesi_ai_local_store.dart';
import 'wesi_ai_chat_ui.dart';
import 'wesi_ai_handoff_controller.dart';
import 'wesi_ai_managed_controller.dart';
import 'wesi_ai_voice_controller.dart';
import 'wesi_ai_voice_devices.dart';
import 'wesi_ai_voice_session.dart';
import 'widgets/wesi_ai_camera_capture.dart';
import 'widgets/wesi_ai_message_content.dart';

class AiAssistantV2Screen extends StatefulWidget {
  const AiAssistantV2Screen({super.key});

  @override
  State<AiAssistantV2Screen> createState() => _AiAssistantV2ScreenState();
}

class _AiAssistantV2ScreenState extends State<AiAssistantV2Screen> {
  WesiAiHandoffController? _controller;
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final WesiAiVoiceController _voice = WesiAiVoiceController();
  final List<WesiAiAttachment> _attachments = <WesiAiAttachment>[];

  String _voicePrefix = '';
  WesiAiVoiceSession? _session;
  WesiAiUiMode _uiMode = WesiAiUiMode.classic;
  DateTime? _sendingSince;
  Timer? _sendingTicker;
  bool _creatingInitial = false;

  @override
  void initState() {
    super.initState();
    _voice.addListener(_onVoiceChanged);
    final employee = TeamService.current;
    if (employee != null) {
      _controller = WesiAiHandoffController(
        store: WesiAiLocalStore(employee.id),
      )..addListener(_refresh);
      unawaited(_controller!.load());
    }
  }

  void _refresh() {
    final controller = _controller;
    if (controller != null && !controller.loading) {
      if (WesiAiChatUi.shouldCreateInitialConversation(controller.state) &&
          !_creatingInitial) {
        _creatingInitial = true;
        unawaited(
          controller.createConversation(WesiAiPersona.zane).whenComplete(() {
            _creatingInitial = false;
            if (mounted) setState(() {});
          }),
        );
      }
      _syncSendingClock(controller.sending);
    }
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _syncSendingClock(bool sending) {
    if (sending) {
      if (_sendingSince != null) return;
      _sendingSince = DateTime.now();
      _sendingTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      return;
    }
    _sendingSince = null;
    _sendingTicker?.cancel();
    _sendingTicker = null;
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _onVoiceChanged() {
    if (!mounted) return;
    if (_session?.active == true) {
      setState(() {});
      return;
    }
    if (_voice.transcript.isNotEmpty || _voice.listening) {
      final next = <String>[_voicePrefix.trim(), _voice.transcript.trim()]
          .where((part) => part.isNotEmpty)
          .join(' ');
      if (_composer.text != next) {
        _composer.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _sendingTicker?.cancel();
    _controller?.removeListener(_refresh);
    _controller?.dispose();
    _session?.removeListener(_refresh);
    _session?.stop();
    _session?.dispose();
    _voice.removeListener(_onVoiceChanged);
    _voice.dispose();
    _composer.dispose();
    _scroll.dispose();
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
      appBar: _appBar(controller),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 820;
          final chat = _chat(controller, active, messages);
          if (!wide) return chat;
          return Row(
            children: [
              SizedBox(width: 308, child: _sidebar(controller)),
              const VerticalDivider(width: 1),
              Expanded(child: chat),
            ],
          );
        },
      ),
      drawer: MediaQuery.sizeOf(context).width < 820
          ? Drawer(child: SafeArea(child: _sidebar(controller)))
          : null,
    );
  }

  PreferredSizeWidget _appBar(WesiAiHandoffController controller) => AppBar(
        titleSpacing: 14,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/app_icon.png',
                width: 30,
                height: 30,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                controller.state.activeProject?.title ?? 'Wesi AI',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<WesiAiUiMode>(
            tooltip: 'Режим отображения ответа',
            initialValue: _uiMode,
            onSelected: (mode) => setState(() => _uiMode = mode),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: WesiAiUiMode.classic,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.chat_bubble_outline_rounded),
                  title: Text('Классический'),
                ),
              ),
              PopupMenuItem(
                value: WesiAiUiMode.thinking,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.psychology_alt_outlined),
                  title: Text('Думающий'),
                  subtitle: Text('Безопасное резюме обработки'),
                ),
              ),
            ],
            icon: Icon(
              _uiMode == WesiAiUiMode.thinking
                  ? Icons.psychology_alt_outlined
                  : Icons.chat_bubble_outline_rounded,
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<WesiAiTier>(
              value: controller.state.tier,
              onChanged: controller.processing
                  ? null
                  : (value) {
                      if (value != null) controller.setTier(value);
                    },
              items: WesiAiTier.values
                  .map(
                    (tier) => DropdownMenuItem<WesiAiTier>(
                      value: tier,
                      child: Text(WesiAiChatUi.tierLabel(tier)),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const SizedBox(width: 12),
        ],
      );

  Widget _sidebar(WesiAiManagedChatController controller) {
    final projects = controller.visibleProjects;
    final visible = controller.visibleConversations;
    final archived = controller.archivedConversations;
    final activeProject = controller.state.activeProject;
    final enabled = !controller.processing;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  width: 34,
                  height: 34,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Wesi AI',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: enabled
                  ? () => controller.createConversation(WesiAiPersona.zane)
                  : null,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Новый чат'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Проекты',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Новый проект',
                onPressed: enabled ? () => _createProject(controller) : null,
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                dense: true,
                selected: controller.state.activeProjectId == null,
                leading: const Icon(Icons.chat_bubble_outline),
                title: const Text('Без проекта'),
                onTap: enabled ? () => controller.selectProject(null) : null,
              ),
              for (final project in projects)
                ListTile(
                  dense: true,
                  selected: project.id == controller.state.activeProjectId,
                  leading: Icon(
                    project.pinned
                        ? Icons.folder_special
                        : Icons.folder_outlined,
                  ),
                  title: Text(
                    project.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: project.description.trim().isEmpty
                      ? null
                      : Text(
                          project.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  onTap: enabled
                      ? () => controller.selectProject(project.id)
                      : null,
                  trailing: PopupMenuButton<String>(
                    enabled: enabled,
                    onSelected: (action) =>
                        _projectAction(controller, project, action),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'pin',
                        child: Text(project.pinned ? 'Открепить' : 'Закрепить'),
                      ),
                      const PopupMenuItem(
                        value: 'context',
                        child: Text('Описание и инструкции'),
                      ),
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text('Переименовать'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Удалить проект'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (activeProject != null &&
            (activeProject.description.trim().isNotEmpty ||
                activeProject.instructions.trim().isNotEmpty))
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (activeProject.description.trim().isNotEmpty)
                    Text(
                      activeProject.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (activeProject.instructions.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Есть инструкции проекта',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 5, 8, 7),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ActionChip(
                avatar: const Icon(Icons.bolt_rounded, size: 16),
                label: const Text('Зейн'),
                onPressed: enabled
                    ? () => controller.createConversation(WesiAiPersona.zane)
                    : null,
              ),
              ActionChip(
                avatar: const Icon(Icons.spa_outlined, size: 16),
                label: const Text('Нирвана'),
                onPressed: enabled
                    ? () =>
                        controller.createConversation(WesiAiPersona.nirvana)
                    : null,
              ),
              ActionChip(
                avatar: const Icon(Icons.groups_2_outlined, size: 16),
                label: const Text('Лобби'),
                onPressed: enabled
                    ? () => controller.createConversation(WesiAiPersona.lobby)
                    : null,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            children: [
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('В этом проекте пока нет чатов.'),
                ),
              for (final item in visible)
                _ConversationTile(
                  item: item,
                  selected: item.id == controller.state.activeConversationId,
                  enabled: enabled,
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
                          enabled: enabled,
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
      if (_creatingInitial) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Text(
          controller.state.activeProject == null
              ? 'Создайте чат или выберите проект'
              : 'Создайте чат внутри проекта «${controller.state.activeProject!.title}»',
        ),
      );
    }

    final hasLastError =
        messages.isNotEmpty && messages.last.kind == WesiAiMessageKind.error;
    return Column(
      children: [
        _conversationHeader(controller, active),
        Expanded(
          child: messages.isEmpty
              ? _emptyConversationState(active)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                  itemCount: messages.length,
                  itemBuilder: (context, index) =>
                      _messageTile(messages[index], index == messages.length - 1),
                ),
        ),
        if (hasLastError && !controller.processing)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Wrap(
              spacing: 8,
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
        if (controller.sending) _sendingStatus(),
        if (_session?.active == true)
          _conversationStatus(_session!)
        else if (_voice.listening)
          _voiceStatus(),
        _composerBar(controller),
      ],
    );
  }

  Widget _emptyConversationState(WesiAiConversation active) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 90),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  width: 78,
                  height: 78,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                WesiAiChatUi.personaEmptyLabel(active.persona),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                active.projectId == null
                    ? 'Напишите сообщение, задайте вопрос или прикрепите файл.'
                    : 'Контекст и инструкции текущего проекта будут учтены автоматически.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sendingStatus() {
    final since = _sendingSince;
    final elapsed =
        since == null ? Duration.zero : DateTime.now().difference(since);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 7),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 9),
          Text(WesiAiChatUi.sendingLabel(elapsed)),
        ],
      ),
    );
  }

  Widget _conversationHeader(
    WesiAiHandoffController controller,
    WesiAiConversation active,
  ) {
    final enabled = !controller.processing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Row(
        children: [
          PopupMenuButton<WesiAiPersona>(
            enabled: enabled,
            tooltip: 'Персона Wesi AI',
            onSelected: controller.createConversation,
            itemBuilder: (_) => const [
              PopupMenuItem(value: WesiAiPersona.zane, child: Text('Зейн')),
              PopupMenuItem(
                value: WesiAiPersona.nirvana,
                child: Text('Нирвана'),
              ),
              PopupMenuItem(value: WesiAiPersona.lobby, child: Text('Лобби')),
            ],
            child: Chip(
              avatar: Icon(_personaIcon(active.persona), size: 17),
              label: Text(_personaName(active.persona)),
            ),
          ),
          if (active.persona == WesiAiPersona.lobby) ...[
            const SizedBox(width: 8),
            DropdownButton<WesiAiLobbyMode>(
              value: active.lobbyMode,
              underline: const SizedBox(),
              onChanged: enabled
                  ? (value) {
                      if (value != null) controller.setLobbyMode(value);
                    }
                  : null,
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
          const Spacer(),
          if (active.persona != WesiAiPersona.lobby)
            TextButton.icon(
              onPressed: enabled ? () => _handoff(controller, active) : null,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
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
    final assistant = message.author == WesiAiMessageAuthor.zane ||
        message.author == WesiAiMessageAuthor.nirvana;
    final toolLike = message.author == WesiAiMessageAuthor.tool ||
        message.kind == WesiAiMessageKind.action ||
        message.kind == WesiAiMessageKind.status;
    final error = message.kind == WesiAiMessageKind.error;
    final rawAttachments = message.metadata['attachments'];
    final attachmentMaps = rawAttachments is List
        ? rawAttachments.whereType<Map>().toList(growable: false)
        : const <Map>[];

    if (toolLike && !mine) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 760),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.extension_outlined, size: 17),
              const SizedBox(width: 8),
              Flexible(child: Text(message.text)),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 780),
        margin: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (assistant)
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 6),
                child: Text(
                  _authorName(message.author),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (assistant && _uiMode == WesiAiUiMode.thinking)
              _reasoningSummary(message),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: mine ? 14 : 2,
                vertical: mine ? 10 : 4,
              ),
              decoration: BoxDecoration(
                color: error
                    ? theme.colorScheme.errorContainer
                    : mine
                        ? theme.colorScheme.surfaceContainerHighest
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (attachmentMaps.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: attachmentMaps.map((raw) {
                        final map = Map<String, dynamic>.from(raw);
                        final mime = '${map['mimeType'] ?? ''}';
                        return Chip(
                          avatar: Icon(
                            mime.startsWith('image/')
                                ? Icons.image_outlined
                                : Icons.attach_file,
                            size: 16,
                          ),
                          label: Text('${map['name'] ?? 'Файл'}'),
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(growable: false),
                    ),
                    const SizedBox(height: 8),
                  ],
                  WesiAiMessageContent(
                    key: ValueKey(message.id),
                    message: message,
                    animateText: latest && assistant,
                  ),
                ],
              ),
            ),
            if (assistant && latest && message.text.trim().isNotEmpty)
              _followUps(message.text),
            if (!assistant && !mine && !toolLike)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  _authorName(message.author),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _reasoningSummary(WesiAiMessage message) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.psychology_alt_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                WesiAiChatUi.safeReasoningSummary(message),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );

  Widget _followUps(String answer) {
    final suggestions = WesiAiChatUi.followUps(answer);
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (final suggestion in suggestions)
            ActionChip(
              avatar: const Icon(
                Icons.subdirectory_arrow_right_rounded,
                size: 16,
              ),
              label: Text(suggestion),
              onPressed: () {
                _composer.text = suggestion;
                _composer.selection =
                    TextSelection.collapsed(offset: suggestion.length);
              },
            ),
        ],
      ),
    );
  }

  Widget _composerBar(WesiAiManagedChatController controller) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 5, 12, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (controller.queuedTurnCount > 0)
                      Container(
                        margin: const EdgeInsets.fromLTRB(4, 2, 4, 7),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'В очереди: ${controller.queuedTurnCount}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              controller.queuedTurns
                                  .take(3)
                                  .map((turn) => turn.preview)
                                  .join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    if (_attachments.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (var index = 0;
                                index < _attachments.length;
                                index++)
                              InputChip(
                                avatar: Icon(
                                  _attachments[index]
                                          .mimeType
                                          .startsWith('image/')
                                      ? Icons.image_outlined
                                      : Icons.attach_file,
                                  size: 16,
                                ),
                                label: Text(
                                  '${_attachments[index].name} · ${_formatBytes(_attachments[index].byteSize)}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onDeleted: () => setState(
                                  () => _attachments.removeAt(index),
                                ),
                              ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: _composer,
                      minLines: 1,
                      maxLines: 6,
                      decoration: InputDecoration(
                        hintText: controller.sending
                            ? 'Дополните запрос — сообщение встанет в очередь'
                            : 'Спроси Wesi AI о чём угодно',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: (_) => _send(controller),
                    ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Прикрепить файл',
                          onPressed: _pickAttachments,
                          icon: const Icon(Icons.add_rounded),
                        ),
                        IconButton(
                          tooltip: 'Камера',
                          onPressed: _capturePhoto,
                          icon: const Icon(Icons.photo_camera_outlined),
                        ),
                        const Spacer(),
                        if (controller.sending || controller.queuedTurnCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              controller.sending
                                  ? 'Ответ обрабатывается'
                                  : 'Обрабатываю очередь',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        IconButton(
                          tooltip: _voice.listening
                              ? 'Остановить диктовку'
                              : 'Голосовой ввод',
                          onPressed:
                              controller.sending || _session?.active == true
                                  ? null
                                  : _toggleVoice,
                          icon:
                              Icon(_voice.listening ? Icons.stop : Icons.mic_none),
                        ),
                        IconButton(
                          tooltip: _session?.active == true
                              ? 'Завершить голосовой разговор'
                              : 'Голосовой разговор',
                          onPressed: controller.sending
                              ? null
                              : () => _toggleConversation(controller),
                          icon: Icon(
                            _session?.active == true
                                ? Icons.headset_off
                                : Icons.headset_mic_outlined,
                          ),
                        ),
                        IconButton.filled(
                          tooltip: controller.sending
                              ? 'Добавить сообщение в очередь'
                              : 'Отправить',
                          onPressed: () => _send(controller),
                          icon: const Icon(Icons.arrow_upward_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> _pickAttachments() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;
      final next = <WesiAiAttachment>[..._attachments];
      for (final file in result.files) {
        next.add(WesiAiAttachment.fromPlatformFile(file));
      }
      WesiAiAttachment.validateBatch(next);
      if (!mounted) return;
      setState(() {
        _attachments
          ..clear()
          ..addAll(next);
      });
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть выбранный файл')),
        );
      }
    }
  }

  Future<void> _capturePhoto() async {
    try {
      final attachment = await Navigator.of(context).push<WesiAiAttachment>(
        MaterialPageRoute(builder: (_) => const WesiAiCameraCaptureScreen()),
      );
      if (attachment == null || !mounted) return;
      final next = <WesiAiAttachment>[..._attachments, attachment];
      WesiAiAttachment.validateBatch(next);
      setState(() {
        _attachments
          ..clear()
          ..addAll(next);
      });
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  Future<void> _send(WesiAiManagedChatController controller) async {
    if (_voice.listening) await _voice.stop();
    final text = _composer.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    final attachments = List<WesiAiAttachment>.from(_attachments);
    final result = controller.submitUserMessage(
      text,
      attachments: attachments,
    );
    if (result != WesiAiMessageSubmitResult.accepted) {
      if (!mounted) return;
      final message = switch (result) {
        WesiAiMessageSubmitResult.queueFull =>
          'Очередь заполнена. Дождитесь обработки сообщения.',
        WesiAiMessageSubmitResult.invalidAttachments =>
          'Не удалось отправить сообщение: проверьте вложения.',
        WesiAiMessageSubmitResult.unavailable =>
          'Не удалось отправить сообщение в текущий чат.',
        WesiAiMessageSubmitResult.accepted => '',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }
    _composer.clear();
    _voicePrefix = '';
    _voice.clearTranscript();
    setState(() => _attachments.clear());
  }

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
    )..addListener(_refresh);
    await session.start();
    if (!mounted) return;
    if (!session.active && session.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(session.error!)),
      );
    }
    setState(() {});
  }

  Future<List<WesiAiSpokenReply>> _speakableTurn(
    WesiAiChatController controller,
    String text,
  ) async {
    final conversationId = controller.state.activeConversation?.id;
    if (conversationId == null) return const [];
    final before =
        controller.state.messagesFor(conversationId).map((m) => m.id).toSet();
    await controller.addUserMessage(text);
    return spokenRepliesFrom(
      messages: controller.state.messagesFor(conversationId),
      alreadySeen: before,
    );
  }

  Widget _conversationStatus(WesiAiVoiceSession session) {
    final label = switch (session.phase) {
      WesiAiVoicePhase.listening => 'Слушаю…',
      WesiAiVoicePhase.thinking => 'Думаю…',
      WesiAiVoicePhase.speaking => 'Говорит Wesi AI',
      WesiAiVoicePhase.off => 'Разговор завершён',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(
        children: [
          const Icon(Icons.graphic_eq, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              session.heard.trim().isNotEmpty ? session.heard : label,
            ),
          ),
          if (session.phase == WesiAiVoicePhase.speaking ||
              session.phase == WesiAiVoicePhase.thinking)
            TextButton(
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
                _voice.transcript.isEmpty
                    ? 'Слушаю… говорите'
                    : _voice.transcript,
              ),
            ),
          ],
        ),
      );

  Future<void> _createProject(WesiAiManagedChatController controller) async {
    final title = TextEditingController();
    final description = TextEditingController();
    final instructions = TextEditingController();
    final result = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Новый проект Wesi AI'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    autofocus: true,
                    maxLength: 120,
                    decoration: const InputDecoration(labelText: 'Название'),
                  ),
                  TextField(
                    controller: description,
                    maxLength: 2000,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Описание'),
                  ),
                  TextField(
                    controller: instructions,
                    maxLength: 8000,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Инструкции для работы в проекте',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Создать'),
              ),
            ],
          ),
        ) ??
        false;
    if (result) {
      await controller.createProject(
        title.text,
        description: description.text,
        instructions: instructions.text,
      );
    }
    title.dispose();
    description.dispose();
    instructions.dispose();
  }

  Future<void> _projectAction(
    WesiAiManagedChatController controller,
    WesiAiProject project,
    String action,
  ) async {
    if (action == 'pin') {
      await controller.toggleProjectPinned(project.id);
    } else if (action == 'rename') {
      final value =
          await _textDialog('Переименовать проект', project.title, 120);
      if (value != null) await controller.renameProject(project.id, value);
    } else if (action == 'context') {
      await _editProjectContext(controller, project);
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Удалить проект?'),
              content: const Text(
                'Чаты не удалятся. Они будут перенесены в «Без проекта».',
              ),
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
      if (confirmed) await controller.deleteProject(project.id);
    }
  }

  Future<void> _editProjectContext(
    WesiAiManagedChatController controller,
    WesiAiProject project,
  ) async {
    final description = TextEditingController(text: project.description);
    final instructions = TextEditingController(text: project.instructions);
    final saved = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(project.title),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: description,
                    maxLength: 2000,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Описание проекта',
                    ),
                  ),
                  TextField(
                    controller: instructions,
                    maxLength: 8000,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText: 'Инструкции Wesi AI',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Сохранить'),
              ),
            ],
          ),
        ) ??
        false;
    if (saved) {
      await controller.updateProjectContext(
        project.id,
        description: description.text,
        instructions: instructions.text,
      );
    }
    description.dispose();
    instructions.dispose();
  }

  Future<void> _conversationAction(
    WesiAiManagedChatController controller,
    WesiAiConversation conversation,
    String action,
  ) async {
    if (action == 'pin') {
      await controller.togglePinned(conversation.id);
    } else if (action == 'rename') {
      final value =
          await _textDialog('Переименовать чат', conversation.title, 120);
      if (value != null) {
        await controller.renameConversation(conversation.id, value);
      }
    } else if (action == 'move') {
      await _moveConversation(controller, conversation);
    } else if (action == 'archive') {
      await controller.archiveConversation(conversation.id);
    } else if (action == 'delete' &&
        await _confirmDelete(conversation.title)) {
      await controller.deleteConversation(conversation.id);
    }
  }

  Future<void> _moveConversation(
    WesiAiManagedChatController controller,
    WesiAiConversation conversation,
  ) async {
    final destination = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Переместить чат'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, '__none__'),
            child: const ListTile(
              leading: Icon(Icons.chat_bubble_outline),
              title: Text('Без проекта'),
            ),
          ),
          for (final project in controller.visibleProjects)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, project.id),
              child: ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(project.title),
              ),
            ),
        ],
      ),
    );
    if (destination == null) return;
    final projectId = destination == '__none__' ? null : destination;
    await controller.moveConversationToProject(conversation.id, projectId);
    await controller.selectProject(projectId);
    await controller.selectConversation(conversation.id);
  }

  Future<void> _archivedAction(
    WesiAiManagedChatController controller,
    WesiAiConversation conversation,
    String action,
  ) async {
    if (action == 'restore') {
      await controller.restoreConversation(conversation.id);
    } else if (action == 'delete' &&
        await _confirmDelete(conversation.title)) {
      await controller.deleteConversation(conversation.id);
    }
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
            content: const Text(
              'Будет создан отдельный чат с переданным текстовым контекстом.',
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

  Future<String?> _textDialog(
    String title,
    String initial,
    int maxLength,
  ) async {
    final editor = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: editor,
          autofocus: true,
          maxLength: maxLength,
          onSubmitted: (text) => Navigator.pop(dialogContext, text),
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
    return value;
  }

  Future<bool> _confirmDelete(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Удалить чат?'),
          content: Text(
            'Локальная история «$title» будет удалена с этого устройства.',
          ),
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

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
    return '$bytes Б';
  }

  String _personaName(WesiAiPersona persona) => switch (persona) {
        WesiAiPersona.zane => 'Зейн',
        WesiAiPersona.nirvana => 'Нирвана',
        WesiAiPersona.lobby => 'Лобби',
      };

  IconData _personaIcon(WesiAiPersona persona) => switch (persona) {
        WesiAiPersona.zane => Icons.bolt_rounded,
        WesiAiPersona.nirvana => Icons.spa_outlined,
        WesiAiPersona.lobby => Icons.groups_2_outlined,
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
        title: Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
            const PopupMenuItem(
              value: 'move',
              child: Text('Переместить в проект'),
            ),
            const PopupMenuItem(
              value: 'archive',
              child: Text('В архив'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Удалить')),
          ],
        ),
      );
}
