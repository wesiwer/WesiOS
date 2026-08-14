import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../models/wesi_ai_chat_models.dart';
import '../storage/wesi_ai_local_store.dart';
import '../wesi_ai_api.dart';
import '../wesi_ai_session_policy.dart';

class WesiAiChatController extends ChangeNotifier with WidgetsBindingObserver {
  // Model-aware pruning now happens on Relay. Local compaction is only an
  // archival safety net for extremely long conversations.
  static const int _minUncompactedMessages = 900;
  static const int _recentMessagesToKeep = 320;
  static const int _maxCompactionBatch = 480;
  static const int _minUncompactedChars = 3500000;

  final WesiAiLocalStore store;
  final WesiAiApi api;
  final Set<String> _mediaPolls = <String>{};
  bool _disposed = false;

  WesiAiLocalState state;
  bool loading = true;
  bool sending = false;

  WesiAiChatController({required this.store, this.api = const WesiAiApi()})
      : state = WesiAiLocalState.empty(store.employeeId) {
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> load() async {
    state = await store.load();
    state = state.copyWith(emotions: state.emotions.decayed());
    final fresh = WesiAiSessionPolicy.shouldStartFresh();
    WesiAiSessionPolicy.markModuleOpened();
    if (fresh) {
      await _createConversationWithoutNotify(_freshPersona());
    }
    loading = false;
    notifyListeners();
    for (final message in state.messages) {
      _startPendingMedia(message);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      WesiAiSessionPolicy.markAppBackgrounded();
    }
  }

  WesiAiPersona _freshPersona() {
    final active = state.activeConversation;
    if (active != null && !active.archived) return active.persona;
    return WesiAiPersona.zane;
  }

  Future<void> setTier(WesiAiTier tier) async {
    state = state.copyWith(tier: tier);
    await _persist();
  }

  Future<void> createConversation(WesiAiPersona persona) async {
    await _createConversationWithoutNotify(persona);
    await _persist();
  }

  Future<void> _createConversationWithoutNotify(WesiAiPersona persona) async {
    final now = DateTime.now();
    final id = '${now.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
    final title = switch (persona) {
      WesiAiPersona.zane => 'Новый чат с Зейном',
      WesiAiPersona.nirvana => 'Новый чат с Нирваной',
      WesiAiPersona.lobby => 'Новое лобби'
    };
    final c = WesiAiConversation(
      id: id,
      employeeId: store.employeeId,
      title: title,
      persona: persona,
      createdAt: now,
      updatedAt: now,
    );
    state = state.copyWith(
      conversations: <WesiAiConversation>[c, ...state.conversations],
      activeConversationId: id,
    );
  }

  Future<void> selectConversation(String id) async {
    if (!state.conversations.any(
      (c) => c.id == id && c.employeeId == store.employeeId,
    )) {
      return;
    }
    state = state.copyWith(
      activeConversationId: id,
      emotions: state.emotions.decayed(),
    );
    WesiAiSessionPolicy.markModuleOpened();
    await _persist();
  }

  List<WesiAiMessage> _transportable(List<WesiAiMessage> messages) => messages
      .where((m) =>
          m.kind == WesiAiMessageKind.text &&
          m.author != WesiAiMessageAuthor.system &&
          m.author != WesiAiMessageAuthor.tool)
      .toList(growable: false);

  Future<WesiAiConversation> _compactContextIfNeeded(
    WesiAiConversation conversation,
    List<WesiAiMessage> history,
  ) async {
    final transportable = _transportable(history);
    final already = conversation.contextCompactedMessageCount
        .clamp(0, transportable.length);
    final uncompacted = transportable.sublist(already);
    if (uncompacted.length <= _recentMessagesToKeep) return conversation;

    final chars = uncompacted.fold<int>(0, (sum, item) => sum + item.text.length);
    if (uncompacted.length < _minUncompactedMessages &&
        chars < _minUncompactedChars) {
      return conversation;
    }

    final availableToCompact = uncompacted.length - _recentMessagesToKeep;
    final batchSize = min(availableToCompact, _maxCompactionBatch);
    if (batchSize <= 0) return conversation;
    final batch = uncompacted.sublist(0, batchSize);

    try {
      final result = await api.compactContext(
        conversation: conversation,
        messages: batch,
        compactedCount: 0,
      );
      final updated = conversation.copyWith(
        contextSummary: result.summary,
        contextCompactedMessageCount:
            conversation.contextCompactedMessageCount + result.compactedCount,
      );
      final conversations = state.conversations
          .map((item) => item.id == updated.id ? updated : item)
          .toList(growable: false);
      final at = DateTime.now();
      final event = WesiAiMessage(
        id: '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
        conversationId: updated.id,
        employeeId: store.employeeId,
        author: WesiAiMessageAuthor.tool,
        kind: WesiAiMessageKind.status,
        text: 'Контекст оптимизирован',
        createdAt: at,
        metadata: <String, dynamic>{
          'blocks': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'tool',
              'data': <String, dynamic>{
                'label': 'Оптимизация контекста',
                'tool': 'context_optimizer',
                'compactedMessages': result.compactedCount,
                'recentMessagesKept': _recentMessagesToKeep,
              },
            },
          ],
        },
      );
      state = state.copyWith(
        conversations: conversations,
        messages: <WesiAiMessage>[...state.messages, event],
      );
      await _persist();
      return updated;
    } on WesiAiApiException {
      return conversation;
    }
  }

  Future<void> addUserMessage(String text) async {
    var c = state.activeConversation;
    final clean = text.trim();
    if (c == null || clean.isEmpty || sending) return;

    WesiAiSessionPolicy.markModuleOpened();
    var history = state.messagesFor(c.id);
    c = await _compactContextIfNeeded(c, history);
    history = state.messagesFor(c.id);

    final now = DateTime.now();
    final emotionalState = state.emotions.decayed(now);
    final user = WesiAiMessage(
      id: '${now.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
      conversationId: c.id,
      employeeId: store.employeeId,
      author: WesiAiMessageAuthor.user,
      text: clean,
      createdAt: now,
    );
    final updated = c.copyWith(updatedAt: now, title: _titleFor(c, clean));
    final conversations = state.conversations
        .map((x) => x.id == c!.id ? updated : x)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = state.copyWith(
      messages: <WesiAiMessage>[...state.messages, user],
      conversations: conversations,
      emotions: emotionalState,
    );
    sending = true;
    await _persist();

    try {
      final reply = await api.send(
        conversation: updated,
        tier: state.tier,
        message: clean,
        history: history,
        memory: state.memory,
        emotions: emotionalState,
      );
      final at = DateTime.now();
      final author = switch (c.persona) {
        WesiAiPersona.zane => WesiAiMessageAuthor.zane,
        WesiAiPersona.nirvana => WesiAiMessageAuthor.nirvana,
        WesiAiPersona.lobby => WesiAiMessageAuthor.zane
      };
      final assistant = WesiAiMessage(
        id: '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
        conversationId: c.id,
        employeeId: store.employeeId,
        author: author,
        text: reply.answer,
        createdAt: at,
        metadata: <String, dynamic>{
          'requestId': reply.requestId,
          if (reply.route.isNotEmpty) 'route': reply.route,
          if (reply.emotions != null) 'emotions': reply.emotions!.toJson(),
          if (reply.blocks.isNotEmpty)
            'blocks': reply.blocks
                .map((block) => block.toJson())
                .toList(growable: false),
        },
      );
      state = state.copyWith(
        messages: <WesiAiMessage>[...state.messages, assistant],
        emotions: reply.emotions ?? emotionalState,
      );
      _startPendingMedia(assistant);
    } on WesiAiApiException catch (e) {
      final at = DateTime.now();
      state = state.copyWith(
        messages: <WesiAiMessage>[
          ...state.messages,
          WesiAiMessage(
            id: '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
            conversationId: c.id,
            employeeId: store.employeeId,
            author: WesiAiMessageAuthor.system,
            kind: WesiAiMessageKind.error,
            text: e.message,
            createdAt: at,
            metadata: <String, dynamic>{'code': e.code},
          ),
        ],
      );
    } finally {
      sending = false;
      await _persist();
    }
  }

  void _startPendingMedia(WesiAiMessage message) {
    final rawBlocks = message.metadata['blocks'];
    if (rawBlocks is! List) return;
    for (final raw in rawBlocks) {
      if (raw is! Map) continue;
      final block = Map<String, dynamic>.from(raw);
      if ('${block['type'] ?? ''}' != 'media') continue;
      final rawData = block['data'];
      if (rawData is! Map) continue;
      final data = Map<String, dynamic>.from(rawData);
      if ('${data['status'] ?? ''}'.toLowerCase() != 'pending') continue;
      final statusUrl = '${data['url'] ?? ''}'.trim();
      final uri = Uri.tryParse(statusUrl);
      if (uri == null ||
          !uri.path.startsWith('/api/wesi/ai/media/jobs/')) {
        continue;
      }
      final key = '${message.id}|$statusUrl';
      if (!_mediaPolls.add(key)) continue;
      unawaited(_monitorMedia(message.id, statusUrl, key));
    }
  }

  Future<void> _monitorMedia(
    String messageId,
    String statusUrl,
    String key,
  ) async {
    try {
      for (var attempt = 0; attempt < 120 && !_disposed; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(seconds: 5));
        }
        if (_disposed || !_messageStillHasStatusUrl(messageId, statusUrl)) {
          return;
        }
        final block = await api.mediaJob(statusUrl);
        if (block == null) continue;
        final status = '${block.data['status'] ?? ''}'.toLowerCase();
        if (status != 'ready' && status != 'failed') continue;
        await _replacePendingMedia(messageId, statusUrl, block.toJson());
        return;
      }
    } finally {
      _mediaPolls.remove(key);
    }
  }

  bool _messageStillHasStatusUrl(String messageId, String statusUrl) {
    WesiAiMessage? message;
    for (final item in state.messages) {
      if (item.id == messageId) {
        message = item;
        break;
      }
    }
    if (message == null) return false;
    final blocks = message.metadata['blocks'];
    if (blocks is! List) return false;
    for (final raw in blocks) {
      final map = raw is Map ? Map<String, dynamic>.from(raw) : null;
      final data = map?['data'];
      if (data is Map && '${data['url'] ?? ''}' == statusUrl) return true;
    }
    return false;
  }

  Future<void> _replacePendingMedia(
    String messageId,
    String statusUrl,
    Map<String, dynamic> resolved,
  ) async {
    var changed = false;
    final messages = state.messages.map((message) {
      if (message.id != messageId) return message;
      final rawBlocks = message.metadata['blocks'];
      if (rawBlocks is! List) return message;
      final nextBlocks = <dynamic>[];
      for (final raw in rawBlocks) {
        if (raw is Map) {
          final map = Map<String, dynamic>.from(raw);
          final data = map['data'];
          if (map['type'] == 'media' &&
              data is Map &&
              '${data['url'] ?? ''}' == statusUrl) {
            nextBlocks.add(resolved);
            changed = true;
            continue;
          }
        }
        nextBlocks.add(raw);
      }
      if (!changed) return message;
      final metadata = Map<String, dynamic>.from(message.metadata);
      metadata['blocks'] = nextBlocks;
      return message.copyWith(metadata: metadata);
    }).toList(growable: false);
    if (!changed || _disposed) return;
    state = state.copyWith(messages: messages);
    await _persist();
  }

  String _titleFor(WesiAiConversation c, String text) {
    if (!c.title.startsWith('Новый ')) return c.title;
    return text.length <= 42 ? text : '${text.substring(0, 42)}…';
  }

  Future<void> _persist() async {
    await store.save(state);
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    WesiAiSessionPolicy.markModuleClosed();
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    _mediaPolls.clear();
    super.dispose();
  }
}
