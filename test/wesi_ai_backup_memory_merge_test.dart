import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/backup/wesi_ai_backup_service.dart';
import 'package:wesios/features/ai/memory/wesi_ai_memory_models.dart';
import 'package:wesios/features/ai/models/wesi_ai_chat_models.dart';
import 'package:wesios/features/ai/storage/wesi_ai_local_store.dart';

WesiAiLocalState _state({
  required DateTime memoryUpdatedAt,
  required bool pinned,
  required bool manual,
  required double importance,
}) {
  const employeeId = 'employee_memory_merge';
  final now = DateTime(2026, 8, 15, 12);
  const conversationId = 'conversation_merge_1';
  return WesiAiLocalState.empty(employeeId).copyWith(
    conversations: <WesiAiConversation>[
      WesiAiConversation(
        id: conversationId,
        employeeId: employeeId,
        title: 'Important chat',
        persona: WesiAiPersona.zane,
        createdAt: now,
        updatedAt: now,
        importantForBackup: true,
      ),
    ],
    messages: <WesiAiMessage>[
      WesiAiMessage(
        id: 'message_merge_1',
        conversationId: conversationId,
        employeeId: employeeId,
        author: WesiAiMessageAuthor.user,
        text: 'remember preference',
        createdAt: now,
      ),
    ],
    memoryEntries: <WesiAiMemoryEntry>[
      WesiAiMemoryEntry(
        id: 'memory_merge_001',
        employeeId: employeeId,
        scope: WesiAiMemoryScope.shared,
        text: 'Prefers concise technical reports',
        createdAt: now,
        updatedAt: memoryUpdatedAt,
        pinned: pinned,
        manual: manual,
        importance: importance,
      ),
    ],
  );
}

void main() {
  test('newer backup memory cannot erase local pinned/manual intent', () async {
    final local = _state(
      memoryUpdatedAt: DateTime(2026, 8, 14),
      pinned: true,
      manual: true,
      importance: 0.9,
    );
    final imported = _state(
      memoryUpdatedAt: DateTime(2026, 8, 15),
      pinned: false,
      manual: false,
      importance: 0.4,
    );
    final package = await WesiAiBackupService.buildImportantPackage(imported);
    final result = await WesiAiBackupService.importPackage(
      package: package.packageBytes,
      current: local,
    );

    expect(result.state.memoryEntries.length, 1);
    final memory = result.state.memoryEntries.single;
    expect(memory.pinned, isTrue);
    expect(memory.manual, isTrue);
    expect(memory.importance, 0.9);
    expect(memory.updatedAt, DateTime(2026, 8, 15));
  });
}
