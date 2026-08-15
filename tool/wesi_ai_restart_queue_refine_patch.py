from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one anchor, got {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")

ui = "lib/features/ai/ai_assistant_v2_screen.dart"
replace_once(
    ui,
    """    final text = _composer.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    final attachments = List<WesiAiAttachment>.from(_attachments);
    final result = await controller.submitUserMessage(
""",
    """    final composerSnapshot = _composer.text;
    final text = composerSnapshot.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    final attachments = List<WesiAiAttachment>.from(_attachments);
    final result = await controller.submitUserMessage(
""",
)
replace_once(
    ui,
    """    _composer.clear();
    _voicePrefix = '';
    _voice.clearTranscript();
    setState(() => _attachments.clear());
""",
    """    if (_composer.text == composerSnapshot) {
      _composer.clear();
      _voicePrefix = '';
      _voice.clearTranscript();
    }
    setState(() {
      _attachments.removeWhere((item) => attachments.contains(item));
    });
""",
)
replace_once(
    ui,
    """    final canRegenerateLastResponse = hasLastError &&
        !lastErrorCode.startsWith('WAI_QUEUE_RECOVERY_') &&
        lastErrorCode != 'WAI_REATTACH_REQUIRED' &&
        lastErrorCode != 'WAI_QUEUE_PERSISTENCE_FAILED';
""",
    """    final canRegenerateLastResponse = hasLastError &&
        lastErrorCode != 'WAI_REATTACH_REQUIRED' &&
        lastErrorCode != 'WAI_QUEUE_PERSISTENCE_FAILED';
""",
)

managed = "lib/features/ai/wesi_ai_managed_controller.dart"
replace_once(
    managed,
    """  WesiAiMessage _recoveryError(
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
""",
    """  WesiAiMessage _recoveryError(
    WesiAiPendingQueueItem item, {
    required String code,
    required String text,
  }) {
    final at = DateTime.now();
    final clean = item.text.trim();
    final preview = clean.length <= 180
        ? clean
        : '${clean.substring(0, 180)}…';
    final visibleText = preview.isEmpty
        ? text
        : '$text\\n\\nВосстановленный запрос: «$preview»';
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
""",
)
replace_once(
    managed,
    """  Future<void> regenerateLastResponse() async {
    if (processing) return;
    final conversation = state.activeConversation;
    if (conversation == null) return;
    final ordered = state.messagesFor(conversation.id);
    var userIndex = -1;
""",
    """  Future<void> regenerateLastResponse() async {
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
""",
)

# Extend recovery tests with visible prompt and explicit manual retry.
test = Path("test/wesi_ai_queue_hardening_test.dart")
text = test.read_text(encoding="utf-8")
old = """    expect(
      controllerB.state.messagesFor(conversationId).any(
            (message) =>
                message.metadata['code'] == 'WAI_QUEUE_RECOVERY_UNCERTAIN' &&
                message.metadata['recoverText'] == 'uncertain-inflight',
          ),
      isTrue,
    );
"""
new = """    expect(
      controllerB.state.messagesFor(conversationId).any(
            (message) =>
                message.metadata['code'] == 'WAI_QUEUE_RECOVERY_UNCERTAIN' &&
                message.metadata['recoverText'] == 'uncertain-inflight' &&
                message.text.contains('uncertain-inflight'),
          ),
      isTrue,
    );
"""
if text.count(old) != 1:
    raise SystemExit("restart uncertainty test anchor mismatch")
text = text.replace(old, new, 1)
insert_at = text.rfind("\n}")
if insert_at < 0:
    raise SystemExit("test main closing brace not found")
extra = r'''

  test('uncertain recovery can be explicitly retried without automatic replay', () async {
    final store = _MemoryStore('employee-1');
    final apiA = _ControlledApi();
    final controllerA = WesiAiManagedChatController(
      store: store,
      api: apiA,
      processSessionId: 'manual-retry-a',
    );
    await controllerA.load();
    await controllerA.createConversation(WesiAiPersona.zane);
    final conversationId = controllerA.state.activeConversationId!;

    expect(
      await controllerA.submitUserMessage('manual retry payload'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => apiA.prompts.length == 1);
    controllerA.dispose();

    final apiB = _ControlledApi();
    final controllerB = WesiAiManagedChatController(
      store: store,
      api: apiB,
      processSessionId: 'manual-retry-b',
    );
    await controllerB.load();
    expect(apiB.prompts, isEmpty);
    expect(
      controllerB.state.messagesFor(conversationId).last.metadata['code'],
      'WAI_QUEUE_RECOVERY_UNCERTAIN',
    );
    expect(
      controllerB.state.messagesFor(conversationId).last.text,
      contains('manual retry payload'),
    );

    final retry = controllerB.regenerateLastResponse();
    await _waitUntil(() => apiB.prompts.length == 1);
    expect(apiB.prompts.single, 'manual retry payload');
    apiB.first.complete(
      const WesiAiReply(
        answer: 'reply:manual retry payload',
        requestId: 'manual-retry-1',
      ),
    );
    await retry;
    await _waitUntil(() => !controllerB.processing);
    expect(store.pending, isEmpty);
    expect(
      controllerB.state.messagesFor(conversationId).any(
            (message) =>
                message.author == WesiAiMessageAuthor.zane &&
                message.text == 'reply:manual retry payload',
          ),
      isTrue,
    );
  });
'''
text = text[:insert_at] + extra + text[insert_at:]
test.write_text(text, encoding="utf-8")
