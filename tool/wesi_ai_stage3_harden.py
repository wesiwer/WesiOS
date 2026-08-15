from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'missing anchor: {label}')
    return text.replace(old, new, 1)


# Controller: injectable memory API and summary-aware history window.
p = Path('lib/features/ai/controllers/wesi_ai_chat_controller.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(s,
'''  final Set<String> _memoryRefreshes = <String>{};
  final WesiAiMemoryApi memoryApi = const WesiAiMemoryApi();
''',
'''  final Set<String> _memoryRefreshes = <String>{};
  final WesiAiMemoryApi memoryApi;
''', 'memory api field')
s = replace_once(s,
'''  WesiAiChatController({required this.store, this.api = const WesiAiApi()})
      : state = WesiAiLocalState.empty(store.employeeId);
''',
'''  WesiAiChatController({
    required this.store,
    this.api = const WesiAiApi(),
    this.memoryApi = const WesiAiMemoryApi(),
  }) : state = WesiAiLocalState.empty(store.employeeId);
''', 'memory api constructor')
s = replace_once(s,
'''    final history = state.messagesFor(c.id);
    final now = DateTime.now();
''',
'''    final fullHistory = state.messagesFor(c.id);
    final history = historyForMemoryRequest(c.id, fullHistory);
    final now = DateTime.now();
''', 'base summary history window')
anchor = '''  @protected
  WesiAiMemorySnapshot relevantMemoryFor(
'''
helper = r'''  @protected
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
    final start = memory.summarizedMessageCount
        .clamp(0, textMessages.length)
        .toInt();
    final unsummarized = textMessages.sublist(start);
    if (unsummarized.length <= 24) return unsummarized;
    return unsummarized.sublist(unsummarized.length - 24);
  }

'''
s = replace_once(s, anchor, helper + anchor, 'history helper')
old = '''      final relevant = relevantMemoryFor(conversation, latestUserText);
      final result = await memoryApi.process(
        conversation: conversation,
        recentMessages: textMessages,
        previousSummary: conversationMemory.rollingSummary,
        taskState: conversationMemory.taskState,
        memory: relevant,
        project: _projectFor(conversation.projectId),
      );
'''
new = '''      final start = conversationMemory.summarizedMessageCount
          .clamp(0, textMessages.length)
          .toInt();
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
'''
s = replace_once(s, old, new, 'bounded compaction batch')
s = replace_once(s,
'''        summarizedMessageCount: textMessages.length,
''',
'''        summarizedMessageCount: start + batch.length,
''', 'compaction watermark')
p.write_text(s, encoding='utf-8')

# Subclasses preserve optional injection and use same history window.
p = Path('lib/features/ai/wesi_ai_lobby_controller.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(s,
"import 'controllers/wesi_ai_chat_controller.dart';\n",
"import 'controllers/wesi_ai_chat_controller.dart';\nimport 'memory/wesi_ai_memory_api.dart';\n", 'lobby memory import')
s = replace_once(s,
'''  WesiAiLobbyChatController({
    required WesiAiLocalStore store,
    WesiAiApi api = const WesiAiLobbyApi(),
  }) : super(store: store, api: api);
''',
'''  WesiAiLobbyChatController({
    required WesiAiLocalStore store,
    WesiAiApi api = const WesiAiLobbyApi(),
    WesiAiMemoryApi memoryApi = const WesiAiMemoryApi(),
  }) : super(store: store, api: api, memoryApi: memoryApi);
''', 'lobby memory constructor')
s = replace_once(s,
'''    final history = state.messagesFor(conversation.id);
    final now = DateTime.now();
''',
'''    final fullHistory = state.messagesFor(conversation.id);
    final history = historyForMemoryRequest(conversation.id, fullHistory);
    final now = DateTime.now();
''', 'lobby history window')
p.write_text(s, encoding='utf-8')

