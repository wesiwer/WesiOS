import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/controllers/wesi_ai_chat_controller.dart';
import 'package:wesios/features/ai/memory/wesi_ai_memory_api.dart';
import 'package:wesios/features/ai/memory/wesi_ai_memory_engine.dart';
import 'package:wesios/features/ai/memory/wesi_ai_memory_models.dart';
import 'package:wesios/features/ai/models/wesi_ai_attachment.dart';
import 'package:wesios/features/ai/models/wesi_ai_chat_models.dart';
import 'package:wesios/features/ai/storage/wesi_ai_local_store.dart';
import 'package:wesios/features/ai/wesi_ai_api.dart';

WesiAiMemoryEntry _entry({
  required String id,
  required WesiAiMemoryScope scope,
  required String text,
  String? projectId,
  bool manual = false,
  bool pinned = false,
}) =>
    WesiAiMemoryEntry(
      id: id,
      employeeId: 'employee-1',
      scope: scope,
      text: text,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 14),
      projectId: projectId,
      manual: manual,
      pinned: pinned,
    );

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

class _CaptureApi extends WesiAiApi {
  final List<List<WesiAiMessage>> histories = <List<WesiAiMessage>>[];

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
    histories.add(List<WesiAiMessage>.from(history));
    onDelta?.call('Готово');
    return const WesiAiReply(answer: 'Готово', requestId: 'memory-test');
  }
}

class _FakeMemoryApi extends WesiAiMemoryApi {
  final WesiAiMemoryProcessResult? result;
  final bool fail;
  int calls = 0;
  final List<List<WesiAiMessage>> batches = <List<WesiAiMessage>>[];

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
    batches.add(List<WesiAiMessage>.from(recentMessages));
    if (fail) {
      throw const WesiAiApiException(
        'WAI_MEMORY_FAILED',
        'synthetic memory failure',
      );
    }
    return result ??
        const WesiAiMemoryProcessResult(
          summary: 'summary',
          taskState: <String, dynamic>{},
          memories: <WesiAiMemoryCandidate>[],
        );
  }
}

Future<void> _waitMemory(bool Function() condition) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for memory processing');
}

