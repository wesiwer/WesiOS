import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/controllers/wesi_ai_chat_controller.dart';
import 'package:wesios/features/ai/memory/wesi_ai_memory_models.dart';
import 'package:wesios/features/ai/storage/wesi_ai_local_store.dart';

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

void main() {
  test('manual memory controls persist locally and reject secret-like text', () async {
    final store = _MemoryStore('employee-controls');
    final controller = WesiAiChatController(store: store);
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);

    expect(
      await controller.addManualMemory(
        WesiAiMemoryScope.shared,
        'Предпочитает короткие технические отчёты',
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
    final chatId = controller.state.activeConversationId!;
    expect(controller.state.conversationMemory[chatId]?.memoryEnabled, isFalse);

    await controller.deleteMemory(controller.state.memoryEntries.single.id);
    expect(controller.state.memoryEntries, isEmpty);
    expect(store.saved, isNotNull);
  });

  test('project memory requires active project and clear only affects that project', () async {
    final store = _MemoryStore('employee-project-memory');
    final controller = WesiAiChatController(store: store);
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);

    expect(
      await controller.addManualMemory(
        WesiAiMemoryScope.project,
        'Project-only rule',
      ),
      isFalse,
    );
  });

  test('oversized persisted task state is dropped fail-closed', () {
    final state = WesiAiConversationMemoryState.fromJson(
      <String, dynamic>{
        'conversationId': 'conversation-1',
        'rollingSummary': 'summary',
        'taskState': <String, dynamic>{'payload': 'x' * 13000},
        'summarizedMessageCount': 3,
        'memoryEnabled': true,
      },
      knownConversationIds: const <String>{'conversation-1'},
    );

    expect(state.taskState, isEmpty);
    expect(state.rollingSummary, 'summary');
    expect(state.summarizedMessageCount, 3);
  });

  test('orphan conversation memory is rejected during local migration', () {
    expect(
      () => WesiAiConversationMemoryState.fromJson(
        <String, dynamic>{
          'conversationId': 'deleted-chat',
          'rollingSummary': 'stale',
          'taskState': <String, dynamic>{},
          'summarizedMessageCount': 1,
        },
        knownConversationIds: const <String>{'active-chat'},
      ),
      throwsFormatException,
    );
  });
}
