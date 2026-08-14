import 'dart:async';

import 'package:flutter/material.dart';

import '../team/services/team_service.dart';
import 'controllers/wesi_ai_chat_controller.dart';
import 'models/wesi_ai_chat_models.dart';
import 'storage/wesi_ai_local_store.dart';
import 'wesi_ai_handoff_controller.dart';
import 'wesi_ai_voice_controller.dart';
import 'wesi_ai_voice_devices.dart';
import 'wesi_ai_voice_session.dart';
import 'widgets/wesi_ai_message_content.dart';

enum WesiAiUiMode { classic, thinking }
enum WesiAiUiTier { fast, pro, maximum, ultra }

class AiAssistantV3Screen extends StatefulWidget {
  const AiAssistantV3Screen({super.key});

  @override
  State<AiAssistantV3Screen> createState() => _AiAssistantV3ScreenState();
}

class _AiAssistantV3ScreenState extends State<AiAssistantV3Screen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  final WesiAiVoiceController _voice = WesiAiVoiceController();
  WesiAiHandoffController? _controller;
  WesiAiVoiceSession? _voiceSession;
  WesiAiUiMode _mode = WesiAiUiMode.classic;
  WesiAiUiTier _uiTier = WesiAiUiTier.fast;
  bool _creatingInitial = false;
  DateTime? _thinkingSince;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
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
      _uiTier = switch (controller.state.tier) {
        WesiAiTier.fast => WesiAiUiTier.fast,
        WesiAiTier.pro => WesiAiUiTier.pro,
        WesiAiTier.maximum => _uiTier == WesiAiUiTier.ultra
            ? WesiAiUiTier.ultra
            : WesiAiUiTier.maximum,
      };
      if (controller.state.activeConversation == null && !_creatingInitial) {
        _creatingInitial = true;
        unawaited(controller.createConversation(WesiAiPersona.zane).whenComplete(() {
          _creatingInitial = false;
        }));
      }
      if (controller.sending && _thinkingSince == null) {
        _thinkingSince = DateTime.now();
        _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      } else if (!controller.sending && _thinkingSince != null) {
        _thinkingSince = null;
        _ticker?.cancel();
        _ticker = null;
      }
    }
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller?.removeListener(_refresh);
    _controller?.dispose();
    _voiceSession?.stop();
    _voiceSession?.dispose();
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
        body: Center(child: Text('Войдите в профиль, чтобы открыть Wesi AI')),
      );
    }
    if (controller.loading || controller.state.activeConversation == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final active = controller.state.activeConversation!;
    final messages = controller.state.messagesFor(active.id);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: scheme.surface,
      drawer: _drawer(controller),
      body: SafeArea(
        child: Column(
          children: [
            _topBar(controller, active),
            Expanded(child: _conversation(controller, active, messages)),
            _composerBar(controller),
          ],
        ),
      ),
    );
  }

  Widget _topBar(
    WesiAiHandoffController controller,
    WesiAiConversation active,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: 'Чаты Wesi AI',
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            icon: const Icon(Icons.menu_rounded),
          ),
          const SizedBox(width: 10),
          _selectorChip(
            icon: Icons.auto_awesome_rounded,
            label: _personaName(active.persona),
            onTap: () => _showPersonaPicker(controller, active.persona),
          ),
          const Spacer(),
          _selectorChip(
            icon: _mode == WesiAiUiMode.thinking
                ? Icons.psychology_alt_rounded
                : Icons.chat_bubble_outline_rounded,
            label: _mode == WesiAiUiMode.thinking ? 'Думающий' : 'Классический',
            onTap: _showModePicker,
          ),
        ],
      ),
    );
  }

  Widget _conversation(
    WesiAiHandoffController controller,
    WesiAiConversation active,
    List<WesiAiMessage> messages,
  ) {
    if (messages.isEmpty) {
      return _emptyState(active.persona);
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      itemCount: messages.length + (controller.sending ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) return _liveThinking();
        final message = messages[index];
        final latest = index == messages.length - 1;
        return _message(message, latest);
      },
    );
  }

  Widget _emptyState(WesiAiPersona persona) {
    final theme = Theme.of(context);
    final employee = TeamService.current;
    final firstName = _firstName(employee?.fullName ?? '');
    final text = switch (persona) {
      WesiAiPersona.zane => 'Зейн ждёт твоё сообщение',
      WesiAiPersona.nirvana =>
        'Нирвана готова разделить с тобой этот приятный момент',
      WesiAiPersona.lobby => firstName.isEmpty
          ? 'Зейн и Нирвана готовы помочь тебе'
          : '$firstName, Зейн и Нирвана готовы помочь. С чего начнём?',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 90),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: .92,
              child: Image.asset(
                'assets/images/app_icon.png',
                width: 78,
                height: 78,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w500,
                height: 1.22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(WesiAiMessage message, bool latest) {
    final mine = message.author == WesiAiMessageAuthor.user;
    final theme = Theme.of(context);
    final blocks = _blocks(message);
    final toolBlocks = blocks.where((b) {
      final type = '${b['type'] ?? ''}'.toLowerCase();
      return type == 'tool' || type == 'action' || type == 'status';
    }).toList(growable: false);
    final reasoning = _reasoningSummary(message, blocks);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!mine && _mode == WesiAiUiMode.thinking && reasoning != null)
              _reasoningCard(reasoning),
            for (final block in toolBlocks) _toolEvent(block),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: mine ? 14 : 2,
                vertical: mine ? 10 : 4,
              ),
              decoration: mine
                  ? BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(22),
                    )
                  : null,
              child: WesiAiMessageContent(
                key: ValueKey(message.id),
                message: message,
                animateText: latest && !mine,
              ),
            ),
            if (!mine && latest && message.kind == WesiAiMessageKind.text)
              _suggestions(message.text),
          ],
        ),
      ),
    );
  }

  Widget _liveThinking() {
    final elapsed = _thinkingSince == null
        ? 0
        : DateTime.now().difference(_thinkingSince!).inSeconds;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            _mode == WesiAiUiMode.thinking
                ? 'Обдумывает · ${elapsed}с'
                : 'Формирует ответ · ${elapsed}с',
          ),
        ],
      ),
    );
  }

  Widget _reasoningCard(String summary) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.fromLTRB(0, 0, 12, 12),
        leading: const Icon(Icons.psychology_alt_outlined),
        title: const Text('Обдумывание завершено'),
        subtitle: Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Здесь показывается безопасное резюме хода решения: какие данные были учтены, какие инструменты использованы и к какому выводу пришёл Wesi AI. Скрытая внутренняя цепочка рассуждений не раскрывается.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolEvent(Map<String, dynamic> block) {
    final data = block['data'];
    final map = data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};
    final label = '${map['label'] ?? map['tool'] ?? map['name'] ?? 'Инструмент WesiOS'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.extension_outlined, size: 18),
          const SizedBox(width: 8),
          Flexible(child: Text('Использован $label')),
        ],
      ),
    );
  }

  Widget _suggestions(String answer) {
    final suggestions = _followUps(answer);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final text in suggestions)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                _composer.text = text;
                _composer.selection = TextSelection.collapsed(offset: text.length);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    const Icon(Icons.subdirectory_arrow_right_rounded, size: 19),
                    const SizedBox(width: 10),
                    Expanded(child: Text(text)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _composerBar(WesiAiHandoffController controller) {
    final activeVoice = _voiceSession?.active == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 8, 8),
          child: Column(
            children: [
              TextField(
                controller: _composer,
                minLines: 1,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Спроси Wesi AI о чём угодно',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Вложить файл',
                    onPressed: controller.sending ? null : () => _comingSoon('Вложения'),
                    icon: const Icon(Icons.add_rounded),
                  ),
                  _selectorChip(
                    icon: _tierIcon(_uiTier),
                    label: _tierName(_uiTier),
                    onTap: () => _showTierPicker(controller),
                    compact: true,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: activeVoice ? 'Остановить разговор' : 'Голосовой разговор',
                    onPressed: controller.sending ? null : () => _toggleConversation(controller),
                    icon: Icon(activeVoice ? Icons.stop_circle_outlined : Icons.mic_none_rounded),
                  ),
                  IconButton.filled(
                    tooltip: 'Отправить',
                    onPressed: controller.sending ? null : () => _send(controller),
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Drawer _drawer(WesiAiHandoffController controller) {
    final chats = controller.visibleConversations;
    return Drawer(
      width: 330,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Text('Wesi AI', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: FilledButton.icon(
                onPressed: controller.sending
                    ? null
                    : () async {
                        await controller.createConversation(WesiAiPersona.zane);
                        if (mounted) Navigator.of(context).pop();
                      },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Новый чат'),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.data_usage_rounded),
              title: const Text('Лимиты моделей'),
              subtitle: const Text('Использование и доступные квоты'),
              onTap: () {
                Navigator.of(context).pop();
                _showLimits();
              },
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: chats.length,
                itemBuilder: (context, index) {
                  final chat = chats[index];
                  final selected = chat.id == controller.state.activeConversationId;
                  return ListTile(
                    selected: selected,
                    leading: Icon(_personaIcon(chat.persona)),
                    title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_personaName(chat.persona)),
                    trailing: chat.pinned ? const Icon(Icons.push_pin_rounded, size: 16) : null,
                    onTap: () async {
                      await controller.selectConversation(chat.id);
                      if (mounted) Navigator.of(context).pop();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send(WesiAiChatController controller) async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    await controller.addUserMessage(text);
  }

  Future<void> _toggleConversation(WesiAiChatController controller) async {
    final existing = _voiceSession;
    if (existing != null && existing.active) {
      await existing.stop();
      if (mounted) setState(() {});
      return;
    }
    final session = _voiceSession ??= WesiAiVoiceSession(
      ear: WesiAiDeviceEar(_voice),
      mouth: const WesiAiDeviceMouth(),
      onTurn: (text) => _voiceTurn(controller, text),
    )..addListener(_refresh);
    await session.start();
    if (mounted) setState(() {});
  }

  Future<List<WesiAiSpokenReply>> _voiceTurn(
    WesiAiChatController controller,
    String text,
  ) async {
    final id = controller.state.activeConversation?.id;
    if (id == null) return const [];
    final before = controller.state.messagesFor(id).map((m) => m.id).toSet();
    await controller.addUserMessage(text);
    return spokenRepliesFrom(
      messages: controller.state.messagesFor(id),
      alreadySeen: before,
    );
  }

  Future<void> _showPersonaPicker(
    WesiAiHandoffController controller,
    WesiAiPersona current,
  ) async {
    final next = await showModalBottomSheet<WesiAiPersona>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final persona in WesiAiPersona.values)
              ListTile(
                leading: Icon(_personaIcon(persona)),
                title: Text(_personaName(persona)),
                trailing: persona == current ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(context, persona),
              ),
          ],
        ),
      ),
    );
    if (next == null || next == current) return;
    await controller.createConversation(next);
  }

  Future<void> _showModePicker() async {
    final next = await showModalBottomSheet<WesiAiUiMode>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded),
              title: const Text('Классический'),
              subtitle: const Text('Сразу показывает ответ и действия'),
              onTap: () => Navigator.pop(context, WesiAiUiMode.classic),
            ),
            ListTile(
              leading: const Icon(Icons.psychology_alt_rounded),
              title: const Text('Думающий'),
              subtitle: const Text('Показывает безопасный ход решения и инструменты'),
              onTap: () => Navigator.pop(context, WesiAiUiMode.thinking),
            ),
          ],
        ),
      ),
    );
    if (next != null) setState(() => _mode = next);
  }

  Future<void> _showTierPicker(WesiAiChatController controller) async {
    final next = await showModalBottomSheet<WesiAiUiTier>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tier in WesiAiUiTier.values)
              ListTile(
                leading: Icon(_tierIcon(tier)),
                title: Text(_tierName(tier)),
                subtitle: Text(_tierDescription(tier)),
                trailing: tier == _uiTier ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(context, tier),
              ),
          ],
        ),
      ),
    );
    if (next == null) return;
    if (next == WesiAiUiTier.ultra) {
      setState(() => _uiTier = next);
      _comingSoon('Ультра будет маршрутизироваться в отдельную максимальную модель Claude / ChatGPT / Grok после подключения provider API');
      return;
    }
    setState(() => _uiTier = next);
    await controller.setTier(switch (next) {
      WesiAiUiTier.fast => WesiAiTier.fast,
      WesiAiUiTier.pro => WesiAiTier.pro,
      WesiAiUiTier.maximum => WesiAiTier.maximum,
      WesiAiUiTier.ultra => WesiAiTier.maximum,
    });
  }

  void _showLimits() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Лимиты Wesi AI', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              SizedBox(height: 12),
              Text('Здесь будет отображаться фактическое потребление запросов, медиа и голоса по каждому подключённому провайдеру. Экран уже является точкой входа для серверного quota API.'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectorChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 13, vertical: compact ? 7 : 9),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 7),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 3),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _blocks(WesiAiMessage message) {
    final raw = message.metadata['blocks'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  String? _reasoningSummary(WesiAiMessage message, List<Map<String, dynamic>> blocks) {
    final direct = '${message.metadata['reasoningSummary'] ?? ''}'.trim();
    if (direct.isNotEmpty) return direct;
    final tools = blocks.where((b) {
      final type = '${b['type'] ?? ''}'.toLowerCase();
      return type == 'tool' || type == 'action';
    }).length;
    if (tools > 0) return 'Проверил данные и использовал инструментов: $tools';
    return 'Сопоставил запрос с контекстом диалога и подготовил ответ';
  }

  List<String> _followUps(String answer) {
    final lower = answer.toLowerCase();
    if (lower.contains('github') || lower.contains('репозитор')) {
      return const ['Покажи последние изменения', 'Проверь проблемы в репозитории', 'Что делать дальше?'];
    }
    if (lower.contains('сервер') || lower.contains('ssh')) {
      return const ['Проверь состояние сервера', 'Что настроить следующим?', 'Покажи риски этой настройки'];
    }
    return const ['Расскажи подробнее', 'Что здесь самое важное?', 'Предложи следующий шаг'];
  }

  String _firstName(String fullName) {
    final clean = fullName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) return '';
    return clean.split(' ').first;
  }

  String _personaName(WesiAiPersona persona) => switch (persona) {
        WesiAiPersona.zane => 'Зейн',
        WesiAiPersona.nirvana => 'Нирвана',
        WesiAiPersona.lobby => 'Лобби',
      };

  IconData _personaIcon(WesiAiPersona persona) => switch (persona) {
        WesiAiPersona.zane => Icons.bolt_rounded,
        WesiAiPersona.nirvana => Icons.spa_rounded,
        WesiAiPersona.lobby => Icons.groups_2_outlined,
      };

  String _tierName(WesiAiUiTier tier) => switch (tier) {
        WesiAiUiTier.fast => 'Быстрый',
        WesiAiUiTier.pro => 'Pro',
        WesiAiUiTier.maximum => 'Максимальный',
        WesiAiUiTier.ultra => 'Ультра',
      };

  IconData _tierIcon(WesiAiUiTier tier) => switch (tier) {
        WesiAiUiTier.fast => Icons.bolt_rounded,
        WesiAiUiTier.pro => Icons.auto_awesome_rounded,
        WesiAiUiTier.maximum => Icons.workspace_premium_rounded,
        WesiAiUiTier.ultra => Icons.diamond_outlined,
      };

  String _tierDescription(WesiAiUiTier tier) => switch (tier) {
        WesiAiUiTier.fast => 'Минимальная задержка для повседневных задач',
        WesiAiUiTier.pro => 'Баланс качества, скорости и инструментов',
        WesiAiUiTier.maximum => 'Максимум доступного качества Gemini',
        WesiAiUiTier.ultra => 'Отдельная флагманская модель · подключение провайдера',
      };

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(feature)));
  }
}
