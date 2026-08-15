from pathlib import Path
import re
import subprocess


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"missing patch anchor: {label}")
    return text.replace(old, new, 1)


def main_file(path: str) -> str:
    return subprocess.check_output(
        ["git", "show", f"origin/main:{path}"], text=True
    )


# Keep the newest owner-approved specs while preserving the durable-outbox detail.
chat_spec = main_file("docs/WESI_AI_CHAT_INTERACTION_SPEC.md")
chat_spec += """

## 4. Restart-safe local outbox

До появления отдельного server-owned Job Engine обычный чат использует durable local outbox:

- accepted turn считается принятым только после записи в employee-scoped Hive;
- text-only deferred/steer turn восстанавливается после настоящего restart процесса;
- uncertain inflight turn не переотправляется автоматически, чтобы не продублировать возможные side effects;
- после restart для ещё не переданных серверу файлов сохраняются только metadata, поэтому требуется reattach;
- второй controller того же процесса не должен перехватывать очередь первого;
- CONTROL/STEER сохраняют приоритет над восстановленными deferred turns;
- эта local-outbox семантика не означает перенос тяжёлого L3/L4 выполнения на основной VPS: тяжёлые jobs подчиняются Foreground / Background Execution Policy.
"""
Path("docs/WESI_AI_CHAT_INTERACTION_SPEC.md").write_text(chat_spec, encoding="utf-8")
Path("docs/WESI_AI_ADAPTIVE_EXECUTION_SPEC.md").write_text(
    main_file("docs/WESI_AI_ADAPTIVE_EXECUTION_SPEC.md"), encoding="utf-8"
)

# Durable outbox stores intent so restart recovery preserves smart priority.
p = Path("lib/features/ai/storage/wesi_ai_local_store.dart")
s = p.read_text(encoding="utf-8")
s = replace_once(
    s,
    "  final WesiAiPendingQueueStatus status;\n  final List<Map<String, dynamic>> attachments;",
    "  final WesiAiPendingQueueStatus status;\n  final String intent;\n  final List<Map<String, dynamic>> attachments;",
    "pending intent field",
)
s = replace_once(
    s,
    "    required this.status,\n    this.attachments = const <Map<String, dynamic>>[],",
    "    required this.status,\n    this.intent = 'deferred',\n    this.attachments = const <Map<String, dynamic>>[],",
    "pending intent ctor",
)
s = replace_once(
    s,
    "    WesiAiPendingQueueStatus? status,\n  }) =>",
    "    WesiAiPendingQueueStatus? status,\n    String? intent,\n  }) =>",
    "pending intent copy signature",
)
s = replace_once(
    s,
    "        status: status ?? this.status,\n        attachments: attachments,",
    "        status: status ?? this.status,\n        intent: intent ?? this.intent,\n        attachments: attachments,",
    "pending intent copy value",
)
s = replace_once(
    s,
    "        'status': status.name,\n        if (attachments.isNotEmpty) 'attachments': attachments,",
    "        'status': status.name,\n        'intent': intent,\n        if (attachments.isNotEmpty) 'attachments': attachments,",
    "pending intent json",
)
anchor = "    if (status == null) {\n      throw const FormatException('Invalid Wesi AI pending queue status');\n    }\n\n"
insert = anchor + "    final intent = '${json['intent'] ?? 'deferred'}'.trim();\n    if (!const <String>{'control', 'steer', 'deferred'}.contains(intent)) {\n      throw const FormatException('Invalid Wesi AI pending queue intent');\n    }\n\n"
s = replace_once(s, anchor, insert, "pending intent parse")
s = replace_once(
    s,
    "      status: status,\n      attachments: List<Map<String, dynamic>>.unmodifiable(attachments),",
    "      status: status,\n      intent: intent,\n      attachments: List<Map<String, dynamic>>.unmodifiable(attachments),",
    "pending intent return",
)
p.write_text(s, encoding="utf-8")

# Base controller gets cooperative interruption. A late provider result is ignored
# after CONTROL/STEER has won the race.
p = Path("lib/features/ai/controllers/wesi_ai_chat_controller.dart")
s = p.read_text(encoding="utf-8")
s = replace_once(
    s,
    "  bool _disposed = false;\n",
    "  bool _disposed = false;\n  Completer<void>? _activeTurnInterrupt;\n",
    "interrupt field",
)
pattern = re.compile(r"      final reply = await api\.send\((.*?)\n      \);", re.S)
m = pattern.search(s)
if not m:
    raise SystemExit("missing patch anchor: base api send")
