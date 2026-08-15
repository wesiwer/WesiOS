import 'dart:async';
import 'dart:math';

import 'models/wesi_ai_attachment.dart';
import 'models/wesi_ai_chat_models.dart';
import 'storage/wesi_ai_local_store.dart';
import 'wesi_ai_api.dart';
import 'wesi_ai_lobby_api.dart';
import 'wesi_ai_lobby_controller.dart';

class _TransientRetryPayload {
  final String prompt;
  final List<WesiAiAttachment> attachments;
  const _TransientRetryPayload(this.prompt, this.attachments);
}

class WesiAiQueuedTurn {
  final String id;
  final String conversationId;
  final String text;
  final List<WesiAiAttachment> attachments;
  final DateTime queuedAt;

  const WesiAiQueuedTurn({
    required this.id,
    required this.conversationId,
    required this.text,
    required this.attachments,
    required this.queuedAt,
  });

  String get preview {
    if (text.trim().isNotEmpty) return text.trim();
    if (attachments.length == 1) return attachments.first.name;
    if (attachments.isNotEmpty) return 'Вложения: ${attachments.length}';
    return 'Сообщение';
  }
}

enum WesiAiMessageSubmitResult {
  accepted,
  queueFull,
  invalidAttachments,
  persistenceFailed,
  unavailable,
}

class WesiAiManagedChatController extends WesiAiLobbyChatController {
  static const int maxQueuedTurns = 12;
  static final String _runtimeQueueSessionId =
      'runtime_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';

  final Map<String, _TransientRetryPayload> _attachmentRetries =
      <String, _TransientRetryPayload>{};
  final List<WesiAiQueuedTurn> _queuedTurns = <WesiAiQueuedTurn>[];
  final String _queueSessionId;
  bool _drainingQueue = false;

  WesiAiManagedChatController({
    required WesiAiLocalStore store,
    WesiAiApi api = const WesiAiLobbyApi(),
    String? processSessionId,
  })  : _queueSessionId = processSessionId ?? _runtimeQueueSessionId,
        super(store: store, api: api);

  int get queuedTurnCount => _queuedTurns.length;
  List<WesiAiQueuedTurn> get queuedTurns =>
      List<WesiAiQueuedTurn>.unmodifiable(_queuedTurns);
  bool get processing => sending || _drainingQueue || _queuedTurns.isNotEmpty;

  void _notify() => notifyIfActive();

  @override
  Future<void> load() async {
    await super.load();
    await _recoverPendingQueue();
  }

  Future<WesiAiMessageSubmitResult> submitUserMessage(
    String text, {
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
  }) =>
      _acceptTurn(text, attachments: attachments, startDrain: true);

  Future<WesiAiMessageSubmitResult> _acceptTurn(
    String text, {
    required List<WesiAiAttachment> attachments,
    required bool startDrain,
  }) async {
    final conversation = state.activeConversation;
    final clean = text.trim();
    if (conversation == null || (clean.isEmpty && attachments.isEmpty)) {
      return WesiAiMessageSubmitResult.unavailable;
    }
    try {
      WesiAiAttachment.validateBatch(attachments);
    } on FormatException {
      return WesiAiMessageSubmitResult.invalidAttachments;
    }
    if (_queuedTurns.length >= maxQueuedTurns) {
      return WesiAiMessageSubmitResult.queueFull;
    }

    final queuedAt = DateTime.now();
    final turn = WesiAiQueuedTurn(
      id: 'queue_${queuedAt.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
      conversationId: conversation.id,
      text: clean,
      attachments: List<WesiAiAttachment>.unmodifiable(attachments),
      queuedAt: queuedAt,
    );
    // Reserve the slot before the await so concurrent submissions cannot all
    // pass the queue limit. UI only receives `accepted` after durable storage.
    _queuedTurns.add(turn);
    try {
      await store.savePendingQueueItem(
        _pendingFor(turn, WesiAiPendingQueueStatus.queued),
      );
    } catch (_) {
      _queuedTurns.removeWhere((candidate) => candidate.id == turn.id);
      _notify();
      return WesiAiMessageSubmitResult.persistenceFailed;
    }
    _notify();
    if (startDrain) unawaited(_drainQueuedTurns());
    return WesiAiMessageSubmitResult.accepted;
  }

