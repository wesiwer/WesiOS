import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/ai/controllers/wesi_ai_chat_controller.dart';
import 'package:wesios/features/ai/models/wesi_ai_chat_models.dart';
import 'package:wesios/features/ai/storage/wesi_ai_local_store.dart';

class _TestController extends WesiAiChatController {
  _TestController(WesiAiLocalStore store) : super(store: store);

  Future<bool> materialize(String id) => materializeConversationForFirstTurn(id);
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('wesios_ai_lazy_chat_');
    Hive.init(temp.path);
  });

  tearDown(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test('blank new chats never enter durable history', () async {
    const employeeId = 'employee_lazy_chat_test';
    const store = WesiAiLocalStore(employeeId);
    final controller = _TestController(store);
    await controller.load();

    await controller.createConversation(WesiAiPersona.zane);
    final firstDraft = controller.state.activeConversation;
    expect(firstDraft, isNotNull);
    expect(controller.isTransientConversation(firstDraft!.id), isTrue);
    expect((await store.load()).conversations, isEmpty);

    await controller.createConversation(WesiAiPersona.nirvana);
    final secondDraft = controller.state.activeConversation;
    expect(secondDraft, isNotNull);
    expect(secondDraft!.id, isNot(firstDraft.id));
    expect(controller.state.conversations, hasLength(2));
    expect(controller.isTransientConversation(firstDraft.id), isTrue);
    expect(controller.isTransientConversation(secondDraft.id), isTrue);
    expect((await store.load()).conversations, isEmpty);

    expect(await controller.materialize(secondDraft.id), isTrue);
    final durable = await store.load();
    expect(durable.conversations, hasLength(1));
    expect(durable.conversations.single.id, secondDraft.id);
    expect(durable.activeConversationId, secondDraft.id);
    expect(controller.isTransientConversation(firstDraft.id), isTrue);
  });
}
