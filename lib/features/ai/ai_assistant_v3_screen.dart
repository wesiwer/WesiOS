import 'dart:async';

import 'package:flutter/material.dart';

import '../team/services/team_service.dart';
import 'models/wesi_ai_chat_models.dart';
import 'models/wesi_ai_limits.dart';
import 'storage/wesi_ai_local_store.dart';
import 'wesi_ai_api.dart';
import 'wesi_ai_handoff_controller.dart';
import 'wesi_ai_voice_controller.dart';
import 'wesi_ai_voice_devices.dart';
import 'wesi_ai_voice_session.dart';
import 'widgets/wesi_ai_message_content.dart';

enum WesiAiUiMode { classic, thinking }

class AiAssistantV3Screen extends StatefulWidget {
  const AiAssistantV3Screen({super.key});

  @override
  State<AiAssistantV3Screen> createState() => _AiAssistantV3ScreenState();
}

class _AiAssistantV3ScreenState extends State<AiAssistantV3Screen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  final _voice = WesiAiVoiceController();

  WesiAiHandoffController? _controller;
  WesiAiVoiceSession? _voiceSession;
  WesiAiUiMode _mode = WesiAiUiMode.classic;
  DateTime? _thinkingSince;
  Timer? _ticker;
  bool _creatingInitial = false;

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
      if (controller.state.activeConversation == null && !_creatingInitial) {
        _creatingInitial = true;
        unawaited(
          controller.createConversation(WesiAiPersona.zane).whenComplete(() {
            _creatingInitial = false;
          }),
        );
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
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
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
    return Scaffold(
      key: _scaffoldKey,
      drawer: _drawer(controller),
      body: SafeArea(
        child: Column(
          children: [
            _topBar(controller, active),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: messages.isEmpty
                    ? _emptyState(active.persona)
                    : _conversation(controller, messages),
              ),
            ),
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
          _chip(
            icon: Icons.auto_awesome_rounded,
            label: _personaName(active.persona),
            onTap: () => _showPersonaPicker(controller, active.persona),
          ),
          const Spacer(),
          _chip(
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

  Widget _emptyState(WesiAiPersona persona) {
    final firstName = _firstName(TeamService.current?.fullName ?? '');
    final text = switch (persona) {
      WesiAiPersona.zane => 'Зейн ждёт твоё сообщение',
      WesiAiPersona.nirvana =>
        'Нирвана готова разделить с тобой этот приятный момент',
      WesiAiPersona.lobby => firstName.isEmpty
          ? 'Зейн и Нирвана готовы помочь тебе'
          : '$firstName, Зейн и Нирвана готовы помочь тебе',
    };
    return Center(
      key: const ValueKey('wesi-ai-empty'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/app_icon.png', width: 76, height: 76),
            const SizedBox(height: 22),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    height: 1.22,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _conversation(
    WesiAiHandoffController controller,
    List<WesiAiMessage> messages,
  ) {
    return ListView.builder(
      key: const ValueKey('wesi-ai-active'),
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      itemCount: messages.length + (controller.sending ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) return _liveThinking();
        final message = messages[index];
        return _message(message, index == messages.length - 1);
      },
    );
  }

  Widget _message(WesiAiMessage message, bool latest) {
    final mine = message.author == WesiAiMessageAuthor.user;
    final blocks = _blocks(message);
    final tools = blocks.where((block) {
      final type = '${block['type'] ?? ''}'.toLowerCase();
      return type == 'tool' || type == 'action' || type == 'status';
    }).toList(growable: false);
    final reasoning = _reasoningSummary(message, blocks);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!mine && _mode == WesiAiUiMode.thinking && reasoning != null)
              _reasoningCard(reasoning),
            for (final tool in tools) _toolEvent(tool),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: mine ? 14 : 2,
                vertical: mine ? 10 : 4,
              ),
              decoration: mine
                  ? BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
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
    final seconds = _thinkingSince == null
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
                ? 'Обдумывает · ${seconds}с'
                : 'Формирует ответ · ${seconds}с',
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
        children: const [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Показывается безопасное резюме решения и использованных данных. '
              'Скрытая внутренняя цепочка рассуждений не раскрывается.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolEvent(Map<String, dynamic> block) {
    final raw = block['data'];
    final data = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
    final label =
        '${data['label'] ?? data['tool'] ?? data['name'] ?? 'Инструмент WesiOS'}';
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
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: [
          for (final text in suggestions)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                _composer.text = text;
                _composer.selection =
                    TextSelection.collapsed(offset: text.length);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.subdirectory_arrow_right_rounded, size: 18),
                    const SizedBox(width: 9),
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
    final voiceActive = _voiceSession?.active == true;
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
                decoration: const InputDecoration(
                  hintText: 'Спроси Wesi AI о чём угодно',
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Вложить файл',
                    onPressed: controller.sending ? null : () {},
                    icon: const Icon(Icons.add_rounded),
                  ),
                  _chip(
                    icon: _tierIcon(controller.state.tier),
                    label: _tierName(controller.state.tier),
                    compact: true,
                    onTap: () => _showTierPicker(controller),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: voiceActive
                        ? 'Остановить разговор'
                        : 'Голосовой разговор',
                    onPressed: controller.sending
                        ? null
                        : () => _toggleConversation(controller),
                    icon: Icon(
                      voiceActive
                          ? Icons.stop_circle_outlined
                          : Icons.mic_none_rounded,
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Отправить',
                    onPressed:
                        controller.sending ? null : () => _send(controller),
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
              child: Text(
                'Wesi AI',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
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
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.data_usage_rounded),
              title: const Text('Лимиты моделей'),
              subtitle: const Text('Остаток квот и время сброса'),
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
                  return ListTile(
                    selected: chat.id == controller.state.activeConversationId,
                    leading: Icon(_personaIcon(chat.persona)),
                    title: Text(
                      chat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(_personaName(chat.persona)),
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

  Future<void> _send(WesiAiHandoffController controller) async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    await controller.addUserMessage(text);
  }

  Future<void> _toggleConversation(WesiAiHandoffController controller) async {
    final current = _voiceSession;
    if (current != null && current.active) {
      await current.stop();
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
    WesiAiHandoffController controller,
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
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final persona in WesiAiPersona.values)
              ListTile(
                leading: Icon(_personaIcon(persona)),
                title: Text(_personaName(persona)),
                trailing:
                    persona == current ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(sheetContext, persona),
              ),
          ],
        ),
      ),
    );
    if (next != null && next != current) {
      await controller.createConversation(next);
    }
  }

  Future<void> _showModePicker() async {
    final next = await showModalBottomSheet<WesiAiUiMode>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded),
              title: const Text('Классический'),
              onTap: () =>
                  Navigator.pop(sheetContext, WesiAiUiMode.classic),
            ),
            ListTile(
              leading: const Icon(Icons.psychology_alt_rounded),
              title: const Text('Думающий'),
              subtitle: const Text('Показывает безопасный ход решения'),
              onTap: () =>
                  Navigator.pop(sheetContext, WesiAiUiMode.thinking),
            ),
          ],
        ),
      ),
    );
    if (next != null && mounted) setState(() => _mode = next);
  }

  Future<void> _showTierPicker(WesiAiHandoffController controller) async {
    final next = await showModalBottomSheet<WesiAiTier>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tier in WesiAiTier.values)
              ListTile(
                leading: Icon(_tierIcon(tier)),
                title: Text(_tierName(tier)),
                subtitle: Text(_tierDescription(tier)),
                trailing: tier == controller.state.tier
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(sheetContext, tier),
              ),
          ],
        ),
      ),
    );
    if (next != null) await controller.setTier(next);
  }

  Future<void> _showLimits() async {
    WesiAiLimits? limits;
    Object? error;
    try {
      limits = await const WesiAiApi().limits();
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Лимиты Wesi AI',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              if (error != null)
                const Text('Не удалось получить актуальные лимиты.')
              else ...[
                _limitRow('Быстрый', limits?['fast']),
                _limitRow('Pro', limits?['pro']),
                _limitRow('Максимальный', limits?['maximum']),
                const Padding(
                  padding: EdgeInsets.only(top: 12, bottom: 6),
                  child: Text(
                    'Ультра',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                _limitRow('Низкий · Grok', limits?['ultraLow']),
                _limitRow('Средний · ChatGPT', limits?['ultraMedium']),
                _limitRow('Высокий · Claude', limits?['ultraHigh']),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _limitRow(String label, WesiAiLimitSnapshot? limit) {
    final percent = limit?.remainingPercent;
    final fraction = limit?.remainingFraction;
    final reset = limit?.resetAt;
    final resetText = reset == null
        ? 'время сброса неизвестно'
        : 'сброс ${reset.day.toString().padLeft(2, '0')}.${reset.month.toString().padLeft(2, '0')} '
            '${reset.hour.toString().padLeft(2, '0')}:${reset.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(percent == null ? '—' : '${percent.round()}% / 100%'),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: fraction),
          const SizedBox(height: 4),
          Text(resetText, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 13,
          vertical: compact ? 7 : 9,
        ),
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
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  String? _reasoningSummary(
    WesiAiMessage message,
    List<Map<String, dynamic>> blocks,
  ) {
    final direct = '${message.metadata['reasoningSummary'] ?? ''}'.trim();
    if (direct.isNotEmpty) return direct;
    final toolCount = blocks.where((block) {
      final type = '${block['type'] ?? ''}'.toLowerCase();
      return type == 'tool' || type == 'action';
    }).length;
    if (toolCount > 0) {
      return 'Проверил контекст и использовал инструментов: $toolCount';
    }
    return 'Сопоставил запрос с контекстом диалога и подготовил ответ';
  }

  List<String> _followUps(String answer) {
    final lower = answer.toLowerCase();
    if (lower.contains('сервер') || lower.contains('ssh')) {
      return const [
        'Проверь состояние сервера',
        'Что настроить следующим?',
        'Покажи риски этой настройки',
      ];
    }
    return const [
      'Расскажи подробнее',
      'Что здесь самое важное?',
      'Предложи следующий шаг',
    ];
  }

  String _firstName(String fullName) {
    final clean = fullName.trim().replaceAll(RegExp(r'\s+'), ' ');
    return clean.isEmpty ? '' : clean.split(' ').first;
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

  String _tierName(WesiAiTier tier) => switch (tier) {
        WesiAiTier.fast => 'Быстрый',
        WesiAiTier.pro => 'Pro',
        WesiAiTier.maximum => 'Максимальный',
        WesiAiTier.ultra => 'Ультра',
      };

  IconData _tierIcon(WesiAiTier tier) => switch (tier) {
        WesiAiTier.fast => Icons.bolt_rounded,
        WesiAiTier.pro => Icons.auto_awesome_rounded,
        WesiAiTier.maximum => Icons.workspace_premium_rounded,
        WesiAiTier.ultra => Icons.diamond_outlined,
      };

  String _tierDescription(WesiAiTier tier) => switch (tier) {
        WesiAiTier.fast => 'Минимальная задержка для повседневных задач',
        WesiAiTier.pro => 'Баланс качества, скорости и инструментов',
        WesiAiTier.maximum => 'Максимум доступного качества Gemini',
        WesiAiTier.ultra => 'Автовыбор Grok / ChatGPT / Claude с fallback',
      };
}