  WesiAiPendingQueueItem _pendingFor(
    WesiAiQueuedTurn turn,
    WesiAiPendingQueueStatus status,
  ) =>
      WesiAiPendingQueueItem(
        id: turn.id,
        employeeId: store.employeeId,
        conversationId: turn.conversationId,
        text: turn.text,
        queuedAt: turn.queuedAt,
        processSessionId: _queueSessionId,
        status: status,
        attachments: turn.attachments
            .map((attachment) => attachment.toMetadataJson())
            .toList(growable: false),
      );

  WesiAiConversation? _conversationById(String id) {
    for (final conversation in state.conversations) {
      if (conversation.id == id && !conversation.archived) return conversation;
    }
    return null;
  }

  @override
  Future<void> addUserMessage(
    String text, {
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
  }) async {
    final conversation = state.activeConversation;
    final result = await _acceptTurn(
      text,
      attachments: attachments,
      startDrain: false,
    );
    if (result == WesiAiMessageSubmitResult.accepted) {
      await _drainQueuedTurns();
      return;
    }
    if (conversation == null) return;
    if (result == WesiAiMessageSubmitResult.queueFull) {
      await _appendQueueFullError(conversation.id);
    } else if (result == WesiAiMessageSubmitResult.invalidAttachments) {
      await _appendLocalSubmissionError(
        conversation.id,
        code: 'WAI_ATTACHMENT_INVALID',
        text: 'Не удалось отправить сообщение: проверьте вложения.',
      );
    }
  }

  Future<void> _sendNow(
    String text, {
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
  }) async {
    final conversationId = state.activeConversationId;
    final previousUserIds = conversationId == null
        ? const <String>{}
        : state
            .messagesFor(conversationId)
            .where((message) => message.author == WesiAiMessageAuthor.user)
            .map((message) => message.id)
            .toSet();
    await super.addUserMessage(text, attachments: attachments);
    if (attachments.isEmpty || conversationId == null) return;
    WesiAiMessage? added;
    for (final message in state.messagesFor(conversationId).reversed) {
      if (message.author == WesiAiMessageAuthor.user &&
          !previousUserIds.contains(message.id)) {
        added = message;
        break;
      }
    }
    if (added == null) return;
    _attachmentRetries[added.id] = _TransientRetryPayload(
      text.trim(),
      List<WesiAiAttachment>.unmodifiable(attachments),
    );
    while (_attachmentRetries.length > 8) {
      _attachmentRetries.remove(_attachmentRetries.keys.first);
    }
  }

  Future<void> _drainQueuedTurns() async {
    if (_drainingQueue || sending || _queuedTurns.isEmpty) return;
    _drainingQueue = true;
    _notify();
    try {
      while (_queuedTurns.isNotEmpty) {
        final turn = _queuedTurns.first;
        try {
          // `inflight` is persisted before any network/tool side effect. A
          // process restart will never auto-replay this uncertain operation.
          await store.savePendingQueueItem(
            _pendingFor(turn, WesiAiPendingQueueStatus.inflight),
          );
        } catch (_) {
          _queuedTurns.removeAt(0);
          try {
            await _appendLocalSubmissionError(
              turn.conversationId,
              code: 'WAI_QUEUE_PERSISTENCE_FAILED',
              text:
                  'Не удалось безопасно подготовить сохранённое сообщение к отправке. Оно не было отправлено автоматически.',
            );
          } catch (_) {
            _notify();
          }
          continue;
        }

        _queuedTurns.removeAt(0);
        _notify();
        try {
          final target = _conversationById(turn.conversationId);
          if (target == null) continue;
          if (state.activeConversationId != target.id) {
            state = state.copyWith(
              activeConversationId: target.id,
              activeProjectId: target.projectId,
              clearActiveProject: target.projectId == null,
            );
            await _save();
          }
          await _sendNow(turn.text, attachments: turn.attachments);
        } catch (_) {
          try {
            await _appendQueueItemError(turn.conversationId);
          } catch (_) {
            _notify();
          }
        } finally {
          await _finishPendingTurn(turn);
        }
      }
    } finally {
      _drainingQueue = false;
      _notify();
    }
  }