p = Path('lib/features/ai/wesi_ai_managed_controller.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(s,
"import 'models/wesi_ai_attachment.dart';\n",
"import 'memory/wesi_ai_memory_api.dart';\nimport 'models/wesi_ai_attachment.dart';\n", 'managed memory import')
s = replace_once(s,
'''    WesiAiApi api = const WesiAiLobbyApi(),
    String? processSessionId,
  })  : _queueSessionId = processSessionId ?? _runtimeQueueSessionId,
        super(store: store, api: api);
''',
'''    WesiAiApi api = const WesiAiLobbyApi(),
    WesiAiMemoryApi memoryApi = const WesiAiMemoryApi(),
    String? processSessionId,
  })  : _queueSessionId = processSessionId ?? _runtimeQueueSessionId,
        super(store: store, api: api, memoryApi: memoryApi);
''', 'managed memory constructor')
p.write_text(s, encoding='utf-8')

# Transport context classes are distinct instead of mislabeled in summary.
p = Path('lib/features/ai/wesi_ai_api.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(s,
'''        'summary': contextPackage(project,
            conversationSummary: conversationSummary, taskState: taskState),
        'conversationId': conversation.id,
''',
'''        'summary': conversationSummary.trim(),
        'projectContext': projectContext(project),
        if (taskState.isNotEmpty) 'taskState': taskState,
        'conversationId': conversation.id,
''', 'chat context fields')
p.write_text(s, encoding='utf-8')

p = Path('lib/features/ai/wesi_ai_lobby_api.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(s,
'''      'summary': WesiAiApi.projectContext(project),
      'conversationId': conversation.id,
''',
'''      'summary': conversationSummary.trim(),
      'projectContext': WesiAiApi.projectContext(project),
      if (taskState.isNotEmpty) 'taskState': taskState,
      'conversationId': conversation.id,
''', 'lobby context fields')
p.write_text(s, encoding='utf-8')

# Direct Main route.
p = Path('server/pb_hooks/wesi_ai_routes.pb.js')
s = p.read_text(encoding='utf-8')
s = replace_once(s,
'''  const summary = String(body.summary || "").trim();
  const activeOrganizationId = String(body.activeOrganizationId || "").trim();
''',
'''  const summary = String(body.summary || "").trim();
  const projectContext = String(body.projectContext || "").trim();
  const taskState = body.taskState && typeof body.taskState === "object" && !Array.isArray(body.taskState) ? body.taskState : {};
  const activeOrganizationId = String(body.activeOrganizationId || "").trim();
''', 'direct context read')
s = replace_once(s,
'''  if (summary.length > 64000 || history.length > 100) throw new BadRequestError("Слишком большой контекст Wesi AI");
''',
'''  let taskStateJson = "{}";
  try { taskStateJson = JSON.stringify(taskState); } catch (_) { throw new BadRequestError("Некорректный task state Wesi AI"); }
  if (summary.length > 64000 || projectContext.length > 64000 || taskStateJson.length > 12000 || history.length > 100) throw new BadRequestError("Слишком большой контекст Wesi AI");
''', 'direct context validation')
s = replace_once(s,
'''  if (summary) systemParts.push("[WESI_AI_CONVERSATION_SUMMARY]\\n" + summary);
  if (cleanMemory.shared.length) systemParts.push("[WESI_AI_SHARED_MEMORY]\\n" + cleanMemory.shared.join("\\n"));
''',
'''  if (summary) systemParts.push("[WESI_AI_CONVERSATION_SUMMARY]\\n" + summary);
  if (projectContext) systemParts.push("[WESI_AI_PROJECT_CONTEXT]\\n" + projectContext);
  if (taskStateJson !== "{}") systemParts.push("[WESI_AI_TASK_STATE]\\n" + taskStateJson);
  if (cleanMemory.shared.length) systemParts.push("[WESI_AI_SHARED_MEMORY]\\n" + cleanMemory.shared.join("\\n"));
''', 'direct context tags')
p.write_text(s, encoding='utf-8')

