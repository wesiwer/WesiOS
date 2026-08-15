import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_attachment.dart';
import 'package:wesios/features/ai/models/wesi_ai_chat_models.dart';
import 'package:wesios/features/ai/storage/wesi_ai_local_store.dart';
import 'package:wesios/features/ai/wesi_ai_api.dart';
import 'package:wesios/features/ai/wesi_ai_managed_controller.dart';

class _MemoryStore extends WesiAiLocalStore {
  WesiAiLocalState? saved;

  _MemoryStore(String employeeId) : super(employeeId);

  @override
  Future<WesiAiLocalState> load() async =>
      saved ?? WesiAiLocalState.empty(employeeId);

  @override
  Future<void> save(WesiAiLocalState state) async {
    saved = state;
  }
}

class _ControlledApi extends WesiAiApi {
  final Completer<WesiAiReply> first = Completer<WesiAiReply>();
  final List<String> prompts = <String>[];
  final List<List<String>> attachmentNames = <List<String>>[];

  @override
  Future<WesiAiReply> send({
    required WesiAiConversation conversation,
    required WesiAiTier tier,
    required String message,
    required List<WesiAiMessage> history,
    required WesiAiMemorySnapshot memory,
    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
  }) {
    prompts.add(message);
    attachmentNames.add(
      attachments.map((attachment) => attachment.name).toList(growable: false),
    );
    if (prompts.length == 1) return first.future;
    return Future<WesiAiReply>.value(
      WesiAiReply(
        answer: 'reply:$message',
        requestId: 'request-${prompts.length}',
      ),
    );
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 400; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for Wesi AI queue');
}

Future<WesiAiManagedChatController> _controller(_ControlledApi api) async {
  final controller = WesiAiManagedChatController(
    store: _MemoryStore('employee-1'),
    api: api,
  );
  await controller.load();
  await controller.createConversation(WesiAiPersona.zane);
  return controller;
}

void main() {
  test('queue accepts exactly 12 waiting turns and preserves FIFO', () async {
    final api = _ControlledApi();
    final controller = await _controller(api);

    expect(
      controller.submitUserMessage('first'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => api.prompts.length == 1);

    for (var index = 0;
        index < WesiAiManagedChatController.maxQueuedTurns;
        index++) {
      expect(
        controller.submitUserMessage('queued-$index'),
        WesiAiMessageSubmitResult.accepted,
      );
    }
    expect(
      controller.queuedTurnCount,
      WesiAiManagedChatController.maxQueuedTurns,
    );
    expect(
      controller.submitUserMessage('overflow'),
      WesiAiMessageSubmitResult.queueFull,
    );

    api.first.complete(
      const WesiAiReply(answer: 'reply:first', requestId: 'request-1'),
    );
    await _waitUntil(() => !controller.processing);

    expect(
      api.prompts,
      <String>[
        'first',
        for (var index = 0;
            index < WesiAiManagedChatController.maxQueuedTurns;
            index++)
          'queued-$index',
      ],
    );
    expect(controller.queuedTurnCount, 0);
  });

  test('unexpected failure does not stop later queued turns', () async {
    final api = _ControlledApi();
    final controller = await _controller(api);
    final conversationId = controller.state.activeConversationId!;

    expect(
      controller.submitUserMessage('will-fail'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => api.prompts.length == 1);
    expect(
      controller.submitUserMessage('must-run-after-failure'),
      WesiAiMessageSubmitResult.accepted,
    );

    api.first.completeError(StateError('synthetic unexpected failure'));
    await _waitUntil(() => !controller.processing);

    expect(api.prompts, <String>['will-fail', 'must-run-after-failure']);
    final messages = controller.state.messagesFor(conversationId);
    expect(
      messages.any(
        (message) =>
            message.metadata['code'] == 'WAI_MESSAGE_QUEUE_ITEM_FAILED',
      ),
      isTrue,
    );
    expect(
      messages.any(
        (message) =>
            message.author == WesiAiMessageAuthor.zane &&
            message.text == 'reply:must-run-after-failure',
      ),
      isTrue,
    );
  });

  test('queued turn keeps its chat and attachment context', () async {
    final api = _ControlledApi();
    final controller = await _controller(api);
    final firstChat = controller.state.activeConversationId!;

    await controller.createConversation(WesiAiPersona.nirvana);
    final secondChat = controller.state.activeConversationId!;
    await controller.selectConversation(firstChat);

    expect(
      controller.submitUserMessage('first-chat'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => api.prompts.length == 1);

    await controller.selectConversation(secondChat);
    final attachment = WesiAiAttachment.fromBytes(
      name: 'context.txt',
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
    );
    expect(
      controller.submitUserMessage(
        'second-chat',
        attachments: <WesiAiAttachment>[attachment],
      ),
      WesiAiMessageSubmitResult.accepted,
    );

    api.first.complete(
      const WesiAiReply(answer: 'reply:first-chat', requestId: 'request-1'),
    );
    await _waitUntil(() => !controller.processing);

    expect(
      controller.state
          .messagesFor(firstChat)
          .where((message) => message.author == WesiAiMessageAuthor.user)
          .map((message) => message.text),
      contains('first-chat'),
    );
    expect(
      controller.state
          .messagesFor(secondChat)
          .where((message) => message.author == WesiAiMessageAuthor.user)
          .map((message) => message.text),
      contains('second-chat'),
    );
    expect(api.attachmentNames[1], <String>['context.txt']);
    expect(controller.state.activeConversationId, secondChat);
  });

  test('disposing screen controller does not interrupt accepted queue', () async {
    final api = _ControlledApi();
    final store = _MemoryStore('employee-1');
    final controller = WesiAiManagedChatController(
      store: store,
      api: api,
    );
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);
    final conversationId = controller.state.activeConversationId!;

    expect(
      controller.submitUserMessage('before-close'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => api.prompts.length == 1);
    expect(
      controller.submitUserMessage('queued-before-close'),
      WesiAiMessageSubmitResult.accepted,
    );

    controller.dispose();
    api.first.complete(
      const WesiAiReply(answer: 'reply:before-close', requestId: 'request-1'),
    );

    await _waitUntil(() {
      final saved = store.saved;
      if (saved == null || api.prompts.length < 2) return false;
      return saved
          .messagesFor(conversationId)
          .any((message) => message.text == 'reply:queued-before-close');
    });

    expect(api.prompts, <String>['before-close', 'queued-before-close']);
    final saved = store.saved!;
    expect(
      saved
          .messagesFor(conversationId)
          .where((message) => message.author == WesiAiMessageAuthor.user)
          .map((message) => message.text),
      containsAll(<String>['before-close', 'queued-before-close']),
    );
  });

}