  Future<void> _finishPendingTurn(WesiAiQueuedTurn turn) async {
    try {
      await store.savePendingQueueItem(
        _pendingFor(turn, WesiAiPendingQueueStatus.completed),
      );
    } catch (_) {}
    try {
      await store.removePendingQueueItem(turn.id);
    } catch (_) {}
  }

  Future<void> _retireRecoveredItem(WesiAiPendingQueueItem item) async {
    try {
      await store.savePendingQueueItem(
        item.copyWith(
          processSessionId: _queueSessionId,
          status: WesiAiPendingQueueStatus.completed,
        ),
      );
    } catch (_) {}
    try {
      await store.removePendingQueueItem(item.id);
    } catch (_) {}
  }

  Future<void> _recoverPendingQueue() async {
    List<WesiAiPendingQueueItem> pending;
    try {
      pending = await store.loadPendingQueueItems();
    } catch (_) {
      return;
    }
    if (pending.isEmpty) return;

    final recoveryMessages = <WesiAiMessage>[];
    for (final item in pending) {
      if (item.status == WesiAiPendingQueueStatus.completed) {
        await _retireRecoveredItem(item);
        continue;
      }
      // A second screen/controller in the same running process must not steal
      // work still owned by the first controller. A real process restart gets
      // a new runtime session id and therefore enters the recovery path below.
      if (item.processSessionId == _queueSessionId) continue;

      final target = _conversationById(item.conversationId);
      if (target == null) {
        await _retireRecoveredItem(item);
        continue;
      }

      if (item.status == WesiAiPendingQueueStatus.inflight) {
        await _retireRecoveredItem(item);
        recoveryMessages.add(
          _recoveryError(
            item,
            code: 'WAI_QUEUE_RECOVERY_UNCERTAIN',
            text:
                'Предыдущая отправка была прервана перезапуском. WesiOS не повторил её автоматически, чтобы не продублировать возможные действия. Проверьте чат и при необходимости отправьте запрос снова.',
          ),
        );
        continue;
      }

      if (item.attachments.isNotEmpty) {
        await _retireRecoveredItem(item);
        final names = item.attachments
            .map((attachment) => '${attachment['name'] ?? 'file'}')
            .join(', ');
        recoveryMessages.add(
          _recoveryError(
            item,
            code: 'WAI_REATTACH_REQUIRED',
            text:
                'После перезапуска сообщение с вложениями не отправлено автоматически. Прикрепите файлы заново: $names.',
          ),
        );
        continue;
      }

      final clean = item.text.trim();
      if (clean.isEmpty) {
        await _retireRecoveredItem(item);
        continue;
      }
      final claimed = item.copyWith(
        processSessionId: _queueSessionId,
        status: WesiAiPendingQueueStatus.queued,
      );
      try {
        await store.savePendingQueueItem(claimed);
        _queuedTurns.add(
          WesiAiQueuedTurn(
            id: item.id,
            conversationId: item.conversationId,
            text: clean,
            attachments: const <WesiAiAttachment>[],
            queuedAt: item.queuedAt,
          ),
        );
      } catch (_) {
        recoveryMessages.add(
          _recoveryError(
            item,
            code: 'WAI_QUEUE_RECOVERY_FAILED',
            text:
                'Сохранённое сообщение найдено, но сейчас его не удалось безопасно восстановить. Оно не было отправлено автоматически.',
          ),
        );
      }
    }

    _queuedTurns.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    if (recoveryMessages.isNotEmpty) {
      state = state.copyWith(
        messages: <WesiAiMessage>[...state.messages, ...recoveryMessages],
      );
      await _save();
    } else {
      _notify();
    }
    if (_queuedTurns.isNotEmpty) unawaited(_drainQueuedTurns());
  }

