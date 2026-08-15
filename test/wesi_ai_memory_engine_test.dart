import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/memory/wesi_ai_memory_engine.dart';
import 'package:wesios/features/ai/memory/wesi_ai_memory_models.dart';
import 'package:wesios/features/ai/models/wesi_ai_attachment.dart';
import 'package:wesios/features/ai/models/wesi_ai_chat_models.dart';
import 'package:wesios/features/ai/storage/wesi_ai_local_store.dart';

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
}