body = m.group(1)
repl = (
    "      final reply = await awaitInterruptible(api.send("
    + body
    + "\n      ));\n      if (reply == null) return;"
)
s = s[: m.start()] + repl + s[m.end() :]
anchor = "  @protected\n  bool get isDisposed => _disposed;\n"
methods = """  bool interruptActiveTurn() {
    final signal = _activeTurnInterrupt;
    if (signal == null || signal.isCompleted) return false;
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
      return result.interrupted ? null : result.value;
    } finally {
      if (identical(_activeTurnInterrupt, signal)) {
        _activeTurnInterrupt = null;
      }
    }
  }

"""
s = replace_once(s, anchor, methods + anchor, "interrupt methods")
s = replace_once(
    s,
    "  void dispose() {\n    _disposed = true;",
    "  void dispose() {\n    interruptActiveTurn();\n    _disposed = true;",
    "interrupt on dispose",
)
p.write_text(s, encoding="utf-8")

# Lobby uses a separate request path and must obey the same preemption.
p = Path("lib/features/ai/wesi_ai_lobby_controller.dart")
s = p.read_text(encoding="utf-8")
pattern = re.compile(r"      final reply = await api\.send\((.*?)\n      \);", re.S)
m = pattern.search(s)
if not m:
    raise SystemExit("missing patch anchor: lobby api send")
body = m.group(1)
repl = (
    "      final reply = await awaitInterruptible(api.send("
    + body
    + "\n      ));\n      if (reply == null) return;"
)
s = s[: m.start()] + repl + s[m.end() :]
p.write_text(s, encoding="utf-8")

# Smart queue: CONTROL > STEER > DEFERRED.
p = Path("lib/features/ai/wesi_ai_managed_controller.dart")
s = p.read_text(encoding="utf-8")
s = replace_once(
    s,
    "import 'wesi_ai_lobby_controller.dart';\n",
    "import 'wesi_ai_lobby_controller.dart';\nimport 'wesi_ai_turn_intent.dart';\n",
    "intent import",
)
s = replace_once(
    s,
    "  final DateTime queuedAt;\n",
    "  final DateTime queuedAt;\n  final WesiAiTurnIntent intent;\n",
    "queued intent field",
)
s = replace_once(
    s,
    "    required this.queuedAt,\n  });",
    "    required this.queuedAt,\n    required this.intent,\n  });",
    "queued intent ctor",
)
s = replace_once(
    s,
    "  String get preview {\n",
    "  String get intentLabel => switch (intent) {\n        WesiAiTurnIntent.control => 'Стоп',\n        WesiAiTurnIntent.steer => 'Корректировка',\n        WesiAiTurnIntent.deferred => 'Потом',\n      };\n\n  String get preview {\n",
    "queued intent label",
)
old = """  Future<WesiAiMessageSubmitResult> submitUserMessage(
    String text, {
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
  }) =>
      _acceptTurn(text, attachments: attachments, startDrain: true);
"""
new = """  Future<WesiAiMessageSubmitResult> submitUserMessage(
    String text, {
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
  }) {
    final intent = WesiAiTurnIntentClassifier.classify(
      text,
      hasActiveWork: processing,
    );
    return _acceptTurn(
      text,
      attachments: attachments,
      startDrain: true,
      intent: intent,
    );
  }

  Future<WesiAiMessageSubmitResult> stopActiveWork() {
    final conversation = state.activeConversation;
    if (conversation == null || !processing) {
      return Future.value(WesiAiMessageSubmitResult.unavailable);
    }
    return _applyControl(conversation, 'Стой');
  }
"""
s = replace_once(s, old, new, "submit classify")
s = replace_once(
    s,
    "    required bool startDrain,\n  }) async {\n    if (_acceptingTurn) return WesiAiMessageSubmitResult.unavailable;",
    "    required bool startDrain,\n    required WesiAiTurnIntent intent,\n  }) async {\n    if (_acceptingTurn && intent != WesiAiTurnIntent.control) {\n      return WesiAiMessageSubmitResult.unavailable;\n    }",
    "accept intent signature",
)
old = """    if (_queuedTurns.length >= maxQueuedTurns) {
      return WesiAiMessageSubmitResult.queueFull;
    }

    _acceptingTurn = true;"""
new = """    if (intent == WesiAiTurnIntent.control) {
      return _applyControl(conversation, clean);
    }
    if (intent == WesiAiTurnIntent.steer) {
      interruptActiveTurn();
      if (WesiAiTurnIntentClassifier.invalidatesDeferred(clean)) {
        await _supersedeQueuedTurns(
          conversation.id,
          includeSteer: false,
          reason: 'correction',
        );
      }
    }
    if (_queuedTurns.length >= maxQueuedTurns) {
      if (intent != WesiAiTurnIntent.steer ||
          !await _makeRoomForPriorityTurn(conversation.id)) {
        return WesiAiMessageSubmitResult.queueFull;
      }
    }

    _acceptingTurn = true;"""
