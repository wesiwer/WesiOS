import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_chat_models.dart';
import 'package:wesios/features/ai/storage/wesi_ai_local_store.dart';
import 'package:wesios/features/ai/wesi_ai_api.dart';

void main() {
  test('old local state without projects remains readable', () {
    final now = DateTime(2026, 8, 15);
    final state = WesiAiLocalState.fromJson({
      'employeeId': 'employee-1',
      'tier': 'fast',
      'activeConversationId': 'chat-1',
      'conversations': [
        {
          'id': 'chat-1',
          'employeeId': 'employee-1',
          'title': 'Legacy chat',
          'persona': 'zane',
          'lobbyMode': 'smart',
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
          'archived': false,
          'pinned': false,
        }
      ],
      'messages': const [],
      'memory': const {},
    }, expectedEmployeeId: 'employee-1');

    expect(state.projects, isEmpty);
    expect(state.activeProjectId, isNull);
    expect(state.activeConversation?.projectId, isNull);
  });

  test('project survives JSON roundtrip and conversation keeps projectId', () {
    final now = DateTime(2026, 8, 15);
    final project = WesiAiProject(
      id: 'project-1',
      employeeId: 'employee-1',
      title: 'WesiOS',
      description: 'Разработка приложения',
      instructions: 'Проверяй сборку перед ответом',
      createdAt: now,
      updatedAt: now,
    );
    final conversation = WesiAiConversation(
      id: 'chat-1',
      employeeId: 'employee-1',
      title: 'Android build',
      persona: WesiAiPersona.zane,
      projectId: project.id,
      createdAt: now,
      updatedAt: now,
    );
    final state = WesiAiLocalState(
      employeeId: 'employee-1',
      tier: WesiAiTier.pro,
      activeConversationId: conversation.id,
      activeProjectId: project.id,
      projects: [project],
      conversations: [conversation],
      messages: const [],
      memory: const WesiAiMemorySnapshot(),
    );

    final restored = WesiAiLocalState.fromJson(
      state.toJson(),
      expectedEmployeeId: 'employee-1',
    );
    expect(restored.activeProject?.title, 'WesiOS');
    expect(restored.activeConversation?.projectId, 'project-1');
  });

  test('project context contains project instructions', () {
    final now = DateTime(2026, 8, 15);
    final context = WesiAiApi.projectContext(WesiAiProject(
      id: 'project-1',
      employeeId: 'employee-1',
      title: 'WesiOS',
      description: 'Разработка',
      instructions: 'Всегда тестируй изменения',
      createdAt: now,
      updatedAt: now,
    ));

    expect(context, contains('[WESI_AI_PROJECT]'));
    expect(context, contains('WesiOS'));
    expect(context, contains('Всегда тестируй изменения'));
  });
}
