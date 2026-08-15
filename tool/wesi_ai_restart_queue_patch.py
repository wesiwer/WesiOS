from pathlib import Path
import re


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one anchor, got {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


def sub_once(path: str, pattern: str, replacement: str, *, flags: int = 0) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    next_text, count = re.subn(pattern, lambda _: replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"{path}: regex anchor mismatch: {pattern[:80]!r} ({count})")
    p.write_text(next_text, encoding="utf-8")


# ---------------------------------------------------------------------------
# Durable per-turn queue records in the existing employee-scoped Hive box.
# No attachment bytes or local paths are persisted here.
# ---------------------------------------------------------------------------
store_path = "lib/features/ai/storage/wesi_ai_local_store.dart"
pending_types = r'''enum WesiAiPendingQueueStatus { queued, inflight, completed }

class WesiAiPendingQueueItem {
  final String id;
  final String employeeId;
  final String conversationId;
  final String text;
  final DateTime queuedAt;
  final String processSessionId;
  final WesiAiPendingQueueStatus status;
  final List<Map<String, dynamic>> attachments;

  const WesiAiPendingQueueItem({
    required this.id,
    required this.employeeId,
    required this.conversationId,
    required this.text,
    required this.queuedAt,
    required this.processSessionId,
    required this.status,
    this.attachments = const <Map<String, dynamic>>[],
  });

  WesiAiPendingQueueItem copyWith({
    String? processSessionId,
    WesiAiPendingQueueStatus? status,
  }) =>
      WesiAiPendingQueueItem(
        id: id,
        employeeId: employeeId,
        conversationId: conversationId,
        text: text,
        queuedAt: queuedAt,
        processSessionId: processSessionId ?? this.processSessionId,
        status: status ?? this.status,
        attachments: attachments,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'id': id,
        'employeeId': employeeId,
        'conversationId': conversationId,
        'text': text,
        'queuedAt': queuedAt.toUtc().toIso8601String(),
        'processSessionId': processSessionId,
        'status': status.name,
        if (attachments.isNotEmpty) 'attachments': attachments,
      };

  factory WesiAiPendingQueueItem.fromJson(
    Map<String, dynamic> json, {
    required String expectedEmployeeId,
  }) {
    final id = '${json['id'] ?? ''}'.trim();
    final employeeId = '${json['employeeId'] ?? ''}'.trim();
    final conversationId = '${json['conversationId'] ?? ''}'.trim();
    final text = '${json['text'] ?? ''}';
    final processSessionId = '${json['processSessionId'] ?? ''}'.trim();
    final queuedAt = DateTime.tryParse('${json['queuedAt'] ?? ''}');
    if (!RegExp(r'^[A-Za-z0-9_-]{8,180}$').hasMatch(id) ||
        employeeId != expectedEmployeeId ||
        conversationId.isEmpty ||
        conversationId.length > 180 ||
        text.length > 32000 ||
        processSessionId.isEmpty ||
        processSessionId.length > 180 ||
        queuedAt == null) {
      throw const FormatException('Invalid Wesi AI pending queue item');
    }

    WesiAiPendingQueueStatus? status;
    final rawStatus = '${json['status'] ?? ''}';
    for (final candidate in WesiAiPendingQueueStatus.values) {
      if (candidate.name == rawStatus) {
        status = candidate;
        break;
      }
    }
    if (status == null) {
      throw const FormatException('Invalid Wesi AI pending queue status');
    }

    final attachments = <Map<String, dynamic>>[];
    final rawAttachments = json['attachments'];
    if (rawAttachments is List) {
      if (rawAttachments.length > 4) {
        throw const FormatException('Too many pending attachment records');
      }
      for (final raw in rawAttachments) {
        if (raw is! Map) {
          throw const FormatException('Invalid pending attachment record');
        }
        final map = Map<String, dynamic>.from(raw);
        final name = '${map['name'] ?? ''}'.trim();
        final mimeType = '${map['mimeType'] ?? ''}'.trim();
        final byteSize = map['byteSize'];
        if (name.isEmpty ||
            name.length > 180 ||
            mimeType.isEmpty ||
            mimeType.length > 120 ||
            byteSize is! int ||
            byteSize <= 0 ||
            byteSize > 256 * 1024 * 1024) {
          throw const FormatException('Invalid pending attachment metadata');
        }
        attachments.add(<String, dynamic>{
          'name': name,
          'mimeType': mimeType,
          'byteSize': byteSize,
        });
      }
    }

    return WesiAiPendingQueueItem(
      id: id,
      employeeId: employeeId,
      conversationId: conversationId,
      text: text,
      queuedAt: queuedAt.toLocal(),
      processSessionId: processSessionId,
      status: status,
      attachments: List<Map<String, dynamic>>.unmodifiable(attachments),
    );
  }
}

'''
replace_once(store_path, "class WesiAiLocalStore {\n", pending_types + "class WesiAiLocalStore {\n")
replace_once(
    store_path,
    "  String get _stateKey => 'employee:$employeeId';\n  String get _corruptBackupKey => 'employee:$employeeId:corrupt-backup';\n",
    "  String get _stateKey => 'employee:$employeeId';\n  String get _corruptBackupKey => 'employee:$employeeId:corrupt-backup';\n  String get _pendingQueuePrefix => 'employee:$employeeId:pending-queue:';\n",
)
pending_methods = r'''  Future<List<WesiAiPendingQueueItem>> loadPendingQueueItems() async {
    final box = await _box();
    final result = <WesiAiPendingQueueItem>[];
    final corruptKeys = <String>[];
    for (final rawKey in box.keys) {
      final key = '$rawKey';
      if (!key.startsWith(_pendingQueuePrefix)) continue;
      final raw = box.get(key);
      if (raw == null || raw.trim().isEmpty) {
        corruptKeys.add(key);
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) throw const FormatException('Pending item is not an object');
        final item = WesiAiPendingQueueItem.fromJson(
          Map<String, dynamic>.from(decoded),
          expectedEmployeeId: employeeId,
        );
        if (key != '$_pendingQueuePrefix${item.id}') {
          throw const FormatException('Pending item key mismatch');
        }
        result.add(item);
      } catch (_) {
        corruptKeys.add(key);
      }
    }
    for (final key in corruptKeys) {
      try {
        await box.delete(key);
      } catch (_) {}
    }
    result.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return result;
  }

  Future<void> savePendingQueueItem(WesiAiPendingQueueItem item) async {
    if (item.employeeId != employeeId) throw StateError('Employee mismatch');
    final box = await _box();
    await box.put('$_pendingQueuePrefix${item.id}', jsonEncode(item.toJson()));
  }

  Future<void> removePendingQueueItem(String id) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{8,180}$').hasMatch(id)) return;
    final box = await _box();
    await box.delete('$_pendingQueuePrefix$id');
  }

  Future<void> removePendingQueueForConversation(String conversationId) async {
    final items = await loadPendingQueueItems();
    for (final item in items) {
      if (item.conversationId == conversationId) {
        await removePendingQueueItem(item.id);
      }
    }
  }

'''
replace_once(
    store_path,
    "  static String namespaceFor(String employeeId) => 'employee:$employeeId';\n",
    pending_methods + "  static String namespaceFor(String employeeId) => 'employee:$employeeId';\n",
)


# ---------------------------------------------------------------------------
# Managed queue: durable accept + safe recovery semantics.
# ---------------------------------------------------------------------------
managed_path = "lib/features/ai/wesi_ai_managed_controller.dart"
queued_turn = r'''class WesiAiQueuedTurn {
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
'''
sub_once(
    managed_path,
    r"class WesiAiQueuedTurn \{.*?\n\}\n\nenum WesiAiMessageSubmitResult",
    queued_turn + "\nenum WesiAiMessageSubmitResult",
    flags=re.S,
)
replace_once(
    managed_path,
    "enum WesiAiMessageSubmitResult {\n  accepted,\n  queueFull,\n  invalidAttachments,\n  unavailable,\n}\n",
    "enum WesiAiMessageSubmitResult {\n  accepted,\n  queueFull,\n  invalidAttachments,\n  persistenceFailed,\n  unavailable,\n}\n",
)
replace_once(
    managed_path,
    "class WesiAiManagedChatController extends WesiAiLobbyChatController {\n  static const int maxQueuedTurns = 12;\n\n",
    "class WesiAiManagedChatController extends WesiAiLobbyChatController {\n  static const int maxQueuedTurns = 12;\n  static final String _runtimeQueueSessionId =\n      'runtime_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';\n\n",
)
replace_once(
    managed_path,
    "  final List<WesiAiQueuedTurn> _queuedTurns = <WesiAiQueuedTurn>[];\n  bool _drainingQueue = false;\n",
    "  final List<WesiAiQueuedTurn> _queuedTurns = <WesiAiQueuedTurn>[];\n  final String _queueSessionId;\n  bool _drainingQueue = false;\n",
)
replace_once(
    managed_path,
    "  WesiAiManagedChatController({\n    required WesiAiLocalStore store,\n    WesiAiApi api = const WesiAiLobbyApi(),\n  }) : super(store: store, api: api);\n",
    "  WesiAiManagedChatController({\n    required WesiAiLocalStore store,\n    WesiAiApi api = const WesiAiLobbyApi(),\n    String? processSessionId,\n  })  : _queueSessionId = processSessionId ?? _runtimeQueueSessionId,\n        super(store: store, api: api);\n",
)

submit_and_helpers = r'''  void _notify() => notifyIfActive();

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
'''
sub_once(
    managed_path,
    r"  void _notify\(\) => notifyIfActive\(\);\n\n  WesiAiMessageSubmitResult submitUserMessage\(.*?\n  @override\n  Future<void> addUserMessage\(\n",
    submit_and_helpers,
    flags=re.S,
)

add_user = r'''  @override
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
'''
sub_once(
    managed_path,
    r"  @override\n  Future<void> addUserMessage\(.*?\n  Future<void> _sendNow\(\n",
    add_user,
    flags=re.S,
)

drain_and_recovery = r'''  Future<void> _drainQueuedTurns() async {
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
      text: text,
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
'''
sub_once(
    managed_path,
    r"  Future<void> _drainQueuedTurns\(\) async \{.*?\n  Future<void> _appendQueueItemError\(String conversationId\) async \{\n",
    drain_and_recovery,
    flags=re.S,
)

# Clean durable records if a conversation is explicitly deleted.
replace_once(
    managed_path,
    "    _queuedTurns.removeWhere((turn) => turn.conversationId == id);\n    final deletedMessageIds = state.messages\n",
    "    _queuedTurns.removeWhere((turn) => turn.conversationId == id);\n    try {\n      await store.removePendingQueueForConversation(id);\n    } catch (_) {}\n    final deletedMessageIds = state.messages\n",
)


# ---------------------------------------------------------------------------
# UI: accepted is now asynchronous/durable; do not offer generic replay for
# uncertain/re-attach recovery errors.
# ---------------------------------------------------------------------------
ui_path = "lib/features/ai/ai_assistant_v2_screen.dart"
replace_once(
    ui_path,
    "    final result = controller.submitUserMessage(\n      text,\n      attachments: attachments,\n    );\n    if (result != WesiAiMessageSubmitResult.accepted) {\n      if (!mounted) return;\n",
    "    final result = await controller.submitUserMessage(\n      text,\n      attachments: attachments,\n    );\n    if (!mounted) return;\n    if (result != WesiAiMessageSubmitResult.accepted) {\n",
)
replace_once(
    ui_path,
    "        WesiAiMessageSubmitResult.invalidAttachments =>\n          'Не удалось отправить сообщение: проверьте вложения.',\n        WesiAiMessageSubmitResult.unavailable =>\n",
    "        WesiAiMessageSubmitResult.invalidAttachments =>\n          'Не удалось отправить сообщение: проверьте вложения.',\n        WesiAiMessageSubmitResult.persistenceFailed =>\n          'Не удалось надёжно сохранить сообщение. Текст оставлен в поле ввода.',\n        WesiAiMessageSubmitResult.unavailable =>\n",
)
replace_once(
    ui_path,
    "    final hasLastError =\n        messages.isNotEmpty && messages.last.kind == WesiAiMessageKind.error;\n    return Column(\n",
    "    final hasLastError =\n        messages.isNotEmpty && messages.last.kind == WesiAiMessageKind.error;\n    final lastErrorCode =\n        hasLastError ? '${messages.last.metadata['code'] ?? ''}' : '';\n    final canRegenerateLastResponse = hasLastError &&\n        !lastErrorCode.startsWith('WAI_QUEUE_RECOVERY_') &&\n        lastErrorCode != 'WAI_REATTACH_REQUIRED' &&\n        lastErrorCode != 'WAI_QUEUE_PERSISTENCE_FAILED';\n    return Column(\n",
)
replace_once(
    ui_path,
    "                FilledButton.tonalIcon(\n                  onPressed: controller.regenerateLastResponse,\n                  icon: const Icon(Icons.refresh),\n                  label: const Text('Повторить ответ'),\n                ),\n",
    "                if (canRegenerateLastResponse)\n                  FilledButton.tonalIcon(\n                    onPressed: controller.regenerateLastResponse,\n                    icon: const Icon(Icons.refresh),\n                    label: const Text('Повторить ответ'),\n                  ),\n",
)


# ---------------------------------------------------------------------------
# Keep interaction specification aligned with the reliability contract.
# ---------------------------------------------------------------------------
spec_path = Path("docs/WESI_AI_CHAT_INTERACTION_SPEC.md")
if spec_path.exists():
    spec = spec_path.read_text(encoding="utf-8")
    marker = "## Надёжность очереди после перезапуска"
    if marker not in spec:
        spec += r'''

## Надёжность очереди после перезапуска

- UI очищает composer только после того, как pending turn надёжно записан в локальное employee-scoped хранилище.
- Текстовый turn со статусом `queued` автоматически восстанавливается после настоящего перезапуска процесса и продолжает FIFO.
- Turn со статусом `inflight` после перезапуска **не** отправляется повторно автоматически: результат мог уже вызвать внешние действия, поэтому WesiOS показывает `WAI_QUEUE_RECOVERY_UNCERTAIN` и оставляет решение о повторе пользователю.
- Для queued turn с вложениями сохраняются только безопасные metadata (имя/MIME/размер). Bytes, Base64 и локальные пути не сохраняются. После перезапуска WesiOS показывает `WAI_REATTACH_REQUIRED` и просит прикрепить исходные файлы заново.
- Второй controller в том же процессе не перехватывает durable queue первого controller: process-session ownership защищает от двойной отправки при закрытии и повторном открытии экрана.
'''
        spec_path.write_text(spec, encoding="utf-8")