  WesiAiMessage _recoveryError(
    WesiAiPendingQueueItem item, {
    required String code,
    required String text,
  }) {
    final at = DateTime.now();
    final clean = item.text.trim();
    final preview = clean.length <= 180 ? clean : '${clean.substring(0, 180)}…';
    final visibleText =
        preview.isEmpty ? text : '$text\n\nВосстановленный запрос: «$preview»';
    final metadata = <String, dynamic>{
      'code': code,
      'recoverText': item.text,
      'pendingQueueId': item.id,
      if (item.attachments.isNotEmpty) 'attachments': item.attachments,
    };
    return WesiAiMessage(
      id: '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
      conversationId: item.conversationId,
      employeeId: store.employeeId,
      author: WesiAiMessageAuthor.system,
      kind: WesiAiMessageKind.error,
      text: visibleText,
      createdAt: at,
      metadata: metadata,
    );
  }

  Future<void> _appendLocalSubmissionError(
    String conversationId, {
    required String code,
    required String text,
  }) async {
    final at = DateTime.now();
    state = state.copyWith(
      messages: <WesiAiMessage>[
        ...state.messages,
        WesiAiMessage(
          id: '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
          conversationId: conversationId,
          employeeId: store.employeeId,
          author: WesiAiMessageAuthor.system,
          kind: WesiAiMessageKind.error,
          text: text,
          createdAt: at,
          metadata: <String, dynamic>{'code': code},
        ),
      ],
    );
    await _save();
  }

  Future<void> _appendQueueItemError(String conversationId) async {
    final at = DateTime.now();
    state = state.copyWith(
      messages: <WesiAiMessage>[
        ...state.messages,
        WesiAiMessage(
          id: '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
          conversationId: conversationId,
          employeeId: store.employeeId,
          author: WesiAiMessageAuthor.system,
          kind: WesiAiMessageKind.error,
          text:
              'Не удалось обработать одно из сообщений. Остальная очередь продолжает выполняться.',
          createdAt: at,
          metadata: const <String, dynamic>{
            'code': 'WAI_MESSAGE_QUEUE_ITEM_FAILED',
          },
        ),
      ],
    );
    await _save();
  }

  Future<void> _appendQueueFullError(String conversationId) async {
    final at = DateTime.now();
    state = state.copyWith(
      messages: <WesiAiMessage>[
        ...state.messages,
        WesiAiMessage(
          id: '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
          conversationId: conversationId,
          employeeId: store.employeeId,
          author: WesiAiMessageAuthor.system,
          kind: WesiAiMessageKind.error,
          text:
              'Очередь сообщений заполнена. Дождитесь обработки одного из ожидающих сообщений.',
          createdAt: at,
          metadata: const <String, dynamic>{'code': 'WAI_MESSAGE_QUEUE_FULL'},
        ),
      ],
    );
    await _save();
  }

  @override
  Future<void> createConversation(WesiAiPersona persona) async {
    final projectId = state.activeProjectId;
    await super.createConversation(persona);
    final id = state.activeConversationId;
    if (id == null || projectId == null) return;
    state = state.copyWith(
      conversations: state.conversations
          .map((conversation) => conversation.id == id
              ? conversation.copyWith(projectId: projectId)
              : conversation)
          .toList(growable: false),
    );
    await _save();
  }