# Streaming Main prepare.
p = Path('server/pb_hooks/wesi_ai_stream.pb.js')
s = p.read_text(encoding='utf-8')
s = replace_once(s,
'''  const summary = String(body.summary || "").trim();
  const conversationId = String(body.conversationId || "").trim();
''',
'''  const summary = String(body.summary || "").trim();
  const projectContext = String(body.projectContext || "").trim();
  const taskState = body.taskState && typeof body.taskState === "object" && !Array.isArray(body.taskState) ? body.taskState : {};
  const conversationId = String(body.conversationId || "").trim();
''', 'stream context read')
s = replace_once(s,
'''  if (summary.length > 64000 || history.length > 100 || conversationId.length > 160) {
    throw new BadRequestError("Слишком большой контекст Wesi AI");
  }
''',
'''  let taskStateJson = "{}";
  try { taskStateJson = JSON.stringify(taskState); } catch (_) { throw new BadRequestError("Некорректный task state Wesi AI"); }
  if (summary.length > 64000 || projectContext.length > 64000 || taskStateJson.length > 12000 || history.length > 100 || conversationId.length > 160) {
    throw new BadRequestError("Слишком большой контекст Wesi AI");
  }
''', 'stream context validation')
s = replace_once(s,
'''  if (summary) systemParts.push("[WESI_AI_CONVERSATION_SUMMARY]\\n" + summary);
  if (cleanMemory.shared.length) systemParts.push("[WESI_AI_SHARED_MEMORY]\\n" + cleanMemory.shared.join("\\n"));
''',
'''  if (summary) systemParts.push("[WESI_AI_CONVERSATION_SUMMARY]\\n" + summary);
  if (projectContext) systemParts.push("[WESI_AI_PROJECT_CONTEXT]\\n" + projectContext);
  if (taskStateJson !== "{}") systemParts.push("[WESI_AI_TASK_STATE]\\n" + taskStateJson);
  if (cleanMemory.shared.length) systemParts.push("[WESI_AI_SHARED_MEMORY]\\n" + cleanMemory.shared.join("\\n"));
''', 'stream context tags')
p.write_text(s, encoding='utf-8')

# Lobby server route.
p = Path('server/pb_hooks/wesi_ai_lobby_core.js')
s = p.read_text(encoding='utf-8')
s = replace_once(s,
'''    const memory = ai.sanitizeMemory(body.memory && typeof body.memory === "object" ? body.memory : {});
    const rootId = "wai_lobby_" + Date.now() + "_" + $security.randomString(10);
''',
'''    const memory = ai.sanitizeMemory(body.memory && typeof body.memory === "object" ? body.memory : {});
    const projectContext = String(body.projectContext || "").trim();
    const taskState = body.taskState && typeof body.taskState === "object" && !Array.isArray(body.taskState) ? body.taskState : {};
    let taskStateJson = "{}";
    try { taskStateJson = JSON.stringify(taskState); } catch (_) { return {status: 400, body: {ok: false, code: "WAI_BAD_LOBBY_REQUEST"}}; }
    if (projectContext.length > 64000 || taskStateJson.length > 12000) return {status: 400, body: {ok: false, code: "WAI_BAD_LOBBY_REQUEST"}};
    const rootId = "wai_lobby_" + Date.now() + "_" + $security.randomString(10);
''', 'lobby context read')
s = replace_once(s,
'''      const result = turn.run(ai, cfg, route, rootId + "_" + name, name, profile, message, history, memory.shared, personaMemory, messages, String(body.summary || ""));
''',
'''      const result = turn.run(ai, cfg, route, rootId + "_" + name, name, profile, message, history, memory.shared, personaMemory, memory.project, messages, String(body.summary || ""), projectContext, taskStateJson);
''', 'lobby turn args')
p.write_text(s, encoding='utf-8')

