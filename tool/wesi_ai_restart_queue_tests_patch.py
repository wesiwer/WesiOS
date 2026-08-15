from pathlib import Path

path = Path("test/wesi_ai_queue_hardening_test.dart")
text = path.read_text(encoding="utf-8")

old_store = '''class _MemoryStore extends WesiAiLocalStore {
  WesiAiLocalState? saved;

  _MemoryStore(String employeeId) : super(employeeId);

  @override
  Future<WesiAiLocalState> load() async =>
      saved ?? WesiAiLocalState.empty(employeeId);

  @override
  Future<void> save(WesiAiLocalState state) async {
    saved = state;
  }
}
'''
new_store = '''class _MemoryStore extends WesiAiLocalStore {
  WesiAiLocalState? saved;
  final Map<String, WesiAiPendingQueueItem> pending =
      <String, WesiAiPendingQueueItem>{};
  bool failPendingWrites = false;

  _MemoryStore(String employeeId) : super(employeeId);

  @override
  Future<WesiAiLocalState> load() async =>
      saved ?? WesiAiLocalState.empty(employeeId);

  @override
  Future<void> save(WesiAiLocalState state) async {
    saved = state;
  }

  @override
  Future<List<WesiAiPendingQueueItem>> loadPendingQueueItems() async {
    final result = pending.values.toList(growable: false);
    result.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return result;
  }

  @override
  Future<void> savePendingQueueItem(WesiAiPendingQueueItem item) async {
    if (failPendingWrites) throw StateError('synthetic pending write failure');
    pending[item.id] = item;
  }

  @override
  Future<void> removePendingQueueItem(String id) async {
    pending.remove(id);
  }

  @override
  Future<void> removePendingQueueForConversation(String conversationId) async {
    pending.removeWhere((_, item) => item.conversationId == conversationId);
  }
}
'''
if text.count(old_store) != 1:
    raise SystemExit("_MemoryStore anchor mismatch")
text = text.replace(old_store, new_store, 1)

# submitUserMessage is intentionally Future-based now: accepted is returned only
# after the durable pending record has been written.
text = text.replace(
    "controller.submitUserMessage(",
    "await controller.submitUserMessage(",
)

insert_at = text.rfind("\n}")
if insert_at < 0:
    raise SystemExit("main closing brace not found")