  Future<String?> createProject(
    String title, {
    String description = '',
    String instructions = '',
  }) async {
    final clean = title.trim();
    if (processing || clean.isEmpty || clean.length > 120) return null;
    final now = DateTime.now();
    final id =
        'project_${now.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
    final project = WesiAiProject(
      id: id,
      employeeId: store.employeeId,
      title: clean,
      description:
          description.trim().substring(0, min(description.trim().length, 2000)),
      instructions: instructions
          .trim()
          .substring(0, min(instructions.trim().length, 8000)),
      createdAt: now,
      updatedAt: now,
    );
    state = state.copyWith(
      projects: <WesiAiProject>[project, ...state.projects],
      activeProjectId: id,
      clearActiveConversation: true,
    );
    await _save();
    return id;
  }

  Future<void> selectProject(String? id) async {
    if (processing) return;
    if (id != null &&
        !state.projects
            .any((project) => project.id == id && !project.archived)) {
      return;
    }
    final active = state.activeConversation;
    final keepConversation =
        active != null && active.projectId == id && !active.archived;
    state = state.copyWith(
      activeProjectId: id,
      clearActiveProject: id == null,
      activeConversationId: keepConversation ? active.id : null,
      clearActiveConversation: !keepConversation,
    );
    await _save();
  }

  Future<void> renameProject(String id, String title) async {
    final clean = title.trim();
    if (processing || clean.isEmpty || clean.length > 120) return;
    var changed = false;
    final now = DateTime.now();
    final projects = state.projects.map((project) {
      if (project.id != id || project.employeeId != store.employeeId) {
        return project;
      }
      changed = true;
      return project.copyWith(title: clean, updatedAt: now);
    }).toList(growable: false);
    if (!changed) return;
    state = state.copyWith(projects: projects);
    await _save();
  }

  Future<void> updateProjectContext(
    String id, {
    required String description,
    required String instructions,
  }) async {
    if (processing) return;
    final cleanDescription = description.trim();
    final cleanInstructions = instructions.trim();
    if (cleanDescription.length > 2000 || cleanInstructions.length > 8000) {
      return;
    }
    var changed = false;
    final projects = state.projects.map((project) {
      if (project.id != id || project.employeeId != store.employeeId) {
        return project;
      }
      changed = true;
      return project.copyWith(
        description: cleanDescription,
        instructions: cleanInstructions,
        updatedAt: DateTime.now(),
      );
    }).toList(growable: false);
    if (!changed) return;
    state = state.copyWith(projects: projects);
    await _save();
  }

  Future<void> toggleProjectPinned(String id) async {
    if (processing) return;
    var changed = false;
    final projects = state.projects.map((project) {
      if (project.id != id || project.employeeId != store.employeeId) {
        return project;
      }
      changed = true;
      return project.copyWith(
        pinned: !project.pinned,
        updatedAt: DateTime.now(),
      );
    }).toList(growable: false);
    if (!changed) return;
    state = state.copyWith(projects: projects);
    await _save();
  }

  Future<void> deleteProject(String id) async {
    if (processing) return;
    if (!state.projects.any(
      (project) => project.id == id && project.employeeId == store.employeeId,
    )) {
      return;
    }
    final projects = state.projects
        .where((project) => project.id != id)
        .toList(growable: false);
    final conversations = state.conversations
        .map((conversation) => conversation.projectId == id
            ? conversation.copyWith(clearProject: true)
            : conversation)
        .toList(growable: false);
    final wasActive = state.activeProjectId == id;
    state = state.copyWith(
      projects: projects,
      conversations: conversations,
      clearActiveProject: wasActive,
      clearActiveConversation: wasActive,
    );
    await _save();
  }

  Future<void> moveConversationToProject(
    String conversationId,
    String? projectId,
  ) async {
    if (processing) return;
    if (projectId != null &&
        !state.projects.any(
          (project) => project.id == projectId && !project.archived,
        )) {
      return;
    }
    var changed = false;
    final conversations = state.conversations.map((conversation) {
      if (conversation.id != conversationId ||
          conversation.employeeId != store.employeeId) {
        return conversation;
      }
      changed = true;
      return conversation.copyWith(
        projectId: projectId,
        clearProject: projectId == null,
        updatedAt: DateTime.now(),
      );
    }).toList(growable: false);
    if (!changed) return;
    final movingActive = state.activeConversationId == conversationId;
    state = state.copyWith(
      conversations: conversations,
      activeProjectId: movingActive ? projectId : null,
      clearActiveProject: movingActive && projectId == null,
    );
    await _save();
  }