p = Path('server/pb_hooks/wesi_ai_lobby_turn.js')
s = p.read_text(encoding='utf-8')
s = replace_once(s,
'''  run: function(ai, cfg, route, requestId, personaName, profile, message, history, sharedMemory, personaMemory, priorTurns, summary) {
    const parts = [profile.prompt, "[WESI_AI_LOBBY]\\nYou are in shared Lobby. Speak only as yourself; never write lines for the other participant."];
    if (summary) parts.push("[WESI_AI_CONVERSATION_SUMMARY]\\n" + summary);
    if (sharedMemory.length) parts.push("[WESI_AI_SHARED_MEMORY]\\n" + sharedMemory.join("\\n"));
    if (personaMemory.length) parts.push("[WESI_AI_PERSONA_MEMORY]\\n" + personaMemory.join("\\n"));
''',
'''  run: function(ai, cfg, route, requestId, personaName, profile, message, history, sharedMemory, personaMemory, projectMemory, priorTurns, summary, projectContext, taskStateJson) {
    const parts = [profile.prompt, "[WESI_AI_LOBBY]\\nYou are in shared Lobby. Speak only as yourself; never write lines for the other participant."];
    if (summary) parts.push("[WESI_AI_CONVERSATION_SUMMARY]\\n" + summary);
    if (projectContext) parts.push("[WESI_AI_PROJECT_CONTEXT]\\n" + projectContext);
    if (taskStateJson && taskStateJson !== "{}") parts.push("[WESI_AI_TASK_STATE]\\n" + taskStateJson);
    if (sharedMemory.length) parts.push("[WESI_AI_SHARED_MEMORY]\\n" + sharedMemory.join("\\n"));
    if (personaMemory.length) parts.push("[WESI_AI_PERSONA_MEMORY]\\n" + personaMemory.join("\\n"));
    if (projectMemory.length) parts.push("[WESI_AI_PROJECT_MEMORY]\\n" + projectMemory.join("\\n"));
''', 'lobby turn tags')
p.write_text(s, encoding='utf-8')

