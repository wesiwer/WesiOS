from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one match, got {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")

chat = "lib/features/ai/controllers/wesi_ai_chat_controller.dart"
replace_once(
    chat,
    """    state = await store.load();
    loading = false;
    notifyListeners();
""",
    """    state = await store.load();
    loading = false;
    notifyIfActive();
""",
)
replace_once(
    chat,
    """  Future<void> _persist() async {
    await store.save(state);
    if (!_disposed) notifyListeners();
  }
""",
    """  @protected
  void notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _persist() async {
    await store.save(state);
    notifyIfActive();
  }
""",
)

lobby = "lib/features/ai/wesi_ai_lobby_controller.dart"
replace_once(
    lobby,
    """  Future<void> _save() async {
    await store.save(state);
    notifyListeners();
  }
""",
    """  Future<void> _save() async {
    await store.save(state);
    notifyIfActive();
  }
""",
)

handoff = "lib/features/ai/wesi_ai_handoff_controller.dart"
replace_once(
    handoff,
    """    await store.save(state);
    notifyListeners();
    return newId;
""",
    """    await store.save(state);
    notifyIfActive();
    return newId;
""",
)

managed = "lib/features/ai/wesi_ai_managed_controller.dart"
replace_once(
    managed,
    """  final List<WesiAiQueuedTurn> _queuedTurns = <WesiAiQueuedTurn>[];
  bool _drainingQueue = false;
  bool _managedDisposed = false;
""",
    """  final List<WesiAiQueuedTurn> _queuedTurns = <WesiAiQueuedTurn>[];
  bool _drainingQueue = false;
""",
)
replace_once(
    managed,
    """  void _notify() {
    if (!_managedDisposed) notifyListeners();
  }
""",
    """  void _notify() => notifyIfActive();
""",
)
replace_once(
    managed,
    """  @override
  void dispose() {
    _managedDisposed = true;
    super.dispose();
  }

  Future<void> _save() async {
""",
    """  Future<void> _save() async {
""",
)

test = Path("test/wesi_ai_queue_hardening_test.dart")
text = test.read_text(encoding="utf-8")
insert_class_before = "\nFuture<void> _waitUntil(bool Function() condition) async {\n"
if text.count(insert_class_before) != 1:
    raise SystemExit("test class insertion anchor mismatch")
lobby_api = r'''

class _LobbyControlledApi extends WesiAiApi {
  final Completer<WesiAiReply> reply = Completer<WesiAiReply>();
  int calls = 0;

  @override
  Future<WesiAiReply> send({
    required WesiAiConversation conversation,
    required WesiAiTier tier,
    required String message,
    required List<WesiAiMessage> history,
    required WesiAiMemorySnapshot memory,
    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
  }) {
    calls++;
    return reply.future;
  }
}
'''
text = text.replace(insert_class_before, lobby_api + insert_class_before, 1)
anchor = "\n}\n"
pos = text.rfind(anchor)
if pos < 0:
    raise SystemExit("test main closing brace not found")
extra = r'''

  test('lobby completion after dispose never notifies disposed listeners', () async {
    final api = _LobbyControlledApi();
    final store = _MemoryStore('employee-1');
    final controller = WesiAiManagedChatController(store: store, api: api);
    await controller.load();
    await controller.createConversation(WesiAiPersona.lobby);

    final sending = controller.addUserMessage('проверь lobby lifecycle');
    await _waitUntil(() => api.calls == 1);
    controller.dispose();
    api.reply.complete(
      const WesiAiReply(
        answer:
            '__WESI_LOBBY_V1__[{"author":"zane","text":"Готово"}]',
        requestId: 'lobby-dispose-1',
      ),
    );

    await sending;
    expect(
      store.saved!.messages.any(
        (message) =>
            message.author == WesiAiMessageAuthor.zane &&
            message.text == 'Готово',
      ),
      isTrue,
    );
  });
'''
text = text[:pos] + extra + text[pos:]
test.write_text(text, encoding="utf-8")