  Future<void> renameConversation(String id, String title) async {
    final clean = title.trim();
    if (processing || clean.isEmpty || clean.length > 120) return;
    var found = false;
    final conversations = state.conversations.map((conversation) {
      if (conversation.id != id ||
          conversation.employeeId != store.employeeId) {
        return conversation;
      }
      found = true;
      return conversation.copyWith(title: clean, updatedAt: DateTime.now());
    }).toList();
    if (!found) return;
    state = state.copyWith(conversations: conversations);
    await _save();
  }

  Future<void> togglePinned(String id) async {
    if (processing) return;
    var found = false;
    final conversations = state.conversations.map((conversation) {
      if (conversation.id != id ||
          conversation.employeeId != store.employeeId) {
        return conversation;
      }
      found = true;
      return conversation.copyWith(
        pinned: !conversation.pinned,
        updatedAt: DateTime.now(),
      );
    }).toList();
    if (!found) return;
    conversations.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    state = state.copyWith(conversations: conversations);
    await _save();
  }

  Future<void> archiveConversation(String id) async {
    if (processing) return;
    var found = false;
    final conversations = state.conversations.map((conversation) {
      if (conversation.id != id ||
          conversation.employeeId != store.employeeId) {
        return conversation;
      }
      found = true;
      return conversation.copyWith(
        archived: true,
        updatedAt: DateTime.now(),
      );
    }).toList();
    if (!found) return;
    final next = conversations
        .where((c) =>
            !c.archived && c.id != id && c.projectId == state.activeProjectId)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = state.copyWith(
      conversations: conversations,
      activeConversationId: state.activeConversationId == id && next.isNotEmpty
          ? next.first.id
          : null,
      clearActiveConversation: state.activeConversationId == id && next.isEmpty,
    );
    await _save();
  }

  Future<void> restoreConversation(String id) async {
    if (processing) return;
    WesiAiConversation? restored;
    final conversations = state.conversations.map((conversation) {
      if (conversation.id != id ||
          conversation.employeeId != store.employeeId) {
        return conversation;
      }
      restored = conversation.copyWith(
        archived: false,
        updatedAt: DateTime.now(),
      );
      return restored!;
    }).toList();
    if (restored == null) return;
    state = state.copyWith(
      conversations: conversations,
      activeProjectId: restored!.projectId,
      clearActiveProject: restored!.projectId == null,
      activeConversationId: id,
    );
    await _save();
  }

  Future<void> deleteConversation(String id) async {
    if (processing) return;
    if (!state.conversations.any(
      (c) => c.id == id && c.employeeId == store.employeeId,
    )) {
      return;
    }
    _queuedTurns.removeWhere((turn) => turn.conversationId == id);
    try {
      await store.removePendingQueueForConversation(id);
    } catch (_) {}
    final deletedMessageIds = state.messages
        .where((message) => message.conversationId == id)
        .map((message) => message.id)
        .toSet();
    for (final messageId in deletedMessageIds) {
      _attachmentRetries.remove(messageId);
    }
    final conversations = state.conversations.where((c) => c.id != id).toList();
    final messages =
        state.messages.where((m) => m.conversationId != id).toList();
    final next = conversations
        .where((c) => !c.archived && c.projectId == state.activeProjectId)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final activeWasDeleted = state.activeConversationId == id;
    state = state.copyWith(
      conversations: conversations,
      messages: messages,
      activeConversationId:
          activeWasDeleted && next.isNotEmpty ? next.first.id : null,
      clearActiveConversation: activeWasDeleted && next.isEmpty,
    );
    await _save();
  }