# Tests: memory processor success/failure + history window + bounded oldest-first compaction.
p = Path('test/wesi_ai_memory_engine_test.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(s,
"import 'package:flutter_test/flutter_test.dart';\n",
"import 'dart:async';\n\nimport 'package:flutter_test/flutter_test.dart';\nimport 'package:wesios/features/ai/controllers/wesi_ai_chat_controller.dart';\nimport 'package:wesios/features/ai/memory/wesi_ai_memory_api.dart';\n", 'test imports')
s = replace_once(s,
"import 'package:wesios/features/ai/models/wesi_ai_chat_models.dart';\n",
"import 'package:wesios/features/ai/models/wesi_ai_attachment.dart';\nimport 'package:wesios/features/ai/models/wesi_ai_chat_models.dart';\n", 'attachment import')
s = replace_once(s,
"import 'package:wesios/features/ai/storage/wesi_ai_local_store.dart';\n",
"import 'package:wesios/features/ai/storage/wesi_ai_local_store.dart';\nimport 'package:wesios/features/ai/wesi_ai_api.dart';\n", 'api import')
insert = r'''
class _MemoryStore extends WesiAiLocalStore {
  WesiAiLocalState? saved;
  _MemoryStore(super.employeeId);

  @override
  Future<WesiAiLocalState> load() async =>
      saved ?? WesiAiLocalState.empty(employeeId);

  @override
  Future<void> save(WesiAiLocalState state) async {
    saved = state;
  }
}

class _RecordingApi extends WesiAiApi {
  List<WesiAiMessage> history = const <WesiAiMessage>[];
  String summary = '';
  Map<String, dynamic> taskState = const <String, dynamic>{};

  @override
  Future<WesiAiReply> send({
    required WesiAiConversation conversation,
    required WesiAiTier tier,
    required String message,
    required List<WesiAiMessage> history,
    required WesiAiMemorySnapshot memory,
    WesiAiProject? project,
    String conversationSummary = '',
    Map<String, dynamic> taskState = const <String, dynamic>{},
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
    void Function(String delta)? onDelta,
    WesiAiRequestCancellation? cancellation,
  }) async {
    this.history = history;
    summary = conversationSummary;
    this.taskState = taskState;
    return const WesiAiReply(answer: 'Готово', requestId: 'memory-test');
  }
}

class _FakeMemoryApi extends WesiAiMemoryApi {
  final WesiAiMemoryProcessResult? result;
  final bool fail;
  int calls = 0;
  final List<List<String>> batches = <List<String>>[];

  _FakeMemoryApi({this.result, this.fail = false});

  @override
  Future<WesiAiMemoryProcessResult> process({
    required WesiAiConversation conversation,
    required List<WesiAiMessage> recentMessages,
    required String previousSummary,
    required Map<String, dynamic> taskState,
    required WesiAiMemorySnapshot memory,
    WesiAiProject? project,
  }) async {
    calls++;
    batches.add(recentMessages.map((message) => message.text).toList());
    if (fail) {
      throw const WesiAiApiException(
        'WAI_MEMORY_FAILED',
        'synthetic memory failure',
      );
    }
    return result ??
        const WesiAiMemoryProcessResult(
          summary: '',
          taskState: <String, dynamic>{},
          memories: <WesiAiMemoryCandidate>[],
        );
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for memory processing');
}

'''
s = replace_once(s, 'void main() {\n', insert + 'void main() {\n', 'test helpers')
end = s.rfind('\n}')
if end < 0: raise SystemExit('test closing brace missing')
extra = r'''

  test('manual memory controls persist locally and reject secret-like text', () async {
    final store = _MemoryStore('employee-controls');
    final controller = WesiAiChatController(
      store: store,
      api: _RecordingApi(),
      memoryApi: _FakeMemoryApi(),
    );
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);

    expect(
      await controller.addManualMemory(
        WesiAiMemoryScope.shared,
        'Предпочитает короткие отчёты',
      ),
      isTrue,
    );
    expect(controller.state.memoryEntries.length, 1);
    expect(
      await controller.addManualMemory(
        WesiAiMemoryScope.shared,
        'API key: secret-1234567890',
      ),
      isFalse,
    );
    await controller.setAutoMemoryEnabled(false);
    expect(controller.state.memorySettings.autoMemoryEnabled, isFalse);
    await controller.setActiveConversationMemoryEnabled(false);
    expect(
      controller.state
          .conversationMemory[controller.state.activeConversationId!]
          ?.memoryEnabled,
      isFalse,
    );
    await controller.deleteMemory(controller.state.memoryEntries.single.id);
    expect(controller.state.memoryEntries, isEmpty);
    expect(store.saved, isNotNull);
  });

  test('successful background processor applies summary task state and memory', () async {
    final store = _MemoryStore('employee-process');
    final memoryApi = _FakeMemoryApi(
      result: const WesiAiMemoryProcessResult(
        summary: 'Пользователь попросил запомнить настройку.',
        taskState: <String, dynamic>{'goal': 'держать настройку'},
        memories: <WesiAiMemoryCandidate>[
          WesiAiMemoryCandidate(
            scope: WesiAiMemoryScope.shared,
            text: 'Пользователь предпочитает режим Pro',
            importance: 0.9,
          ),
        ],
      ),
    );
    final controller = WesiAiChatController(
      store: store,
      api: _RecordingApi(),
      memoryApi: memoryApi,
    );
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);
    final conversationId = controller.state.activeConversationId!;

    await controller.addUserMessage('Запомни: я предпочитаю режим Pro');
    await _waitUntil(
      () => memoryApi.calls == 1 && controller.state.memoryEntries.isNotEmpty,
    );

    expect(
      controller.state.memoryEntries.single.text,
      'Пользователь предпочитает режим Pro',
    );
    expect(
      controller.state.conversationMemory[conversationId]?.rollingSummary,
      'Пользователь попросил запомнить настройку.',
    );
    expect(
      controller.state.conversationMemory[conversationId]?.taskState['goal'],
      'держать настройку',
    );
  });

  test('memory processor failure never turns a successful chat into an error', () async {
    final store = _MemoryStore('employee-failure');
    final memoryApi = _FakeMemoryApi(fail: true);
    final controller = WesiAiChatController(
      store: store,
      api: _RecordingApi(),
      memoryApi: memoryApi,
    );
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);
    final conversationId = controller.state.activeConversationId!;

    await controller.addUserMessage('Запомни это важное правило');
    await _waitUntil(() => memoryApi.calls == 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final messages = controller.state.messagesFor(conversationId);
    expect(
      messages.any(
        (message) =>
            message.author == WesiAiMessageAuthor.zane &&
            message.text == 'Готово',
      ),
      isTrue,
    );
    expect(
      messages.any((message) => message.kind == WesiAiMessageKind.error),
      isFalse,
    );
  });

  test('rolling summary removes summarized prefix from next transport history', () async {
    final store = _MemoryStore('employee-history');
    final api = _RecordingApi();
    final controller = WesiAiChatController(
      store: store,
      api: api,
      memoryApi: _FakeMemoryApi(),
    );
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);
    final conversation = controller.state.activeConversation!;
    final now = DateTime(2026, 8, 15);
    final messages = <WesiAiMessage>[
      for (var index = 0; index < 6; index++)
        WesiAiMessage(
          id: 'history-$index',
          conversationId: conversation.id,
          employeeId: store.employeeId,
          author: index.isEven
              ? WesiAiMessageAuthor.user
              : WesiAiMessageAuthor.zane,
          text: 'old-$index',
          createdAt: now.add(Duration(seconds: index)),
        ),
    ];
    store.saved = controller.state.copyWith(
      messages: messages,
      conversationMemory: <String, WesiAiConversationMemoryState>{
        conversation.id: WesiAiConversationMemoryState(
          conversationId: conversation.id,
          rollingSummary: 'old 0..3',
          taskState: const <String, dynamic>{'goal': 'continue'},
          summarizedMessageCount: 4,
        ),
      },
    );
    await controller.load();

    await controller.addUserMessage('new question');
    expect(api.history.map((message) => message.text), <String>['old-4', 'old-5']);
    expect(api.summary, 'old 0..3');
    expect(api.taskState['goal'], 'continue');
  });

  test('compaction advances by bounded oldest-first batch instead of skipping gap', () async {
    final store = _MemoryStore('employee-batch');
    final memoryApi = _FakeMemoryApi(
      result: const WesiAiMemoryProcessResult(
        summary: 'batch summary',
        taskState: <String, dynamic>{},
        memories: <WesiAiMemoryCandidate>[],
      ),
    );
    final controller = WesiAiChatController(
      store: store,
      api: _RecordingApi(),
      memoryApi: memoryApi,
    );
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);
    final conversation = controller.state.activeConversation!;
    final now = DateTime(2026, 8, 15);
    final messages = <WesiAiMessage>[
      for (var index = 0; index < 30; index++)
        WesiAiMessage(
          id: 'batch-$index',
          conversationId: conversation.id,
          employeeId: store.employeeId,
          author: index.isEven
              ? WesiAiMessageAuthor.user
              : WesiAiMessageAuthor.zane,
          text: 'batch-$index',
          createdAt: now.add(Duration(seconds: index)),
        ),
    ];
    store.saved = controller.state.copyWith(
      messages: messages,
      conversationMemory: <String, WesiAiConversationMemoryState>{
        conversation.id: WesiAiConversationMemoryState(
          conversationId: conversation.id,
        ),
      },
    );
    await controller.load();

    await controller.addUserMessage('Запомни прогресс');
    await _waitUntil(() => memoryApi.calls == 1);
    expect(memoryApi.batches.single.length, 24);
    expect(memoryApi.batches.single.first, 'batch-0');
    expect(memoryApi.batches.single.last, 'batch-23');
    expect(
      controller.state
          .conversationMemory[conversation.id]
          ?.summarizedMessageCount,
      24,
    );
  });
'''
s = s[:end] + extra + s[end:]
p.write_text(s, encoding='utf-8')

# Local corrupted state: task state must be bounded and orphan chat-memory discarded by existing id check.
p = Path('lib/features/ai/memory/wesi_ai_memory_models.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(s,
'''    final taskState = taskRaw is Map
        ? Map<String, dynamic>.from(taskRaw)
        : const <String, dynamic>{};
''',
'''    Map<String, dynamic> taskState = const <String, dynamic>{};
    if (taskRaw is Map) {
      final candidate = Map<String, dynamic>.from(taskRaw);
      try {
        if (candidate.toString().length <= 12000) taskState = candidate;
      } catch (_) {}
    }
''', 'local task state bound')
p.write_text(s, encoding='utf-8')