s = replace_once(s, old, new, "priority acceptance")
s = replace_once(
    s,
    "      queuedAt: queuedAt,\n    );",
    "      queuedAt: queuedAt,\n      intent: intent,\n    );",
    "turn intent assignment",
)
s = replace_once(
    s,
    "    _queuedTurns.add(turn);\n",
    "    if (intent == WesiAiTurnIntent.steer) {\n      _queuedTurns.insert(0, turn);\n    } else {\n      _queuedTurns.add(turn);\n    }\n",
    "priority insertion",
)
s = replace_once(
    s,
    "        status: status,\n        attachments: turn.attachments",
    "        status: status,\n        intent: turn.intent.name,\n        attachments: turn.attachments",
    "persist queue intent",
)
old = """    final conversation = state.activeConversation;
    final result = await _acceptTurn(
      text,
      attachments: attachments,
      startDrain: false,
    );"""
new = """    final conversation = state.activeConversation;
    final intent = WesiAiTurnIntentClassifier.classify(
      text,
      hasActiveWork: processing,
    );
    final result = await _acceptTurn(
      text,
      attachments: attachments,
      startDrain: false,
      intent: intent,
    );"""
s = replace_once(s, old, new, "legacy add intent")
helper_anchor = "  Future<void> _sendNow(\n"
helpers = """  WesiAiTurnIntent _intentFromName(String raw) {
    for (final value in WesiAiTurnIntent.values) {
      if (value.name == raw) return value;
    }
    return WesiAiTurnIntent.deferred;
  }

  Future<WesiAiMessageSubmitResult> _applyControl(
    WesiAiConversation conversation,
    String text,
  ) async {
    interruptActiveTurn();
    await _supersedeQueuedTurns(
      conversation.id,
      includeSteer: true,
      reason: 'control',
    );
    final at = DateTime.now();
    state = state.copyWith(
      messages: <WesiAiMessage>[
        ...state.messages,
        WesiAiMessage(
          id: '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
          conversationId: conversation.id,
          employeeId: store.employeeId,
          author: WesiAiMessageAuthor.user,
          text: text.trim().isEmpty ? 'Стой' : text.trim(),
          createdAt: at,
          metadata: const <String, dynamic>{
            'turnIntent': 'control',
            'turnState': 'applied',
          },
        ),
        WesiAiMessage(
          id: '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}_stop',
          conversationId: conversation.id,
          employeeId: store.employeeId,
          author: WesiAiMessageAuthor.system,
          kind: WesiAiMessageKind.status,
          text: 'Текущая работа остановлена. Новые шаги старого плана не запускаются.',
          createdAt: at.add(const Duration(microseconds: 1)),
          metadata: const <String, dynamic>{
            'code': 'WAI_CONTROL_APPLIED',
            'turnIntent': 'control',
            'turnState': 'cancelled',
          },
        ),
      ],
    );
    await _save();
    return WesiAiMessageSubmitResult.accepted;
  }

  Future<void> _supersedeQueuedTurns(
    String conversationId, {
    required bool includeSteer,
    required String reason,
  }) async {
    final removed = _queuedTurns
        .where((turn) =>
            turn.conversationId == conversationId &&
            (includeSteer || turn.intent == WesiAiTurnIntent.deferred))
        .toList(growable: false);
    if (removed.isEmpty) return;
    final ids = removed.map((turn) => turn.id).toSet();
    _queuedTurns.removeWhere((turn) => ids.contains(turn.id));
    for (final turn in removed) {
      try {
        await store.removePendingQueueItem(turn.id);
      } catch (_) {}
    }
    final at = DateTime.now();
    state = state.copyWith(
      messages: <WesiAiMessage>[
        ...state.messages,
        WesiAiMessage(
          id: '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
          conversationId: conversationId,
          employeeId: store.employeeId,
          author: WesiAiMessageAuthor.system,
          kind: WesiAiMessageKind.status,
          text: 'Неактуальные ожидающие сообщения сняты с выполнения: ${removed.length}.',
          createdAt: at,
          metadata: <String, dynamic>{
            'code': 'WAI_QUEUE_SUPERSEDED',
            'turnState': 'superseded',
            'reason': reason,
            'count': removed.length,
          },
        ),
      ],
    );
    await _save();
  }

  Future<bool> _makeRoomForPriorityTurn(String conversationId) async {
    for (var index = _queuedTurns.length - 1; index >= 0; index--) {
      final turn = _queuedTurns[index];
      if (turn.conversationId != conversationId ||
          turn.intent != WesiAiTurnIntent.deferred) {
        continue;
      }
      _queuedTurns.removeAt(index);
      try {
        await store.removePendingQueueItem(turn.id);
      } catch (_) {}
      return true;
    }
    return false;
  }

"""
s = replace_once(s, helper_anchor, helpers + helper_anchor, "smart queue helpers")
s = replace_once(
    s,
    "            queuedAt: item.queuedAt,\n          ),",
    "            queuedAt: item.queuedAt,\n            intent: _intentFromName(item.intent),\n          ),",
    "recover intent",
)
p.write_text(s, encoding="utf-8")

