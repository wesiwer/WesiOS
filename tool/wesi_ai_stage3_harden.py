from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'missing anchor: {label}')
    return text.replace(old, new, 1)


p = Path('lib/features/ai/controllers/wesi_ai_chat_controller.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(s,
'''  final Set<String> _memoryRefreshes = <String>{};
  final WesiAiMemoryApi memoryApi = const WesiAiMemoryApi();''',
'''  final Set<String> _memoryRefreshes = <String>{};
  final WesiAiMemoryApi memoryApi;''', 'base memory api field')
s = replace_once(s,
'''  WesiAiChatController({required this.store, this.api = const WesiAiApi()})
      : state = WesiAiLocalState.empty(store.employeeId);''',
'''  WesiAiChatController({
    required this.store,
    this.api = const WesiAiApi(),
    this.memoryApi = const WesiAiMemoryApi(),
  }) : state = WesiAiLocalState.empty(store.employeeId);''', 'base memory api constructor')
p.write_text(s, encoding='utf-8')

p = Path('lib/features/ai/wesi_ai_lobby_controller.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(s,
"import 'models/wesi_ai_attachment.dart';\n",
"import 'memory/wesi_ai_memory_api.dart';\nimport 'models/wesi_ai_attachment.dart';\n", 'lobby memory import')
s = replace_once(s,
'''  WesiAiLobbyChatController({
    required WesiAiLocalStore store,
    WesiAiApi api = const WesiAiLobbyApi(),
  }) : super(store: store, api: api);''',
'''  WesiAiLobbyChatController({
    required WesiAiLocalStore store,
    WesiAiApi api = const WesiAiLobbyApi(),
    WesiAiMemoryApi memoryApi = const WesiAiMemoryApi(),
  }) : super(store: store, api: api, memoryApi: memoryApi);''', 'lobby memory constructor')
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
        super(store: store, api: api);''',
'''    WesiAiApi api = const WesiAiLobbyApi(),
    WesiAiMemoryApi memoryApi = const WesiAiMemoryApi(),
    String? processSessionId,
  })  : _queueSessionId = processSessionId ?? _runtimeQueueSessionId,
        super(store: store, api: api, memoryApi: memoryApi);''', 'managed memory constructor')
p.write_text(s, encoding='utf-8')

p = Path('test/wesi_ai_memory_engine_test.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(s,
"import 'package:wesios/features/ai/memory/wesi_ai_memory_engine.dart';\n",
"import 'package:wesios/features/ai/controllers/wesi_ai_chat_controller.dart';\nimport 'package:wesios/features/ai/memory/wesi_ai_memory_api.dart';\nimport 'package:wesios/features/ai/memory/wesi_ai_memory_engine.dart';\n", 'test controller imports')
s = replace_once(s,
"import 'package:wesios/features/ai/storage/wesi_ai_local_store.dart';\n",
"import 'package:wesios/features/ai/storage/wesi_ai_local_store.dart';\nimport 'package:wesios/features/ai/wesi_ai_api.dart';\n", 'test api import')
insert_anchor = 'void main() {'
classes = r'''class _MemoryStore extends WesiAiLocalStore {
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

class _ImmediateApi extends WesiAiApi {
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
    onDelta?.call('Готово');
    return const WesiAiReply(answer: 'Готово', requestId: 'memory-test');
  }
}

class _FakeMemoryApi extends WesiAiMemoryApi {
  final WesiAiMemoryProcessResult? result;
  final bool fail;
  int calls = 0;

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
s = replace_once(s, insert_anchor, classes + insert_anchor, 'test helper classes')
end = s.rfind('\n}')
if end < 0:
    raise SystemExit('test closing brace missing')
extra = r'''

  test('context package contains project summary and bounded task state', () {
    final project = WesiAiProject(
      id: 'project-1',
      employeeId: 'employee-1',
      title: 'Wesi AI',
      description: 'Описание',
      instructions: 'Не ломать main',
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
    );
    final context = WesiAiApi.contextPackage(
      project,
      conversationSummary: 'Краткое содержание старой части чата',
      taskState: const <String, dynamic>{'goal': 'исправить build'},
    );
    expect(context, contains('[WESI_AI_PROJECT]'));
    expect(context, contains('[WESI_AI_ROLLING_SUMMARY]'));
    expect(context, contains('[WESI_AI_TASK_STATE]'));
    expect(context, contains('исправить build'));
  });

  test('manual memory controls persist locally and reject secret-like text', () async {
    final store = _MemoryStore('employee-controls');
    final controller = WesiAiChatController(
      store: store,
      api: _ImmediateApi(),
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
      api: _ImmediateApi(),
      memoryApi: memoryApi,
    );
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);
    final conversationId = controller.state.activeConversationId!;

    await controller.addUserMessage('Запомни: я предпочитаю режим Pro');
    await _waitUntil(() => memoryApi.calls == 1 && controller.state.memoryEntries.isNotEmpty);

    expect(controller.state.memoryEntries.single.text, 'Пользователь предпочитает режим Pro');
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
      api: _ImmediateApi(),
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
      messages.any((message) =>
          message.author == WesiAiMessageAuthor.zane && message.text == 'Готово'),
      isTrue,
    );
    expect(
      messages.any((message) => message.kind == WesiAiMessageKind.error),
      isFalse,
    );
  });
'''
s = s[:end] + extra + s[end:]
p.write_text(s, encoding='utf-8')
