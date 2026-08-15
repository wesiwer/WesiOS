from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one anchor, got {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")

managed = "lib/features/ai/wesi_ai_managed_controller.dart"
replace_once(
    managed,
    """  bool _drainingQueue = false;
  bool _waitingForSameProcessOwner = false;
""",
    """  bool _drainingQueue = false;
  bool _waitingForSameProcessOwner = false;
  bool _acceptingTurn = false;
""",
)
replace_once(
    managed,
    """      _drainingQueue ||
      _queuedTurns.isNotEmpty ||
      _waitingForSameProcessOwner;
""",
    """      _drainingQueue ||
      _queuedTurns.isNotEmpty ||
      _waitingForSameProcessOwner ||
      _acceptingTurn;
""",
)
replace_once(
    managed,
    """  }) async {
    final conversation = state.activeConversation;
    final clean = text.trim();
""",
    """  }) async {
    if (_acceptingTurn) return WesiAiMessageSubmitResult.unavailable;
    final conversation = state.activeConversation;
    final clean = text.trim();
""",
)
replace_once(
    managed,
    """    if (_queuedTurns.length >= maxQueuedTurns) {
      return WesiAiMessageSubmitResult.queueFull;
    }

    final queuedAt = DateTime.now();
""",
    """    if (_queuedTurns.length >= maxQueuedTurns) {
      return WesiAiMessageSubmitResult.queueFull;
    }

    _acceptingTurn = true;
    _notify();
    final queuedAt = DateTime.now();
""",
)
replace_once(
    managed,
    """    } catch (_) {
      _queuedTurns.removeWhere((candidate) => candidate.id == turn.id);
      _notify();
      return WesiAiMessageSubmitResult.persistenceFailed;
    }
    _notify();
    if (startDrain) unawaited(_drainQueuedTurns());
""",
    """    } catch (_) {
      _queuedTurns.removeWhere((candidate) => candidate.id == turn.id);
      _acceptingTurn = false;
      _notify();
      return WesiAiMessageSubmitResult.persistenceFailed;
    }
    _acceptingTurn = false;
    _notify();
    if (startDrain) unawaited(_drainQueuedTurns());
""",
)

test = "test/wesi_ai_queue_hardening_test.dart"
replace_once(
    test,
    """  bool failPendingWrites = false;

  _MemoryStore(String employeeId) : super(employeeId);
""",
    """  bool failPendingWrites = false;
  Completer<void>? pendingWriteGate;
  int pendingWriteCount = 0;

  _MemoryStore(String employeeId) : super(employeeId);
""",
)
replace_once(
    test,
    """  Future<void> savePendingQueueItem(WesiAiPendingQueueItem item) async {
    if (failPendingWrites) throw StateError('synthetic pending write failure');
    pending[item.id] = item;
  }
""",
    """  Future<void> savePendingQueueItem(WesiAiPendingQueueItem item) async {
    pendingWriteCount++;
    final gate = pendingWriteGate;
    if (pendingWriteCount == 1 && gate != null) await gate.future;
    if (failPendingWrites) throw StateError('synthetic pending write failure');
    pending[item.id] = item;
  }
""",
)

p = Path(test)
text = p.read_text(encoding="utf-8")
insert_at = text.rfind("\n}")
if insert_at < 0:
    raise SystemExit("test main closing brace not found")
extra = r'''

  test('durable acceptance serializes concurrent pending writes', () async {
    final api = _ControlledApi();
    final store = _MemoryStore('employee-1');
    store.pendingWriteGate = Completer<void>();
    final controller = WesiAiManagedChatController(
      store: store,
      api: api,
      processSessionId: 'accept-race-session',
    );
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);

    final first = controller.submitUserMessage('first durable write');
    await _waitUntil(() => store.pendingWriteCount == 1);
    expect(controller.processing, isTrue);
    expect(api.prompts, isEmpty);

    expect(
      await controller.submitUserMessage('second while first is saving'),
      WesiAiMessageSubmitResult.unavailable,
    );
    expect(controller.queuedTurnCount, 1);
    expect(store.pending, isEmpty);
    expect(api.prompts, isEmpty);

    store.pendingWriteGate!.complete();
    expect(await first, WesiAiMessageSubmitResult.accepted);
    await _waitUntil(() => api.prompts.length == 1);
    expect(api.prompts, <String>['first durable write']);

    api.first.complete(
      const WesiAiReply(
        answer: 'reply:first durable write',
        requestId: 'accept-race-1',
      ),
    );
    await _waitUntil(() => !controller.processing);
    expect(store.pending, isEmpty);
  });
'''
text = text[:insert_at] + extra + text[insert_at:]
p.write_text(text, encoding="utf-8")
