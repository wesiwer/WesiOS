import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_attachment.dart';
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
    expect(restored.toJson()['schemaVersion'], WesiAiLocalStore.schemaVersion);
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

  test('unknown tier falls back to fast instead of breaking local AI', () {
    final state = WesiAiLocalState.fromJson({
      'employeeId': 'employee-1',
      'tier': 'future-super-tier',
      'conversations': const [],
      'messages': const [],
      'projects': const [],
      'memory': const {},
    }, expectedEmployeeId: 'employee-1');
    expect(state.tier, WesiAiTier.fast);
  });

  test('orphan project link is migrated to no-project and orphan messages are dropped', () {
    final now = DateTime(2026, 8, 15);
    final state = WesiAiLocalState.fromJson({
      'employeeId': 'employee-1',
      'tier': 'fast',
      'activeProjectId': 'missing-project',
      'activeConversationId': 'chat-1',
      'projects': const [],
      'conversations': [
        {
          'id': 'chat-1',
          'employeeId': 'employee-1',
          'title': 'Recovered chat',
          'persona': 'zane',
          'lobbyMode': 'smart',
          'projectId': 'missing-project',
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        }
      ],
      'messages': [
        {
          'id': 'valid',
          'conversationId': 'chat-1',
          'employeeId': 'employee-1',
          'author': 'user',
          'kind': 'text',
          'text': 'hello',
          'createdAt': now.toIso8601String(),
        },
        {
          'id': 'orphan',
          'conversationId': 'missing-chat',
          'employeeId': 'employee-1',
          'author': 'user',
          'kind': 'text',
          'text': 'must disappear',
          'createdAt': now.toIso8601String(),
        },
      ],
      'memory': const {},
    }, expectedEmployeeId: 'employee-1');

    expect(state.activeConversation?.id, 'chat-1');
    expect(state.activeConversation?.projectId, isNull);
    expect(state.activeProjectId, isNull);
    expect(state.messages.map((item) => item.id), ['valid']);
  });

  test('active conversation project wins over stale activeProjectId during migration', () {
    final now = DateTime(2026, 8, 15);
    Map<String, dynamic> project(String id) => {
          'id': id,
          'employeeId': 'employee-1',
          'title': id,
          'description': '',
          'instructions': '',
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        };
    final state = WesiAiLocalState.fromJson({
      'employeeId': 'employee-1',
      'tier': 'fast',
      'activeProjectId': 'project-old',
      'activeConversationId': 'chat-1',
      'projects': [project('project-old'), project('project-new')],
      'conversations': [
        {
          'id': 'chat-1',
          'employeeId': 'employee-1',
          'title': 'Moved chat',
          'persona': 'nirvana',
          'lobbyMode': 'smart',
          'projectId': 'project-new',
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        }
      ],
      'messages': const [],
      'memory': const {},
    }, expectedEmployeeId: 'employee-1');
    expect(state.activeProjectId, 'project-new');
  });

  test('attachment transport chooses staging without reading a large PlatformFile', () {
    final small = WesiAiAttachment.fromBytes(
      name: 'small.md',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    final large = WesiAiAttachment.fromPlatformFile(PlatformFile(
      name: 'large.zip',
      size: 20 * 1024 * 1024,
      path: '/not/read/during/model/test.zip',
    ));
    expect(WesiAiAttachment.requiresStagedUpload([small]), isFalse);
    expect(WesiAiAttachment.requiresStagedUpload([large]), isTrue);
    expect(large.chunkCount, 20);
    WesiAiAttachment.validateBatch([small, large]);
  });
}
