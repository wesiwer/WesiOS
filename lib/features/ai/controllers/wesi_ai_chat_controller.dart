import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../media_engines/wesi_media_engine_runner.dart';
import '../memory/wesi_ai_memory_api.dart';
import '../memory/wesi_ai_memory_engine.dart';
import '../memory/wesi_ai_memory_models.dart';
import '../models/wesi_ai_attachment.dart';
import '../models/wesi_ai_chat_models.dart';
import '../storage/wesi_ai_local_store.dart';
import '../wesi_ai_api.dart';

class WesiAiChatController extends ChangeNotifier {
  final WesiAiLocalStore store;
  final WesiAiApi api;
  final Set<String> _mediaPolls = <String>{};
  final Set<String> _localMediaRuns = <String>{};
  final Set<String> _memoryRefreshes = <String>{};
  final WesiAiMemoryApi memoryApi = const WesiAiMemoryApi();
  bool _disposed = false;
  Completer<void>? _activeTurnInterrupt;
  WesiAiRequestCancellation? _activeRequestCancellation;

  WesiAiLocalState state;
  bool loading = true;
  bool sending = false;

  WesiAiChatController({required this.store, this.api = const WesiAiApi()})
      : state = WesiAiLocalState.empty(store.employeeId);

  Future<void> load() async {
    state = await store.load();
    loading = false;
    notifyIfActive();
    for (final message in state.messages) {
      _startPendingMedia(message);
    }
  }

  Future<void> setTier(WesiAiTier tier) async {
    state = state.copyWith(tier: tier);
    await _persist();
  }

  Future<void> createConversation(WesiAiPersona persona) async {
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
    await _persist();
  }

  Future<void> selectConversation(String id) async {
    if (!state.conversations.any(
      (c) => c.id == id && c.employeeId == store.employeeId,
    )) {
      return;
    }
    state = state.copyWith(activeConversationId: id);
    await _persist();
  }

  WesiAiProject? _projectFor(String? projectId) {
    if (projectId == null) return null;
    for (final project in state.projects) {
      if (project.id == projectId && project.employeeId == store.employeeId) {
        return project;
      }
    }
    return null;
  }

