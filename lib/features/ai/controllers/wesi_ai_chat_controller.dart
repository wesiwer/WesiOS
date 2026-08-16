import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../media_engines/wesi_media_input_stager.dart';
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
  final WesiAiMemoryApi memoryApi;
  bool _disposed = false;
  Completer<void>? _activeTurnInterrupt;
  WesiAiRequestCancellation? _activeRequestCancellation;
  final Set<String> _transientConversationIds = <String>{};

  WesiAiLocalState state;
  bool loading = true;
  bool sending = false;

  WesiAiChatController({
    required this.store,
    this.api = const WesiAiApi(),
    this.memoryApi = const WesiAiMemoryApi(),
  }) : state = WesiAiLocalState.empty(store.employeeId);

  Future<void> load() async {
    _transientConversationIds.clear();
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
    final oldDrafts = Set<String>.from(_transientConversationIds);
    _transientConversationIds
      ..clear()
      ..add(id);
    state = state.copyWith(
      conversations: <WesiAiConversation>[
        c,
        ...state.conversations.where((item) => !oldDrafts.contains(item.id)),
      ],
      messages: state.messages
          .where((message) => !oldDrafts.contains(message.conversationId))
          .toList(growable: false),
      activeConversationId: id,
      conversationMemory:
          Map<String, WesiAiConversationMemoryState>.fromEntries(
        state.conversationMemory.entries
            .where((entry) => !oldDrafts.contains(entry.key)),
      ),
    );
    // Новый чат существует только как UI draft. Он попадёт в durable history
    // после первой принятой пользовательской отправки.
    notifyIfActive();
  }

  bool isTransientConversation(String id) =>
      _transientConversationIds.contains(id);

  @protected
  WesiAiLocalState get persistableState {
    if (_transientConversationIds.isEmpty) return state;
    final ids = _transientConversationIds;
    final activeIsDraft = ids.contains(state.activeConversationId);
    return state.copyWith(
      conversations: state.conversations
          .where((conversation) => !ids.contains(conversation.id))
          .toList(growable: false),
      messages: state.messages
          .where((message) => !ids.contains(message.conversationId))
          .toList(growable: false),
      conversationMemory:
          Map<String, WesiAiConversationMemoryState>.fromEntries(
        state.conversationMemory.entries
            .where((entry) => !ids.contains(entry.key)),
      ),
      clearActiveConversation: activeIsDraft,
    );
  }

  @protected
  Future<bool> materializeConversationForFirstTurn(String id) async {
    if (!_transientConversationIds.remove(id)) return true;
    try {
      await store.save(persistableState);
      return true;
    } catch (_) {
      _transientConversationIds.add(id);
      return false;
    }
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

  Future<void> setMessageSaved(String messageId, bool saved) async {
    var changed = false;
    final messages = state.messages.map((message) {
      if (message.id != messageId || message.employeeId != store.employeeId) {
        return message;
      }
      final metadata = Map<String, dynamic>.from(message.metadata);
      if (saved) {
        metadata['savedToChatArchive'] = true;
      } else {
        metadata.remove('savedToChatArchive');
      }
      changed = true;
      return message.copyWith(metadata: metadata);
    }).toList(growable: false);
    if (!changed) return;
    state = state.copyWith(messages: messages);
    await _persist();
  }

  Future<String?> branchConversationFromMessage(String messageId) async {
    WesiAiMessage? target;
    for (final message in state.messages) {
      if (message.id == messageId && message.employeeId == store.employeeId) {
        target = message;
        break;
      }
    }
    if (target == null) return null;
    WesiAiConversation? source;
    for (final conversation in state.conversations) {
      if (conversation.id == target.conversationId &&
          conversation.employeeId == store.employeeId) {
        source = conversation;
        break;
      }
    }
    if (source == null) return null;
    final sourceMessages = state.messagesFor(source.id);
    final targetIndex =
        sourceMessages.indexWhere((message) => message.id == messageId);
    if (targetIndex < 0) return null;

    final now = DateTime.now();
    final newId = '${now.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
    final copied = <WesiAiMessage>[];
    for (var index = 0; index <= targetIndex; index++) {
      final original = sourceMessages[index];
      copied.add(WesiAiMessage(
        id: '${newId}_branch_$index',
        conversationId: newId,
        employeeId: store.employeeId,
        author: original.author,
        kind: original.kind,
        text: original.text,
        createdAt: original.createdAt,
        metadata: <String, dynamic>{
          ...original.metadata,
          'branchOriginalConversationId': source.id,
          'branchOriginalMessageId': original.id,
        },
      ));
    }
    final branch = WesiAiConversation(
      id: newId,
      employeeId: store.employeeId,
      title: 'Ветка · ${source.title}',
      persona: source.persona,
      lobbyMode: source.lobbyMode,
      projectId: source.projectId,
      createdAt: now,
      updatedAt: now,
      branchedFromConversationId: source.id,
      branchedFromMessageId: messageId,
    );
    state = state.copyWith(
      conversations: <WesiAiConversation>[branch, ...state.conversations],
      messages: <WesiAiMessage>[...state.messages, ...copied],
      activeConversationId: newId,
      activeProjectId: source.projectId,
      clearActiveProject: source.projectId == null,
    );
    await _persist();
    return newId;
  }

  Future<void> setConversationBackupImportant(
    String conversationId,
    bool important,
  ) async {
    var changed = false;
    final conversations = state.conversations.map((conversation) {
      if (conversation.id != conversationId ||
          conversation.employeeId != store.employeeId ||
          conversation.importantForBackup == important) {
        return conversation;
      }
      changed = true;
      return conversation.copyWith(importantForBackup: important);
    }).toList(growable: false);
    if (!changed) return;
    state = state.copyWith(conversations: conversations);
    await _persist();
  }

  Future<void> applyRestoredState(WesiAiLocalState restored) async {
    if (restored.employeeId != store.employeeId) {
      throw StateError('Employee mismatch');
    }
    state = restored;
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

    // Direct callers that bypass ManagedChatController also materialize
    // the draft at the first valid user message.
    _transientConversationIds.remove(c.id);
    final fullHistory = state.messagesFor(c.id);
    final history = historyForMemoryRequest(c.id, fullHistory);
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
    final workStartedAt = DateTime.now().toUtc();
    final activity = <Map<String, dynamic>>[];
    final openTools = <String, int>{};
    final openAgents = <String, int>{};
    var activitySequence = 0;
    var streamedText = '';
    var streamVisible = c.persona != WesiAiPersona.lobby;

    Map<String, dynamic> streamMetadata(bool streaming) => <String, dynamic>{
          if (streaming) 'transportStreaming': true,
          'activity': activity
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false),
          'workStartedAt': workStartedAt.toIso8601String(),
          'workDurationMs':
              DateTime.now().toUtc().difference(workStartedAt).inMilliseconds,
        };

    void publishPartial() {
      if (c.persona == WesiAiPersona.lobby) return;
      final partial = WesiAiMessage(
        id: streamMessageId,
        conversationId: c.id,
        employeeId: store.employeeId,
        author: author,
        text: streamedText,
        createdAt: workStartedAt.toLocal(),
        metadata: streamMetadata(true),
      );
      final withoutPartial = state.messages
          .where((message) => message.id != streamMessageId)
          .toList(growable: false);
      state =
          state.copyWith(messages: <WesiAiMessage>[...withoutPartial, partial]);
      streamVisible = true;
      notifyIfActive();
    }

    Map<String, dynamic> activityEntry({
      required String kind,
      required String label,
      String sourceName = '',
      String detail = '',
      String status = '',
      int additions = 0,
      int deletions = 0,
      List<dynamic> files = const <dynamic>[],
    }) {
      final at = DateTime.now().toUtc();
      return <String, dynamic>{
        'id': '${user.id}_activity_${activitySequence++}',
        'kind': kind,
        'label': label,
        if (sourceName.isNotEmpty) 'sourceName': sourceName,
        if (detail.isNotEmpty) 'detail': detail,
        if (status.isNotEmpty) 'status': status,
        'textOffset': streamedText.length,
        'startedAt': at.toIso8601String(),
        if (status == 'result' || status == 'done')
          'completedAt': at.toIso8601String(),
        'additions': additions < 0 ? 0 : additions,
        'deletions': deletions < 0 ? 0 : deletions,
        if (files.isNotEmpty)
          'files':
              files.take(40).map((item) => '$item').toList(growable: false),
      };
    }

    int safeCount(Object? value) {
      final count = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
      return count < 0 ? 0 : count;
    }

    String streamedToolDetail(Map<String, dynamic> raw) {
      final parts = <String>[];
      final rawDiagnostic = raw['diagnostic'];
      if (rawDiagnostic is Map) {
        final diagnostic = Map<String, dynamic>.from(rawDiagnostic);
        final stage = '${diagnostic['stage'] ?? ''}'.trim();
        final component = '${diagnostic['component'] ?? ''}'.trim();
        final operation = '${diagnostic['operation'] ?? ''}'.trim();
        final diagnosticCode = '${diagnostic['code'] ?? ''}'.trim();
        final lastSuccess = '${diagnostic['lastSuccess'] ?? ''}'.trim();
        final requestId = '${diagnostic['requestId'] ?? ''}'.trim();
        if (stage.isNotEmpty) parts.add('Этап: $stage');
        if (component.isNotEmpty) parts.add('Компонент: $component');
        if (operation.isNotEmpty) parts.add('Операция: $operation');
        if (diagnosticCode.isNotEmpty) parts.add('Код: $diagnosticCode');
        if (lastSuccess.isNotEmpty) parts.add('После: $lastSuccess');
        if (requestId.isNotEmpty) parts.add('Request ID: $requestId');
      }
      final transactionCount = raw['transactionCount'];
      if (transactionCount is num) {
        parts.add('${transactionCount.toInt()} операций');
      }
      final organizationName = '${raw['organizationName'] ?? ''}'.trim();
      final organizationId = '${raw['organizationId'] ?? ''}'.trim();
      if (organizationName.isNotEmpty) {
        parts.add(organizationName);
      } else if (organizationId.isNotEmpty) {
        parts.add(organizationId);
      }
      final code = '${raw['code'] ?? ''}'.trim();
      if (code.isNotEmpty) parts.add(code);
      return parts.join(' · ');
    }

    void onActivity(Map<String, dynamic> raw) {
      final type = '${raw['type'] ?? 'activity'}'.toLowerCase();
      final phase = '${raw['phase'] ?? ''}'.toLowerCase();
      final name =
          '${raw['name'] ?? raw['agent'] ?? raw['persona'] ?? ''}'.trim();
      final additions = safeCount(raw['additions']);
      final deletions = safeCount(raw['deletions']);
      final files = raw['files'] is List
          ? List<dynamic>.from(raw['files'] as List)
          : const <dynamic>[];
      if (type == 'tool') {
        if (phase == 'start') {
          activity.add(activityEntry(
            kind: 'tool',
            label: name.isEmpty ? 'Запущен инструмент' : 'Инструмент · $name',
            sourceName: name,
            status: 'start',
          ));
          if (name.isNotEmpty) openTools[name] = activity.length - 1;
        } else {
          final index = name.isEmpty ? null : openTools.remove(name);
          if (index != null && index >= 0 && index < activity.length) {
            final current = Map<String, dynamic>.from(activity[index]);
            current['status'] = 'result';
            current['completedAt'] = DateTime.now().toUtc().toIso8601String();
            current['additions'] = additions;
            current['deletions'] = deletions;
            if (files.isNotEmpty)
              current['files'] =
                  files.take(40).map((item) => '$item').toList(growable: false);
            final detail = streamedToolDetail(raw);
            if (detail.isNotEmpty) current['detail'] = detail;
            activity[index] = current;
          } else {
            activity.add(activityEntry(
              kind: 'tool',
              label:
                  name.isEmpty ? 'Инструмент завершён' : 'Инструмент · $name',
              sourceName: name,
              status: 'result',
              detail: streamedToolDetail(raw),
              additions: additions,
              deletions: deletions,
              files: files,
            ));
          }
        }
      } else if (type == 'agent') {
        if (phase == 'start') {
          activity.add(activityEntry(
            kind: 'agent',
            label: name.isEmpty ? 'Подключён агент' : 'Агент · $name',
            sourceName: name,
            status: 'start',
          ));
          if (name.isNotEmpty) openAgents[name] = activity.length - 1;
        } else {
          final index = name.isEmpty ? null : openAgents.remove(name);
          if (index != null && index >= 0 && index < activity.length) {
            final current = Map<String, dynamic>.from(activity[index]);
            current['status'] = 'result';
            current['completedAt'] = DateTime.now().toUtc().toIso8601String();
            current['additions'] = additions;
            current['deletions'] = deletions;
            if (files.isNotEmpty)
              current['files'] =
                  files.take(40).map((item) => '$item').toList(growable: false);
            activity[index] = current;
          } else {
            activity.add(activityEntry(
              kind: 'agent',
              label: name.isEmpty ? 'Агент завершил работу' : 'Агент · $name',
              sourceName: name,
              status: 'result',
              additions: additions,
              deletions: deletions,
              files: files,
            ));
          }
        }
      } else if (type == 'meta') {
        final persona = '${raw['persona'] ?? ''}'.trim();
        final tier = '${raw['tier'] ?? ''}'.trim();
        activity.add(activityEntry(
          kind: 'status',
          label: 'Контекст и маршрут подготовлены',
          sourceName: persona,
          detail: [if (persona.isNotEmpty) persona, if (tier.isNotEmpty) tier]
              .join(' · '),
          status: 'done',
        ));
      } else if (type == 'activity') {
        var detail = '${raw['detail'] ?? raw['message'] ?? ''}'.trim();
        final rawDiagnostic = raw['diagnostic'];
        if (rawDiagnostic is Map) {
          final diagnostic = Map<String, dynamic>.from(rawDiagnostic);
          final diagnosticParts = <String>[
            if ('${diagnostic['stage'] ?? ''}'.trim().isNotEmpty)
              'Этап: ${diagnostic['stage']}',
            if ('${diagnostic['component'] ?? ''}'.trim().isNotEmpty)
              'Компонент: ${diagnostic['component']}',
            if ('${diagnostic['code'] ?? ''}'.trim().isNotEmpty)
              'Код: ${diagnostic['code']}',
            if ('${diagnostic['requestId'] ?? ''}'.trim().isNotEmpty)
              'Request ID: ${diagnostic['requestId']}',
          ];
          final diagnosticText = diagnosticParts.join(' · ');
          if (diagnosticText.isNotEmpty && !detail.contains(diagnosticText)) {
            detail =
                detail.isEmpty ? diagnosticText : '$detail\n$diagnosticText';
          }
        }
        activity.add(activityEntry(
          kind: '${raw['kind'] ?? 'reasoning'}',
          label: '${raw['label'] ?? 'Ход работы'}'.trim(),
          sourceName: name,
          detail: detail,
          status: phase.isEmpty ? '${raw['status'] ?? ''}' : phase,
          additions: additions,
          deletions: deletions,
          files: files,
        ));
      }
      publishPartial();
    }

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
      publishPartial();
    }

    if (streamVisible) {
      activity.add(activityEntry(
        kind: 'reasoning',
        label: 'Подготавливаю ответ',
        detail:
            'Собираю контекст диалога, память, проект и доступные действия.',
        status: 'start',
      ));
      publishPartial();
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
        onActivity: onActivity,
        cancellation: cancellation,
      ));
      if (reply == null) {
        removeTransientStream();
        return;
      }
      for (final finalEvent in reply.activity) {
        final sourceName =
            '${finalEvent['sourceName'] ?? finalEvent['name'] ?? finalEvent['tool'] ?? ''}'
                .trim();
        final kind = '${finalEvent['kind'] ?? 'tool'}';
        var merged = false;
        if (sourceName.isNotEmpty) {
          for (var index = activity.length - 1; index >= 0; index--) {
            final current = activity[index];
            if ('${current['sourceName'] ?? ''}' == sourceName &&
                '${current['kind'] ?? ''}' == kind) {
              final next = Map<String, dynamic>.from(current);
              next['additions'] = safeCount(finalEvent['additions']);
              next['deletions'] = safeCount(finalEvent['deletions']);
              if (finalEvent['files'] is List)
                next['files'] = List<dynamic>.from(finalEvent['files'] as List);
              next['status'] = 'result';
              next['completedAt'] ??= DateTime.now().toUtc().toIso8601String();
              activity[index] = next;
              merged = true;
              break;
            }
          }
        }
        if (!merged) {
          final copy = Map<String, dynamic>.from(finalEvent);
          copy['id'] ??= '${user.id}_activity_${activitySequence++}';
          copy['textOffset'] ??= streamedText.length;
          activity.add(copy);
        }
      }
      final completedAt = DateTime.now().toUtc().toIso8601String();
      for (var index = 0; index < activity.length; index++) {
        final current = activity[index];
        if ('${current['status'] ?? ''}' != 'start') continue;
        final closed = Map<String, dynamic>.from(current);
        closed['status'] = 'done';
        closed['completedAt'] = completedAt;
        activity[index] = closed;
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
          if (activity.isNotEmpty)
            'activity': activity
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false),
          'workStartedAt': workStartedAt.toIso8601String(),
          'workDurationMs':
              DateTime.now().toUtc().difference(workStartedAt).inMilliseconds,
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
      _startPendingMedia(assistant, turnAttachments: attachments);
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
            text: e.displayMessage,
            createdAt: at,
            metadata: <String, dynamic>{
              'code': e.code,
              'diagnostic': e.diagnostic,
              if (e.requestId.isNotEmpty) 'requestId': e.requestId,
            },
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
  List<WesiAiMessage> historyForMemoryRequest(
    String conversationId,
    List<WesiAiMessage> history,
  ) {
    final memory = conversationMemoryFor(conversationId);
    if (memory.rollingSummary.trim().isEmpty ||
        memory.summarizedMessageCount <= 0) {
      return history;
    }
    final textMessages = history
        .where((message) =>
            message.kind == WesiAiMessageKind.text &&
            message.author != WesiAiMessageAuthor.system)
        .toList(growable: false);
    final start = memory.summarizedMessageCount.clamp(0, textMessages.length);
    final unsummarized = textMessages.sublist(start);
    if (unsummarized.length <= 24) return unsummarized;
    return unsummarized.sublist(unsummarized.length - 24);
  }

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
      final start = conversationMemory.summarizedMessageCount.clamp(
        0,
        textMessages.length,
      );
      if (start >= textMessages.length) return;
      final pending = textMessages.sublist(start);
      final batch = pending.length <= 24 ? pending : pending.sublist(0, 24);
      if (batch.isEmpty) return;
      final relevant = relevantMemoryFor(conversation, latestUserText);
      final result = await memoryApi.process(
        conversation: conversation,
        recentMessages: batch,
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
        summarizedMessageCount: start + batch.length,
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

  String _localMediaRequestIdentity(Map<String, dynamic> request) {
    final rawIndexes = request['attachmentIndexes'];
    final indexes =
        rawIndexes is List ? rawIndexes.map((item) => '$item').join(',') : '';
    return <String>[
      '${request['mediaType'] ?? ''}',
      '${request['workflow'] ?? ''}',
      '${request['prompt'] ?? ''}',
      '${request['title'] ?? ''}',
      indexes,
    ].join('|');
  }

  void _startPendingMedia(
    WesiAiMessage message, {
    List<WesiAiAttachment> turnAttachments = const <WesiAiAttachment>[],
  }) {
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
        final requestMap = Map<String, dynamic>.from(localRequest);
        final key =
            '${message.id}|local|${_localMediaRequestIdentity(requestMap)}';
        if (_localMediaRuns.add(key)) {
          unawaited(_runLocalMedia(
            message,
            requestMap,
            key,
            turnAttachments: turnAttachments,
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
    String key, {
    List<WesiAiAttachment> turnAttachments = const <WesiAiAttachment>[],
  }) async {
    try {
      final result = await WesiMediaTurnExecutor.run(
        request,
        turnAttachments,
      );
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
    final targetIdentity = _localMediaRequestIdentity(request);
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
                _localMediaRequestIdentity(
                      Map<String, dynamic>.from(localRaw),
                    ) ==
                    targetIdentity) {
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
    await store.save(persistableState);
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
