import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/ai/controllers/wesi_ai_chat_controller.dart';
import 'package:wesios/features/ai/models/wesi_ai_chat_models.dart';
import 'package:wesios/features/ai/storage/wesi_ai_local_store.dart';

void main() {
  late Directory temp;
  late WesiAiLocalStore store;
  late WesiAiChatController controller;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wesi_ai_chat_actions_');
    Hive.init(temp.path);
    store = const WesiAiLocalStore('employee_test');
    controller = WesiAiChatController(store: store);
    final now = DateTime(2026, 8, 16, 0, 30);
    const conversationId = 'conversation_original_01';
    controller.state = WesiAiLocalState.empty('employee_test').copyWith(
      activeConversationId: conversationId,
      conversations: [
        WesiAiConversation(
          id: conversationId,
          employeeId: 'employee_test',
          title: 'Исходный чат',
          persona: WesiAiPersona.zane,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      messages: [
        WesiAiMessage(
          id: 'message_user_0001',
          conversationId: conversationId,
          employeeId: 'employee_test',
          author: WesiAiMessageAuthor.user,
          text: 'Сделай изменение',
          createdAt: now,
        ),
        WesiAiMessage(
          id: 'message_ai_000002',
          conversationId: conversationId,
          employeeId: 'employee_test',
          author: WesiAiMessageAuthor.zane,
          text: 'Готово',
          createdAt: now.add(const Duration(seconds: 1)),
        ),
      ],
    );
    await store.save(controller.state);
  });

  tearDown(() async {
    controller.dispose();
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('saved answer is persisted only as message metadata', () async {
    await controller.setMessageSaved('message_ai_000002', true);

    expect(
      controller.state.messages
          .singleWhere((m) => m.id == 'message_ai_000002')
          .metadata['savedToChatArchive'],
      true,
    );
    expect(
      controller.state.messages
          .singleWhere((m) => m.id == 'message_user_0001')
          .metadata['savedToChatArchive'],
      isNull,
    );

    final restored = await store.load();
    expect(
      restored.messages
          .singleWhere((m) => m.id == 'message_ai_000002')
          .metadata['savedToChatArchive'],
      true,
    );
  });

  test('branch copies history through selected message and records its origin',
      () async {
    final branchId =
        await controller.branchConversationFromMessage('message_ai_000002');

    expect(branchId, isNotNull);
    final branch =
        controller.state.conversations.singleWhere((c) => c.id == branchId);
    expect(branch.branchedFromConversationId, 'conversation_original_01');
    expect(branch.branchedFromMessageId, 'message_ai_000002');
    expect(controller.state.activeConversationId, branchId);

    final branchMessages = controller.state.messagesFor(branchId!);
    expect(branchMessages, hasLength(2));
    expect(branchMessages.map((m) => m.text), ['Сделай изменение', 'Готово']);
    expect(
        branchMessages.every((m) =>
            m.metadata['branchOriginalConversationId'] ==
            'conversation_original_01'),
        true);

    final restored = await store.load();
    final restoredBranch =
        restored.conversations.singleWhere((c) => c.id == branchId);
    expect(
        restoredBranch.branchedFromConversationId, 'conversation_original_01');
    expect(restoredBranch.branchedFromMessageId, 'message_ai_000002');
    expect(restored.messagesFor(branchId), hasLength(2));
  });
}