  Future<void> clearLastError() async {
    if (processing) return;
    final conversation = state.activeConversation;
    if (conversation == null) return;
    final messages = state.messagesFor(conversation.id);
    if (messages.isEmpty || messages.last.kind != WesiAiMessageKind.error) {
      return;
    }
    final errorId = messages.last.id;
    state = state.copyWith(
      messages:
          state.messages.where((message) => message.id != errorId).toList(),
    );
    await _save();
  }

  Future<void> regenerateLastResponse() async {
    if (processing) return;
    final conversation = state.activeConversation;
    if (conversation == null) return;
    final ordered = state.messagesFor(conversation.id);
    if (ordered.isNotEmpty && ordered.last.kind == WesiAiMessageKind.error) {
      final lastError = ordered.last;
      final code = '${lastError.metadata['code'] ?? ''}';
      if (code == 'WAI_REATTACH_REQUIRED' ||
          code == 'WAI_QUEUE_PERSISTENCE_FAILED') {
        return;
      }
      if (code == 'WAI_QUEUE_RECOVERY_UNCERTAIN' ||
          code == 'WAI_QUEUE_RECOVERY_FAILED') {
        final prompt = '${lastError.metadata['recoverText'] ?? ''}'.trim();
        if (prompt.isEmpty) return;
        final pendingQueueId =
            '${lastError.metadata['pendingQueueId'] ?? ''}'.trim();
        if (pendingQueueId.isNotEmpty) {
          try {
            await store.removePendingQueueItem(pendingQueueId);
          } catch (_) {}
        }
        state = state.copyWith(
          messages: state.messages
              .where((message) => message.id != lastError.id)
              .toList(growable: false),
        );
        await _save();
        await addUserMessage(prompt);
        return;
      }
    }
    var userIndex = -1;
    for (var i = ordered.length - 1; i >= 0; i--) {
      if (ordered[i].author == WesiAiMessageAuthor.user) {
        userIndex = i;
        break;
      }
    }
    if (userIndex < 0) return;
    final user = ordered[userIndex];
    final rawAttachments = user.metadata['attachments'];
    final hadAttachments = rawAttachments is List && rawAttachments.isNotEmpty;
    final retry = _attachmentRetries[user.id];
    if (hadAttachments && retry == null) {
      final at = DateTime.now();
      state = state.copyWith(
        messages: <WesiAiMessage>[
          ...state.messages,
          WesiAiMessage(
            id: '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
            conversationId: conversation.id,
            employeeId: store.employeeId,
            author: WesiAiMessageAuthor.system,
            kind: WesiAiMessageKind.error,
            text:
                'Для повторной отправки прикрепите исходный файл заново. WesiOS намеренно не хранит байты и локальные пути вложений в истории чата.',
            createdAt: at,
            metadata: const <String, dynamic>{'code': 'WAI_REATTACH_REQUIRED'},
          ),
        ],
      );
      await _save();
      return;
    }

    final prompt = retry?.prompt ?? user.text.trim();
    if (prompt.isEmpty && !hadAttachments) return;
    final removeIds = ordered.sublist(userIndex).map((m) => m.id).toSet();
    _attachmentRetries.remove(user.id);
    state = state.copyWith(
      messages: state.messages
          .where((message) => !removeIds.contains(message.id))
          .toList(),
    );
    await _save();
    await addUserMessage(
      prompt,
      attachments: retry?.attachments ?? const <WesiAiAttachment>[],
    );
  }

  List<WesiAiProject> get visibleProjects {
    final items = state.projects.where((project) => !project.archived).toList();
    items.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return items;
  }

  List<WesiAiConversation> get visibleConversations {
    final items = state.conversations
        .where((c) => !c.archived && c.projectId == state.activeProjectId)
        .toList();
    items.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return items;
  }

  List<WesiAiConversation> get archivedConversations {
    final items = state.conversations
        .where((c) => c.archived && c.projectId == state.activeProjectId)
        .toList();
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  Future<void> _save() async {
    await store.save(state);
    _notify();
  }
}