void main() {
  test('retrieval isolates persona and project memory', () {
    final entries = <WesiAiMemoryEntry>[
      _entry(
          id: 'memory_shared_01',
          scope: WesiAiMemoryScope.shared,
          text: 'Пользователь предпочитает короткие технические отчёты'),
      _entry(
          id: 'memory_zane_001',
          scope: WesiAiMemoryScope.zane,
          text: 'Для Flutter задач сначала запускать targeted tests'),
      _entry(
          id: 'memory_nirvana1',
          scope: WesiAiMemoryScope.nirvana,
          text: 'Визуальный стиль проекта минималистичный'),
      _entry(
          id: 'memory_project1',
          scope: WesiAiMemoryScope.project,
          text: 'Android build проекта использует текущую release подпись',
          projectId: 'project-a'),
      _entry(
          id: 'memory_project2',
          scope: WesiAiMemoryScope.project,
          text: 'Другой проект использует старую подпись',
          projectId: 'project-b'),
    ];

    final result = WesiAiMemoryEngine.retrieve(
      entries: entries,
      employeeId: 'employee-1',
      persona: WesiAiPersona.zane,
      projectId: 'project-a',
      query: 'проверь Flutter Android build и подпись',
      settings: const WesiAiMemorySettings(retrievalLimit: 12),
      now: DateTime(2026, 8, 15),
    );

    expect(result.zane,
        contains('Для Flutter задач сначала запускать targeted tests'));
    expect(result.nirvana, isEmpty);
    expect(result.project,
        contains('Android build проекта использует текущую release подпись'));
    expect(result.project,
        isNot(contains('Другой проект использует старую подпись')));
  });

  test('automatic merge deduplicates and rejects secret-like memory', () {
    final existing = <WesiAiMemoryEntry>[
      _entry(
          id: 'memory_existing1',
          scope: WesiAiMemoryScope.shared,
          text: 'Пользователь предпочитает тёмную тему'),
    ];
    final merged = WesiAiMemoryEngine.mergeCandidates(
      existing: existing,
      candidates: const <WesiAiMemoryCandidate>[
        WesiAiMemoryCandidate(
            scope: WesiAiMemoryScope.shared,
            text: 'Пользователь предпочитает тёмную тему',
            importance: 0.9),
        WesiAiMemoryCandidate(
            scope: WesiAiMemoryScope.shared,
            text: 'API key: super-secret-value-123456',
            importance: 1),
      ],
      employeeId: 'employee-1',
      sourceConversationId: 'conversation-1',
      settings: const WesiAiMemorySettings(),
      now: DateTime(2026, 8, 15),
    );

    expect(merged.length, 1);
    expect(merged.single.importance, 0.9);
    expect(merged.single.text, 'Пользователь предпочитает тёмную тему');
  });

  test('processing threshold respects global and per-chat memory controls', () {
    const settings = WesiAiMemorySettings();
    const chat = WesiAiConversationMemoryState(
        conversationId: 'conversation-1', summarizedMessageCount: 4);
    expect(
        WesiAiMemoryEngine.shouldProcess(
            settings: settings,
            conversationMemory: chat,
            currentTextMessageCount: 14,
            latestUserText: 'продолжай'),
        isTrue);
    expect(
        WesiAiMemoryEngine.shouldProcess(
            settings: const WesiAiMemorySettings(autoMemoryEnabled: false),
            conversationMemory: chat,
            currentTextMessageCount: 100,
            latestUserText: 'запомни это'),
        isFalse);
    expect(
        WesiAiMemoryEngine.shouldProcess(
            settings: settings,
            conversationMemory: chat.copyWith(memoryEnabled: false),
            currentTextMessageCount: 100,
            latestUserText: 'запомни это'),
        isFalse);
  });

  test('legacy v2 snapshot migrates into structured entries', () {
    final json = <String, dynamic>{
      'schemaVersion': 2,
      'employeeId': 'employee-1',
      'tier': 'fast',
      'activeConversationId': 'conversation-1',
      'projects': <dynamic>[],
      'conversations': <dynamic>[
        <String, dynamic>{
          'id': 'conversation-1',
          'employeeId': 'employee-1',
          'title': 'Чат',
          'persona': 'zane',
          'createdAt': '2026-08-01T00:00:00.000Z',
          'updatedAt': '2026-08-02T00:00:00.000Z',
        },
      ],
      'messages': <dynamic>[],
      'memory': <String, dynamic>{
        'shared': <String>['Любит краткие ответы'],
        'zane': <String>['Сначала проверять build'],
        'nirvana': <String>[],
      },
    };

    final state =
        WesiAiLocalState.fromJson(json, expectedEmployeeId: 'employee-1');
    expect(state.memoryEntries.length, 2);
    expect(
        state.memoryEntries.any((entry) =>
            entry.scope == WesiAiMemoryScope.shared &&
            entry.text == 'Любит краткие ответы'),
        isTrue);
    expect(state.conversationMemory['conversation-1']?.memoryEnabled, isTrue);
  });

  test('successful background processor persists summary task state and memory',
      () async {
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
      api: _CaptureApi(),
      memoryApi: memoryApi,
    );
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);
    final conversationId = controller.state.activeConversationId!;
    await controller.addUserMessage('Запомни: я предпочитаю режим Pro');
    await _waitMemory(() =>
        memoryApi.calls == 1 && controller.state.memoryEntries.isNotEmpty);
    expect(controller.state.memoryEntries.single.text,
        'Пользователь предпочитает режим Pro');
    expect(controller.state.conversationMemory[conversationId]?.rollingSummary,
        'Пользователь попросил запомнить настройку.');
    expect(
        controller.state.conversationMemory[conversationId]?.taskState['goal'],
        'держать настройку');
  });

  test('memory processor failure never turns successful chat into an error',
      () async {
    final store = _MemoryStore('employee-failure');
    final memoryApi = _FakeMemoryApi(fail: true);
    final controller = WesiAiChatController(
      store: store,
      api: _CaptureApi(),
      memoryApi: memoryApi,
    );
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);
    final conversationId = controller.state.activeConversationId!;
    await controller.addUserMessage('Запомни это важное правило');
    await _waitMemory(() => memoryApi.calls == 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final messages = controller.state.messagesFor(conversationId);
    expect(
        messages.any((message) =>
            message.author == WesiAiMessageAuthor.zane &&
            message.text == 'Готово'),
        isTrue);
    expect(messages.any((message) => message.kind == WesiAiMessageKind.error),
        isFalse);
  });

  test('rolling summary removes summarized raw history from next request',
      () async {
    final store = _MemoryStore('employee-history');
    final api = _CaptureApi();
    final controller = WesiAiChatController(
      store: store,
      api: api,
      memoryApi: _FakeMemoryApi(),
    );
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);
    final conversationId = controller.state.activeConversationId!;
    final base = DateTime(2026, 8, 15, 10);
    controller.state = controller.state.copyWith(
      messages: <WesiAiMessage>[
        for (var i = 0; i < 6; i++)
          WesiAiMessage(
            id: 'old_memory_message_$i',
            conversationId: conversationId,
            employeeId: store.employeeId,
            author:
                i.isEven ? WesiAiMessageAuthor.user : WesiAiMessageAuthor.zane,
            text: 'old-$i',
            createdAt: base.add(Duration(minutes: i)),
          ),
      ],
      conversationMemory: <String, WesiAiConversationMemoryState>{
        conversationId: WesiAiConversationMemoryState(
          conversationId: conversationId,
          rollingSummary: 'old-0..old-3 summarized',
          summarizedMessageCount: 4,
        ),
      },
    );
    await controller.addUserMessage('новый вопрос без запоминания');
    expect(api.histories.last.map((message) => message.text).toList(),
        <String>['old-4', 'old-5']);
  });

  test('long unsummarized chat is compacted oldest-first in batches of 24',
      () async {
    final store = _MemoryStore('employee-batch');
    final memoryApi = _FakeMemoryApi();
    final controller = WesiAiChatController(
      store: store,
      api: _CaptureApi(),
      memoryApi: memoryApi,
    );
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);
    final conversationId = controller.state.activeConversationId!;
    final base = DateTime(2026, 8, 15, 9);
    controller.state = controller.state.copyWith(
      messages: <WesiAiMessage>[
        for (var i = 0; i < 30; i++)
          WesiAiMessage(
            id: 'batch_memory_message_$i',
            conversationId: conversationId,
            employeeId: store.employeeId,
            author:
                i.isEven ? WesiAiMessageAuthor.user : WesiAiMessageAuthor.zane,
            text: 'message-$i',
            createdAt: base.add(Duration(minutes: i)),
          ),
      ],
    );
    await controller.addUserMessage('запомни текущий контекст');
    await _waitMemory(() => memoryApi.calls == 1);
    expect(memoryApi.batches.single.length, 24);
    expect(memoryApi.batches.single.first.text, 'message-0');
    expect(memoryApi.batches.single.last.text, 'message-23');
    await _waitMemory(() =>
        controller
            .state.conversationMemory[conversationId]?.summarizedMessageCount ==
        24);
  });
}
