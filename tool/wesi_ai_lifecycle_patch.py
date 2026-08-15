from pathlib import Path

def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one match, got {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")

managed = Path("lib/features/ai/wesi_ai_managed_controller.dart")
text = managed.read_text(encoding="utf-8")

old = """  final List<WesiAiQueuedTurn> _queuedTurns = <WesiAiQueuedTurn>[];
  bool _drainingQueue = false;
"""
new = """  final List<WesiAiQueuedTurn> _queuedTurns = <WesiAiQueuedTurn>[];
  bool _drainingQueue = false;
  bool _managedDisposed = false;
"""
if text.count(old) != 1:
    raise SystemExit(f"{managed}: managed disposed anchor mismatch")
text = text.replace(old, new, 1)

existing_notify_count = text.count("notifyListeners();")
if existing_notify_count < 4:
    raise SystemExit(f"{managed}: expected managed notifications, got {existing_notify_count}")
text = text.replace("notifyListeners();", "_notify();")

old = """  bool get processing => sending || _drainingQueue || _queuedTurns.isNotEmpty;

  WesiAiMessageSubmitResult submitUserMessage(
"""
new = """  bool get processing => sending || _drainingQueue || _queuedTurns.isNotEmpty;

  void _notify() {
    if (!_managedDisposed) notifyListeners();
  }

  WesiAiMessageSubmitResult submitUserMessage(
"""
if text.count(old) != 1:
    raise SystemExit(f"{managed}: notify helper anchor mismatch")
text = text.replace(old, new, 1)

old = """  Future<void> _save() async {
    await store.save(state);
    _notify();
  }
}
"""
new = """  @override
  void dispose() {
    _managedDisposed = true;
    super.dispose();
  }

  Future<void> _save() async {
    await store.save(state);
    _notify();
  }
}
"""
if text.count(old) != 1:
    raise SystemExit(f"{managed}: dispose anchor mismatch")
text = text.replace(old, new, 1)
managed.write_text(text, encoding="utf-8")

ui = "lib/features/ai/ai_assistant_v2_screen.dart"
replace_once(
    ui,
    """                          onPressed:
                              controller.sending || _session?.active == true
                                  ? null
                                  : _toggleVoice,
""",
    """                          onPressed:
                              controller.processing || _session?.active == true
                                  ? null
                                  : _toggleVoice,
""",
)
replace_once(
    ui,
    """                          onPressed: controller.sending
                              ? null
                              : () => _toggleConversation(controller),
""",
    """                          onPressed: controller.processing
                              ? null
                              : () => _toggleConversation(controller),
""",
)

test_file = Path("test/wesi_ai_queue_hardening_test.dart")
test_text = test_file.read_text(encoding="utf-8")
anchor = "\n}\n"
pos = test_text.rfind(anchor)
if pos < 0:
    raise SystemExit(f"{test_file}: main closing brace not found")
extra = r"""

  test('disposing screen controller does not interrupt accepted queue', () async {
    final api = _ControlledApi();
    final store = _MemoryStore('employee-1');
    final controller = WesiAiManagedChatController(
      store: store,
      api: api,
    );
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);
    final conversationId = controller.state.activeConversationId!;

    expect(
      controller.submitUserMessage('before-close'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => api.prompts.length == 1);
    expect(
      controller.submitUserMessage('queued-before-close'),
      WesiAiMessageSubmitResult.accepted,
    );

    controller.dispose();
    api.first.complete(
      const WesiAiReply(answer: 'reply:before-close', requestId: 'request-1'),
    );

    await _waitUntil(() {
      final saved = store.saved;
      if (saved == null || api.prompts.length < 2) return false;
      return saved
          .messagesFor(conversationId)
          .any((message) => message.text == 'reply:queued-before-close');
    });

    expect(api.prompts, <String>['before-close', 'queued-before-close']);
    final saved = store.saved!;
    expect(
      saved
          .messagesFor(conversationId)
          .where((message) => message.author == WesiAiMessageAuthor.user)
          .map((message) => message.text),
      containsAll(<String>['before-close', 'queued-before-close']),
    );
  });
"""
test_text = test_text[:pos] + extra + test_text[pos:]
test_file.write_text(test_text, encoding="utf-8")