extra = r'''

  test('durable accept fails closed when pending storage cannot be written', () async {
    final api = _ControlledApi();
    final store = _MemoryStore('employee-1');
    final controller = WesiAiManagedChatController(
      store: store,
      api: api,
      processSessionId: 'storage-failure-session',
    );
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);
    store.failPendingWrites = true;

    expect(
      await controller.submitUserMessage('do not lose me'),
      WesiAiMessageSubmitResult.persistenceFailed,
    );
    expect(controller.queuedTurnCount, 0);
    expect(api.prompts, isEmpty);
  });

  test('queued text resumes after a real process-session restart', () async {
    final store = _MemoryStore('employee-1');
    final apiA = _ControlledApi();
    final controllerA = WesiAiManagedChatController(
      store: store,
      api: apiA,
      processSessionId: 'process-a',
    );
    await controllerA.load();
    await controllerA.createConversation(WesiAiPersona.zane);
    final conversationId = controllerA.state.activeConversationId!;

    expect(
      await controllerA.submitUserMessage('uncertain-inflight'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => apiA.prompts.length == 1);
    expect(
      await controllerA.submitUserMessage('resume-after-restart'),
      WesiAiMessageSubmitResult.accepted,
    );
    expect(
      store.pending.values.any(
        (item) =>
            item.text == 'uncertain-inflight' &&
            item.status == WesiAiPendingQueueStatus.inflight,
      ),
      isTrue,
    );
    expect(
      store.pending.values.any(
        (item) =>
            item.text == 'resume-after-restart' &&
            item.status == WesiAiPendingQueueStatus.queued,
      ),
      isTrue,
    );

    // Simulate the old UI disappearing and then a brand-new process session.
    // The old in-flight future deliberately never completes.
    controllerA.dispose();
    final apiB = _ControlledApi();
    final controllerB = WesiAiManagedChatController(
      store: store,
      api: apiB,
      processSessionId: 'process-b',
    );
    await controllerB.load();
    await _waitUntil(() => apiB.prompts.length == 1);

    expect(apiB.prompts, <String>['resume-after-restart']);
    expect(
      controllerB.state.messagesFor(conversationId).any(
        (message) =>
            message.metadata['code'] == 'WAI_QUEUE_RECOVERY_UNCERTAIN' &&
            message.metadata['recoverText'] == 'uncertain-inflight',
      ),
      isTrue,
    );

    apiB.first.complete(
      const WesiAiReply(
        answer: 'reply:resume-after-restart',
        requestId: 'restart-1',
      ),
    );
    await _waitUntil(() => !controllerB.processing);
    expect(store.pending, isEmpty);
    expect(
      controllerB.state.messagesFor(conversationId).any(
        (message) =>
            message.author == WesiAiMessageAuthor.zane &&
            message.text == 'reply:resume-after-restart',
      ),
      isTrue,
    );
  });

  test('queued attachment survives as reattach intent, never as stored bytes', () async {
    final store = _MemoryStore('employee-1');
    final apiA = _ControlledApi();
    final controllerA = WesiAiManagedChatController(
      store: store,
      api: apiA,
      processSessionId: 'attachment-process-a',
    );
    await controllerA.load();
    await controllerA.createConversation(WesiAiPersona.nirvana);
    final conversationId = controllerA.state.activeConversationId!;

    expect(
      await controllerA.submitUserMessage('block-first'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => apiA.prompts.length == 1);
    final attachment = WesiAiAttachment.fromBytes(
      name: 'restart-context.txt',
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
    );
    expect(
      await controllerA.submitUserMessage(
        'use this after restart',
        attachments: <WesiAiAttachment>[attachment],
      ),
      WesiAiMessageSubmitResult.accepted,
    );

    final queuedAttachment = store.pending.values.firstWhere(
      (item) => item.text == 'use this after restart',
    );
    expect(queuedAttachment.attachments, hasLength(1));
    expect(
      queuedAttachment.attachments.single.keys.toSet(),
      <String>{'name', 'mimeType', 'byteSize'},
    );
    expect(
      queuedAttachment.attachments.single.containsKey('dataBase64'),
      isFalse,
    );
    expect(
      queuedAttachment.attachments.single.containsKey('localPath'),
      isFalse,
    );

    controllerA.dispose();
    final apiB = _ControlledApi();
    final controllerB = WesiAiManagedChatController(
      store: store,
      api: apiB,
      processSessionId: 'attachment-process-b',
    );
    await controllerB.load();

    expect(apiB.prompts, isEmpty);
    expect(store.pending, isEmpty);
    final messages = controllerB.state.messagesFor(conversationId);
    expect(
      messages.any(
        (message) =>
            message.metadata['code'] == 'WAI_REATTACH_REQUIRED' &&
            message.metadata['recoverText'] == 'use this after restart' &&
            message.text.contains('restart-context.txt'),
      ),
      isTrue,
    );
  });

  test('same process session never steals or duplicates another controller queue', () async {
    final store = _MemoryStore('employee-1');
    final apiA = _ControlledApi();
    final controllerA = WesiAiManagedChatController(
      store: store,
      api: apiA,
      processSessionId: 'same-runtime',
    );
    await controllerA.load();
    await controllerA.createConversation(WesiAiPersona.zane);

    expect(
      await controllerA.submitUserMessage('first-owned'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => apiA.prompts.length == 1);
    expect(
      await controllerA.submitUserMessage('second-owned'),
      WesiAiMessageSubmitResult.accepted,
    );
    controllerA.dispose();

    final apiB = _ControlledApi();
    final controllerB = WesiAiManagedChatController(
      store: store,
      api: apiB,
      processSessionId: 'same-runtime',
    );
    await controllerB.load();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(apiB.prompts, isEmpty);
    expect(controllerB.queuedTurnCount, 0);
    expect(store.pending.length, 2);

    apiA.first.complete(
      const WesiAiReply(answer: 'reply:first-owned', requestId: 'owner-1'),
    );
    await _waitUntil(() => store.pending.isEmpty);
    expect(apiA.prompts, <String>['first-owned', 'second-owned']);
    expect(apiB.prompts, isEmpty);
  });
'''

text = text[:insert_at] + extra + text[insert_at:]
path.write_text(text, encoding="utf-8")