  Future<void> addUserMessage(
    String text, {
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
  }) async {
    final c = state.activeConversation;
    final clean = text.trim();
    if (c == null || sending || (clean.isEmpty && attachments.isEmpty)) return;
    try {
      WesiAiAttachment.validateBatch(attachments);
    } on FormatException catch (e) {
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
            metadata: const <String, dynamic>{'code': 'WAI_ATTACHMENT_INVALID'},
          ),
        ],
      );
      await _persist();
      return;
    }

    final history = state.messagesFor(c.id);
    final now = DateTime.now();
    final visibleText = clean.isNotEmpty
        ? clean
        : 'Вложения: ${attachments.map((item) => item.name).join(', ')}';
    final user = WesiAiMessage(
      id: '${now.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
      conversationId: c.id,
      employeeId: store.employeeId,
      author: WesiAiMessageAuthor.user,
      text: visibleText,
      createdAt: now,
      metadata: attachments.isEmpty
          ? const <String, dynamic>{}
          : <String, dynamic>{
              'attachments': attachments
                  .map((attachment) => attachment.toMetadataJson())
                  .toList(growable: false),
            },
    );
    final titleSource = clean.isNotEmpty ? clean : attachments.first.name;
    final updated =
        c.copyWith(updatedAt: now, title: _titleFor(c, titleSource));
    final conversations = state.conversations
        .map((x) => x.id == c.id ? updated : x)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = state.copyWith(
      messages: <WesiAiMessage>[...state.messages, user],
      conversations: conversations,
    );
    sending = true;
    await _persist();

    final author = switch (c.persona) {
      WesiAiPersona.zane => WesiAiMessageAuthor.zane,
      WesiAiPersona.nirvana => WesiAiMessageAuthor.nirvana,
      WesiAiPersona.lobby => WesiAiMessageAuthor.zane
    };
    final streamMessageId = '${user.id}_transport_stream';
    var streamedText = '';
    var streamVisible = false;

    void removeTransientStream() {
      if (!streamVisible) return;
      state = state.copyWith(
        messages: state.messages
            .where((message) => message.id != streamMessageId)
            .toList(growable: false),
      );
      streamVisible = false;
      streamedText = '';
      notifyIfActive();
    }

    void onDelta(String delta) {
      if (delta.isEmpty || c.persona == WesiAiPersona.lobby) return;
      streamedText += delta;
      final at = DateTime.now();
      final partial = WesiAiMessage(
        id: streamMessageId,
        conversationId: c.id,
        employeeId: store.employeeId,
        author: author,
        text: streamedText,
        createdAt: at,
        metadata: const <String, dynamic>{'transportStreaming': true},
      );
      final withoutPartial = state.messages
          .where((message) => message.id != streamMessageId)
          .toList(growable: false);
      state =
          state.copyWith(messages: <WesiAiMessage>[...withoutPartial, partial]);
      streamVisible = true;
      notifyIfActive();
    }

    final cancellation = WesiAiRequestCancellation();
    _activeRequestCancellation = cancellation;
    try {
      final reply = await awaitInterruptible(api.send(
        conversation: updated,
        tier: state.tier,
        message: clean,
        history: history,
        memory: relevantMemoryFor(updated, clean),
        project: _projectFor(updated.projectId),
        conversationSummary: conversationMemoryFor(updated.id).rollingSummary,
        taskState: conversationMemoryFor(updated.id).taskState,
        attachments: attachments,
        onDelta: onDelta,
        cancellation: cancellation,
      ));
      if (reply == null) {
        removeTransientStream();
        return;
      }
      final at = DateTime.now();
      final assistant = WesiAiMessage(
        id: streamVisible
            ? streamMessageId
            : '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
        conversationId: c.id,
        employeeId: store.employeeId,
        author: author,
        text: reply.answer,
        createdAt: at,
        metadata: <String, dynamic>{
          'requestId': reply.requestId,
          if (streamVisible) 'transportStreamed': true,
          if (reply.blocks.isNotEmpty)
            'blocks': reply.blocks
                .map((block) => block.toJson())
                .toList(growable: false),
        },
      );
      final withoutPartial = state.messages
          .where((message) => message.id != streamMessageId)
          .toList(growable: false);
      state = state.copyWith(
        messages: <WesiAiMessage>[...withoutPartial, assistant],
      );
      streamVisible = false;
      _startPendingMedia(assistant);
      scheduleMemoryRefresh(updated, clean);
    } on WesiAiApiException catch (e) {
      removeTransientStream();
      if (e.code == 'WAI_CANCELLED') return;
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
      if (identical(_activeRequestCancellation, cancellation)) {
        _activeRequestCancellation = null;
      }
      sending = false;
      await _persist();
    }
  }

  @protected
  WesiAiConversationMemoryState conversationMemoryFor(String conversationId) =>
      state.conversationMemory[conversationId] ??
      WesiAiConversationMemoryState(conversationId: conversationId);

  @protected
  WesiAiMemorySnapshot relevantMemoryFor(
    WesiAiConversation conversation,
    String query,
  ) =>
      WesiAiMemoryEngine.retrieve(
        entries: state.memoryEntries,
        employeeId: store.employeeId,
        persona: conversation.persona,
        projectId: conversation.projectId,
        query: query,
        settings: state.memorySettings,
      ).toSnapshot();

  @protected
  void scheduleMemoryRefresh(
    WesiAiConversation conversation,
    String latestUserText,
  ) {
    if (!_memoryRefreshes.add(conversation.id)) return;
    unawaited(_refreshMemory(conversation, latestUserText).whenComplete(() {
      _memoryRefreshes.remove(conversation.id);
    }));
  }

  Future<void> _refreshMemory(
    WesiAiConversation conversation,
    String latestUserText,
  ) async {
    try {
      if (!state.conversations.any((item) => item.id == conversation.id))
        return;
      final messages = state.messagesFor(conversation.id);
      final textMessages = messages
          .where((message) => message.kind == WesiAiMessageKind.text)
          .toList(growable: false);
      final conversationMemory = conversationMemoryFor(conversation.id);
      if (!WesiAiMemoryEngine.shouldProcess(
        settings: state.memorySettings,
        conversationMemory: conversationMemory,
        currentTextMessageCount: textMessages.length,
        latestUserText: latestUserText,
      )) {
        return;
      }
      final relevant = relevantMemoryFor(conversation, latestUserText);
      final result = await memoryApi.process(
        conversation: conversation,
        recentMessages: textMessages,
        previousSummary: conversationMemory.rollingSummary,
        taskState: conversationMemory.taskState,
        memory: relevant,
        project: _projectFor(conversation.projectId),
      );
      if (!state.conversations.any((item) => item.id == conversation.id))
        return;
      final merged = WesiAiMemoryEngine.mergeCandidates(
        existing: state.memoryEntries,
        candidates: result.memories,
        employeeId: store.employeeId,
        sourceConversationId: conversation.id,
        projectId: conversation.projectId,
        settings: state.memorySettings,
      );
      final nextConversationMemory =
          Map<String, WesiAiConversationMemoryState>.from(
        state.conversationMemory,
      );
      nextConversationMemory[conversation.id] = conversationMemory.copyWith(
        rollingSummary: result.summary,
        taskState: result.taskState,
        summarizedMessageCount: textMessages.length,
      );
      state = state.copyWith(
        memoryEntries: merged,
        conversationMemory: nextConversationMemory,
      );
      await _persist();
    } catch (_) {
      // Memory enrichment is best-effort and must never fail the chat turn.
    }
  }

  Future<void> setAutoMemoryEnabled(bool enabled) async {
    state = state.copyWith(
      memorySettings: state.memorySettings.copyWith(autoMemoryEnabled: enabled),
    );
    await _persist();
  }

  Future<void> setActiveConversationMemoryEnabled(bool enabled) async {
    final conversation = state.activeConversation;
    if (conversation == null) return;
    final map = Map<String, WesiAiConversationMemoryState>.from(
      state.conversationMemory,
    );
    map[conversation.id] =
        conversationMemoryFor(conversation.id).copyWith(memoryEnabled: enabled);
    state = state.copyWith(conversationMemory: map);
    await _persist();
  }

  Future<bool> addManualMemory(
    WesiAiMemoryScope scope,
    String text,
  ) async {
    final clean = text.trim();
    if (clean.isEmpty ||
        clean.length > WesiAiMemoryEngine.maxMemoryTextLength ||
        WesiAiMemoryEngine.looksSensitive(clean)) {
      return false;
    }
    final projectId = state.activeProjectId;
    if (scope == WesiAiMemoryScope.project && projectId == null) return false;
    final normalized = WesiAiMemoryEngine.normalizeForDedup(clean);
    if (normalized.length < 4) return false;
    final now = DateTime.now();
    final entries = <WesiAiMemoryEntry>[...state.memoryEntries];
    for (var index = 0; index < entries.length; index++) {
      final old = entries[index];
      if (old.scope != scope ||
          (scope == WesiAiMemoryScope.project && old.projectId != projectId)) {
        continue;
      }
      if (WesiAiMemoryEngine.normalizeForDedup(old.text) == normalized) {
        entries[index] = old.copyWith(
          text: clean,
          updatedAt: now,
          manual: true,
          importance: 1,
        );
        state = state.copyWith(memoryEntries: entries);
        await _persist();
        return true;
      }
    }
    entries.add(WesiAiMemoryEntry(
      id: 'memory_manual_${now.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
      employeeId: store.employeeId,
      scope: scope,
      text: clean,
      createdAt: now,
      updatedAt: now,
      sourceConversationId: state.activeConversationId,
      projectId: scope == WesiAiMemoryScope.project ? projectId : null,
      manual: true,
      importance: 1,
    ));
    state = state.copyWith(memoryEntries: entries);
    await _persist();
    return true;
  }

  Future<void> deleteMemory(String id) async {
    final next = state.memoryEntries.where((entry) => entry.id != id).toList();
    if (next.length == state.memoryEntries.length) return;
    state = state.copyWith(memoryEntries: next);
    await _persist();
  }

  Future<void> clearMemoryScope(WesiAiMemoryScope scope) async {
    final activeProjectId = state.activeProjectId;
    final next = state.memoryEntries.where((entry) {
      if (entry.scope != scope) return true;
      if (scope == WesiAiMemoryScope.project) {
        return activeProjectId == null || entry.projectId != activeProjectId;
      }
      return false;
    }).toList(growable: false);
    state = state.copyWith(memoryEntries: next);
    await _persist();
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

      final localRequest = data['localRequest'];
      if (localRequest is Map) {
        final key =
            '${message.id}|local|${data['mediaType']}|${data['prompt']}';
        if (_localMediaRuns.add(key)) {
          unawaited(_runLocalMedia(
            message,
            Map<String, dynamic>.from(localRequest),
            key,
          ));
        }
        continue;
      }

      final statusUrl = '${data['url'] ?? ''}'.trim();
      final uri = Uri.tryParse(statusUrl);
      if (uri == null || !uri.path.startsWith('/api/wesi/ai/media/jobs/')) {
        continue;
      }
      final key = '${message.id}|$statusUrl';
      if (!_mediaPolls.add(key)) continue;
      unawaited(_monitorMedia(message.id, statusUrl, key));
    }
  }

  Future<void> _runLocalMedia(
    WesiAiMessage source,
    Map<String, dynamic> request,
    String key,
  ) async {
    try {
      final result = await WesiMediaEngineRunner.run(request);
      if (_disposed) return;
      await _markLocalRequestFinished(source.id, request, result.ok);
      final at = DateTime.now();
      final type = '${request['mediaType'] ?? 'media'}';
      final label = switch (type) {
        'image' => 'изображения',
        'music' => 'музыки',
        'video' => 'видео',
        _ => 'медиа',
      };
      final text = result.ok
          ? 'Локальная генерация $label завершена. Файл сохранён: ${result.outputPath}'
          : result.code == 'WAI_MEDIA_ENGINE_NOT_INSTALLED'
              ? 'Для генерации $label установите соответствующий Wesi AI Media Engine в Настройки → Модели.'
              : 'Локальная генерация $label не завершилась (${result.code}).';
      state = state.copyWith(
        messages: <WesiAiMessage>[
          ...state.messages,
          WesiAiMessage(
            id: '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
            conversationId: source.conversationId,
            employeeId: store.employeeId,
            author: WesiAiMessageAuthor.system,
            kind: result.ok ? WesiAiMessageKind.file : WesiAiMessageKind.error,
            text: text,
            createdAt: at,
            metadata: <String, dynamic>{
              'code': result.code,
              'mediaType': type,
              if (result.outputPath != null) 'localPath': result.outputPath,
              if (result.mimeType != null) 'mimeType': result.mimeType,
            },
          ),
        ],
      );
      await _persist();
    } finally {
      _localMediaRuns.remove(key);
    }
  }

  Future<void> _markLocalRequestFinished(
    String messageId,
    Map<String, dynamic> request,
    bool ok,
  ) async {
    var changed = false;
    final messages = state.messages.map((message) {
      if (message.id != messageId) return message;
      final rawBlocks = message.metadata['blocks'];
      if (rawBlocks is! List) return message;
      final nextBlocks = <dynamic>[];
      for (final raw in rawBlocks) {
        if (raw is Map) {
          final block = Map<String, dynamic>.from(raw);
          final dataRaw = block['data'];
          if (block['type'] == 'media' && dataRaw is Map) {
            final data = Map<String, dynamic>.from(dataRaw);
            final localRaw = data['localRequest'];
            if (localRaw is Map &&
                '${localRaw['mediaType'] ?? ''}' ==
                    '${request['mediaType'] ?? ''}' &&
                '${localRaw['prompt'] ?? ''}' == '${request['prompt'] ?? ''}') {
              data.remove('localRequest');
              data['status'] = ok ? 'ready' : 'failed';
              block['data'] = data;
              nextBlocks.add(block);
              changed = true;
              continue;
            }
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
      if (raw is! Map) continue;
      final data = raw['data'];
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

  bool interruptActiveTurn() {
    final transportCancelled = _activeRequestCancellation?.cancel() ?? false;
    final signal = _activeTurnInterrupt;
    if (signal == null || signal.isCompleted) return transportCancelled;
    signal.complete();
    return true;
  }

  @protected
  Future<T?> awaitInterruptible<T>(Future<T> future) async {
    final signal = Completer<void>();
    _activeTurnInterrupt = signal;
    try {
      final result = await Future.any<(bool interrupted, T? value)>([
        future.then<(bool interrupted, T? value)>((value) => (false, value)),
        signal.future.then<(bool interrupted, T? value)>((_) => (true, null)),
      ]);
      return result.$1 ? null : result.$2;
    } finally {
      if (identical(_activeTurnInterrupt, signal)) {
        _activeTurnInterrupt = null;
      }
    }
  }

  @protected
  bool get isDisposed => _disposed;

  @protected
  void notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _persist() async {
    await store.save(state);
    notifyIfActive();
  }

  @override
  void dispose() {
    _disposed = true;
    _mediaPolls.clear();
    _localMediaRuns.clear();
    super.dispose();
  }
}