# UI shows intent and exposes Stop while a turn is running.
p = Path("lib/features/ai/ai_assistant_v2_screen.dart")
s = p.read_text(encoding="utf-8")
s = replace_once(
    s,
    ".map((turn) => turn.preview)\n                                  .join(' · '),",
    ".map((turn) => '${turn.intentLabel}: ${turn.preview}')\n                                  .join(' · '),",
    "queue intent preview",
)
s = replace_once(
    s,
    "                        hintText: controller.sending\n                            ? 'Дополните запрос — сообщение встанет в очередь'\n                            : 'Спроси Wesi AI о чём угодно',",
    "                        hintText: controller.sending\n                            ? 'Можно написать «Стой», исправление или следующий запрос'\n                            : 'Спроси Wesi AI о чём угодно',",
    "smart composer hint",
)
anchor = """                        const Spacer(),
                        if (controller.sending ||
                            controller.queuedTurnCount > 0)"""
replacement = """                        const Spacer(),
                        if (controller.sending)
                          IconButton(
                            tooltip: 'Остановить текущую работу',
                            onPressed: () => unawaited(controller.stopActiveWork()),
                            icon: const Icon(Icons.stop_circle_outlined),
                          ),
                        if (controller.sending ||
                            controller.queuedTurnCount > 0)"""
s = replace_once(s, anchor, replacement, "stop button")
p.write_text(s, encoding="utf-8")

# Integration regressions.
p = Path("test/wesi_ai_queue_hardening_test.dart")
s = p.read_text(encoding="utf-8")
insert_at = s.rfind("\n}")
if insert_at < 0:
    raise SystemExit("missing test suite closing brace")
tests = r'''

  test('steer correction preempts active reply and runs before deferred work', () async {
    final api = _ControlledApi();
    final controller = await _controller(api);

    expect(
      await controller.submitUserMessage('проверь весь проект'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => api.prompts.length == 1);

    expect(
      await controller.submitUserMessage('После этого проверь Windows build'),
      WesiAiMessageSubmitResult.accepted,
    );
    expect(
      await controller.submitUserMessage(
        'Нет, не весь проект, проверяй только Android build',
      ),
      WesiAiMessageSubmitResult.accepted,
    );

    await _waitUntil(() => api.prompts.length >= 2);
    expect(api.prompts[1], 'Нет, не весь проект, проверяй только Android build');
    expect(api.prompts, isNot(contains('После этого проверь Windows build')));

    api.first.complete(
      const WesiAiReply(answer: 'устаревший ответ', requestId: 'old-request'),
    );
    await _waitUntil(() => !controller.processing);
    expect(
      controller.state.messages.any((message) => message.text == 'устаревший ответ'),
      isFalse,
    );
    expect(
      controller.state.messages.any(
        (message) => message.metadata['code'] == 'WAI_QUEUE_SUPERSEDED',
      ),
      isTrue,
    );
  });

  test('text control stops active work and cancels queued follow-ups', () async {
    final api = _ControlledApi();
    final controller = await _controller(api);

    expect(
      await controller.submitUserMessage('сделай аудит'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => api.prompts.length == 1);
    expect(
      await controller.submitUserMessage('После этого собери Windows'),
      WesiAiMessageSubmitResult.accepted,
    );
    expect(
      await controller.submitUserMessage('стой'),
      WesiAiMessageSubmitResult.accepted,
    );

    await _waitUntil(() => !controller.processing);
    expect(api.prompts, <String>['сделай аудит']);
    expect(
      controller.state.messages.any(
        (message) => message.metadata['code'] == 'WAI_CONTROL_APPLIED',
      ),
      isTrue,
    );
    expect(controller.queuedTurnCount, 0);

    api.first.complete(
      const WesiAiReply(answer: 'поздний ответ', requestId: 'late-request'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      controller.state.messages.any((message) => message.text == 'поздний ответ'),
      isFalse,
    );
  });
'''
s = s[:insert_at] + tests + s[insert_at:]
p.write_text(s, encoding="utf-8")
