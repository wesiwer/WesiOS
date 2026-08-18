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
  final Map<String, WesiAiPendingQueueItem> pending =
      <String, WesiAiPendingQueueItem>{};
  bool failPendingWrites = false;
  Completer<void>? pendingWriteGate;
  int pendingWriteCount = 0;

  _MemoryStore(String employeeId) : super(employeeId);

  @override
  Future<WesiAiLocalState> load() async =>
      saved ?? WesiAiLocalState.empty(employeeId);

  @override
  Future<void> save(WesiAiLocalState state) async {
    saved = state;
  }

  @override
  Future<List<WesiAiPendingQueueItem>> loadPendingQueueItems() async {
    final result = pending.values.toList(growable: false);
    result.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return result;
  }

  @override
  Future<void> savePendingQueueItem(WesiAiPendingQueueItem item) async {
    pendingWriteCount++;
    final gate = pendingWriteGate;
    if (pendingWriteCount == 1 && gate != null) await gate.future;
    if (failPendingWrites) throw StateError('synthetic pending write failure');
    pending[item.id] = item;
  }

  @override
  Future<void> removePendingQueueItem(String id) async {
    pending.remove(id);
  }

  @override
  Future<void> removePendingQueueForConversation(String conversationId) async {
    pending.removeWhere((_, item) => item.conversationId == conversationId);
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
    String conversationSummary = '',
    Map<String, dynamic> taskState = const <String, dynamic>{},
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
    void Function(String delta)? onDelta,
    void Function(Map<String, dynamic> event)? onActivity,
    WesiAiRequestCancellation? cancellation,
    bool thinkingMode = false,
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

class _LobbyControlledApi extends WesiAiApi {
  final Completer<WesiAiReply> reply = Completer<WesiAiReply>();
  int calls = 0;

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
    void Function(Map<String, dynamic> event)? onActivity,
    WesiAiRequestCancellation? cancellation,
    bool thinkingMode = false,
  }) {
    calls++;
    return reply.future;
  }
}

class _StreamingControlledApi extends WesiAiApi {
  final Completer<WesiAiReply> reply = Completer<WesiAiReply>();
  void Function(String delta)? onDelta;
  void Function(Map<String, dynamic> event)? activityCallback;

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
    void Function(Map<String, dynamic> event)? onActivity,
    WesiAiRequestCancellation? cancellation,
    bool thinkingMode = false,
  }) {
    this.onDelta = onDelta;
    activityCallback = onActivity;
    return reply.future;
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
      await controller.submitUserMessage('first'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => api.prompts.length == 1);

    for (var index = 0;
        index < WesiAiManagedChatController.maxQueuedTurns;
        index++) {
      expect(
        await controller.submitUserMessage('queued-$index'),
        WesiAiMessageSubmitResult.accepted,
      );
    }
    expect(
      controller.queuedTurnCount,
      WesiAiManagedChatController.maxQueuedTurns,
    );
    expect(
      await controller.submitUserMessage('overflow'),
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
      await controller.submitUserMessage('will-fail'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => api.prompts.length == 1);
    expect(
      await controller.submitUserMessage('must-run-after-failure'),
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
    expect(
      await controller.submitUserMessage('first-chat'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => api.prompts.length == 1);

    await controller.createConversation(WesiAiPersona.nirvana);
    final secondChat = controller.state.activeConversationId!;
    final attachment = WesiAiAttachment.fromBytes(
      name: 'context.txt',
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
    );
    expect(
      await controller.submitUserMessage(
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

  test('disposing screen controller does not interrupt accepted queue',
      () async {
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
      await controller.submitUserMessage('before-close'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => api.prompts.length == 1);
    expect(
      await controller.submitUserMessage('queued-before-close'),
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

  test('lobby completion after dispose never notifies disposed listeners',
      () async {
    final api = _LobbyControlledApi();
    final store = _MemoryStore('employee-1');
    final controller = WesiAiManagedChatController(store: store, api: api);
    await controller.load();
    await controller.createConversation(WesiAiPersona.lobby);

    final sending = controller.addUserMessage('проверь lobby lifecycle');
    await _waitUntil(() => api.calls == 1);
    controller.dispose();
    api.reply.complete(
      const WesiAiReply(
        answer: '__WESI_LOBBY_V1__[{"author":"zane","text":"Готово"}]',
        requestId: 'lobby-dispose-1',
      ),
    );

    await sending;
    expect(
      store.saved!.messages.any(
        (message) =>
            message.author == WesiAiMessageAuthor.zane &&
            message.text == 'Готово',
      ),
      isTrue,
    );
  });

  test('durable accept fails closed when pending storage cannot be written',
      () async {
    final api = _ControlledApi();
    final store = _MemoryStore('employee-1');
    final controller = WesiAiManagedChatController(
      store: store,
      api: api,
      processSessionId: 'storage-failure-session',
    );
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);
    store.failPendingWrites = true;

    expect(
      await controller.submitUserMessage('do not lose me'),
      WesiAiMessageSubmitResult.persistenceFailed,
    );
    expect(controller.queuedTurnCount, 0);
    expect(api.prompts, isEmpty);
  });

  test('queued text resumes after a real process-session restart', () async {
    final store = _MemoryStore('employee-1');
    final apiA = _ControlledApi();
    final controllerA = WesiAiManagedChatController(
      store: store,
      api: apiA,
      processSessionId: 'process-a',
    );
    await controllerA.load();
    await controllerA.createConversation(WesiAiPersona.zane);
    final conversationId = controllerA.state.activeConversationId!;

    expect(
      await controllerA.submitUserMessage('uncertain-inflight'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => apiA.prompts.length == 1);
    expect(
      await controllerA.submitUserMessage('resume-after-restart'),
      WesiAiMessageSubmitResult.accepted,
    );
    expect(
      store.pending.values.any(
        (item) =>
            item.text == 'uncertain-inflight' &&
            item.status == WesiAiPendingQueueStatus.inflight,
      ),
      isTrue,
    );
    expect(
      store.pending.values.any(
        (item) =>
            item.text == 'resume-after-restart' &&
            item.status == WesiAiPendingQueueStatus.queued,
      ),
      isTrue,
    );

    // Simulate the old UI disappearing and then a brand-new process session.
    // The old in-flight future deliberately never completes.
    controllerA.dispose();
    final apiB = _ControlledApi();
    final controllerB = WesiAiManagedChatController(
      store: store,
      api: apiB,
      processSessionId: 'process-b',
    );
    await controllerB.load();
    await _waitUntil(() => apiB.prompts.length == 1);

    expect(apiB.prompts, <String>['resume-after-restart']);
    expect(
      controllerB.state.messagesFor(conversationId).any(
            (message) =>
                message.metadata['code'] == 'WAI_QUEUE_RECOVERY_UNCERTAIN' &&
                message.metadata['recoverText'] == 'uncertain-inflight' &&
                message.text.contains('uncertain-inflight'),
          ),
      isTrue,
    );

    apiB.first.complete(
      const WesiAiReply(
        answer: 'reply:resume-after-restart',
        requestId: 'restart-1',
      ),
    );
    await _waitUntil(() => !controllerB.processing);
    expect(store.pending, isEmpty);
    expect(
      controllerB.state.messagesFor(conversationId).any(
            (message) =>
                message.author == WesiAiMessageAuthor.zane &&
                message.text == 'reply:resume-after-restart',
          ),
      isTrue,
    );
  });

  test('queued attachment survives as reattach intent, never as stored bytes',
      () async {
    final store = _MemoryStore('employee-1');
    final apiA = _ControlledApi();
    final controllerA = WesiAiManagedChatController(
      store: store,
      api: apiA,
      processSessionId: 'attachment-process-a',
    );
    await controllerA.load();
    await controllerA.createConversation(WesiAiPersona.nirvana);
    final conversationId = controllerA.state.activeConversationId!;

    expect(
      await controllerA.submitUserMessage('block-first'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => apiA.prompts.length == 1);
    final attachment = WesiAiAttachment.fromBytes(
      name: 'restart-context.txt',
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
    );
    expect(
      await controllerA.submitUserMessage(
        'use this after restart',
        attachments: <WesiAiAttachment>[attachment],
      ),
      WesiAiMessageSubmitResult.accepted,
    );

    final queuedAttachment = store.pending.values.firstWhere(
      (item) => item.text == 'use this after restart',
    );
    expect(queuedAttachment.attachments, hasLength(1));
    expect(
      queuedAttachment.attachments.single.keys.toSet(),
      <String>{'name', 'mimeType', 'byteSize'},
    );
    expect(
      queuedAttachment.attachments.single.containsKey('dataBase64'),
      isFalse,
    );
    expect(
      queuedAttachment.attachments.single.containsKey('localPath'),
      isFalse,
    );

    controllerA.dispose();
    final apiB = _ControlledApi();
    final controllerB = WesiAiManagedChatController(
      store: store,
      api: apiB,
      processSessionId: 'attachment-process-b',
    );
    await controllerB.load();

    expect(apiB.prompts, isEmpty);
    expect(store.pending, isEmpty);
    final messages = controllerB.state.messagesFor(conversationId);
    expect(
      messages.any(
        (message) =>
            message.metadata['code'] == 'WAI_REATTACH_REQUIRED' &&
            message.metadata['recoverText'] == 'use this after restart' &&
            message.text.contains('restart-context.txt'),
      ),
      isTrue,
    );
  });

  test(
      'same process session never steals or duplicates another controller queue',
      () async {
    final store = _MemoryStore('employee-1');
    final apiA = _ControlledApi();
    final controllerA = WesiAiManagedChatController(
      store: store,
      api: apiA,
      processSessionId: 'same-runtime',
    );
    await controllerA.load();
    await controllerA.createConversation(WesiAiPersona.zane);

    expect(
      await controllerA.submitUserMessage('first-owned'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => apiA.prompts.length == 1);
    expect(
      await controllerA.submitUserMessage('second-owned'),
      WesiAiMessageSubmitResult.accepted,
    );
    controllerA.dispose();

    final apiB = _ControlledApi();
    final controllerB = WesiAiManagedChatController(
      store: store,
      api: apiB,
      processSessionId: 'same-runtime',
    );
    await controllerB.load();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(apiB.prompts, isEmpty);
    expect(controllerB.queuedTurnCount, 0);
    expect(controllerB.processing, isTrue);
    expect(store.pending.length, 2);

    apiA.first.complete(
      const WesiAiReply(answer: 'reply:first-owned', requestId: 'owner-1'),
    );
    await _waitUntil(() => store.pending.isEmpty);
    await _waitUntil(() => !controllerB.processing);
    expect(apiA.prompts, <String>['first-owned', 'second-owned']);
    expect(apiB.prompts, isEmpty);
    expect(
      controllerB.state.messages.any(
        (message) => message.text == 'reply:second-owned',
      ),
      isTrue,
    );
  });

  test('uncertain recovery can be explicitly retried without automatic replay',
      () async {
    final store = _MemoryStore('employee-1');
    final apiA = _ControlledApi();
    final controllerA = WesiAiManagedChatController(
      store: store,
      api: apiA,
      processSessionId: 'manual-retry-a',
    );
    await controllerA.load();
    await controllerA.createConversation(WesiAiPersona.zane);
    final conversationId = controllerA.state.activeConversationId!;

    expect(
      await controllerA.submitUserMessage('manual retry payload'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => apiA.prompts.length == 1);
    controllerA.dispose();

    final apiB = _ControlledApi();
    final controllerB = WesiAiManagedChatController(
      store: store,
      api: apiB,
      processSessionId: 'manual-retry-b',
    );
    await controllerB.load();
    expect(apiB.prompts, isEmpty);
    expect(
      controllerB.state.messagesFor(conversationId).last.metadata['code'],
      'WAI_QUEUE_RECOVERY_UNCERTAIN',
    );
    expect(
      controllerB.state.messagesFor(conversationId).last.text,
      contains('manual retry payload'),
    );

    final retry = controllerB.regenerateLastResponse();
    await _waitUntil(() => apiB.prompts.length == 1);
    expect(apiB.prompts.single, 'manual retry payload');
    apiB.first.complete(
      const WesiAiReply(
        answer: 'reply:manual retry payload',
        requestId: 'manual-retry-1',
      ),
    );
    await retry;
    await _waitUntil(() => !controllerB.processing);
    expect(store.pending, isEmpty);
    expect(
      controllerB.state.messagesFor(conversationId).any(
            (message) =>
                message.author == WesiAiMessageAuthor.zane &&
                message.text == 'reply:manual retry payload',
          ),
      isTrue,
    );
  });

  test('durable acceptance serializes concurrent pending writes', () async {
    final api = _ControlledApi();
    final store = _MemoryStore('employee-1');
    store.pendingWriteGate = Completer<void>();
    final controller = WesiAiManagedChatController(
      store: store,
      api: api,
      processSessionId: 'accept-race-session',
    );
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);

    final first = controller.submitUserMessage('first durable write');
    await _waitUntil(() => store.pendingWriteCount == 1);
    expect(controller.processing, isTrue);
    expect(api.prompts, isEmpty);

    expect(
      await controller.submitUserMessage('second while first is saving'),
      WesiAiMessageSubmitResult.unavailable,
    );
    expect(controller.queuedTurnCount, 1);
    expect(store.pending, isEmpty);
    expect(api.prompts, isEmpty);

    store.pendingWriteGate!.complete();
    expect(await first, WesiAiMessageSubmitResult.accepted);
    await _waitUntil(() => api.prompts.length == 1);
    expect(api.prompts, <String>['first durable write']);

    api.first.complete(
      const WesiAiReply(
        answer: 'reply:first durable write',
        requestId: 'accept-race-1',
      ),
    );
    await _waitUntil(() => !controller.processing);
    expect(store.pending, isEmpty);
  });

  test('steer correction preempts active reply and runs before deferred work',
      () async {
    final api = _ControlledApi();
    final controller = await _controller(api);

    expect(
      await controller.submitUserMessage('проверь весь проект'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => api.prompts.length == 1);

    expect(
      await controller.submitUserMessage('После этого проверь Windows build'),
      WesiAiMessageSubmitResult.accepted,
    );
    expect(
      await controller.submitUserMessage(
        'Нет, не весь проект, проверяй только Android build',
      ),
      WesiAiMessageSubmitResult.accepted,
    );

    await _waitUntil(() => api.prompts.length >= 2);
    expect(
        api.prompts[1], 'Нет, не весь проект, проверяй только Android build');
    expect(api.prompts, isNot(contains('После этого проверь Windows build')));

    api.first.complete(
      const WesiAiReply(answer: 'устаревший ответ', requestId: 'old-request'),
    );
    await _waitUntil(() => !controller.processing);
    expect(
      controller.state.messages
          .any((message) => message.text == 'устаревший ответ'),
      isFalse,
    );
    expect(
      controller.state.messages.any(
        (message) => message.metadata['code'] == 'WAI_QUEUE_SUPERSEDED',
      ),
      isTrue,
    );
  });

  test('text control stops active work and cancels queued follow-ups',
      () async {
    final api = _ControlledApi();
    final controller = await _controller(api);

    expect(
      await controller.submitUserMessage('сделай аудит'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => api.prompts.length == 1);
    expect(
      await controller.submitUserMessage('После этого собери Windows'),
      WesiAiMessageSubmitResult.accepted,
    );
    expect(
      await controller.submitUserMessage('стой'),
      WesiAiMessageSubmitResult.accepted,
    );

    await _waitUntil(() => !controller.processing);
    expect(api.prompts, <String>['сделай аудит']);
    expect(
      controller.state.messages.any(
        (message) => message.metadata['code'] == 'WAI_CONTROL_APPLIED',
      ),
      isTrue,
    );
    expect(controller.queuedTurnCount, 0);

    api.first.complete(
      const WesiAiReply(answer: 'поздний ответ', requestId: 'late-request'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      controller.state.messages
          .any((message) => message.text == 'поздний ответ'),
      isFalse,
    );
  });

  test(
      'transport deltas are visible before final reply and collapse into one persisted message',
      () async {
    final api = _StreamingControlledApi();
    final store = _MemoryStore('employee-stream');
    final controller = WesiAiManagedChatController(store: store, api: api);
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);
    final conversationId = controller.state.activeConversationId!;

    final sending = controller.addUserMessage('stream me');
    await _waitUntil(() => api.onDelta != null && api.activityCallback != null);
    api.activityCallback!({
      'type': 'tool',
      'phase': 'start',
      'name': 'github_file_upsert',
    });
    api.activityCallback!({
      'type': 'tool',
      'phase': 'result',
      'name': 'github_file_upsert',
      'additions': 4,
      'deletions': 2,
      'files': ['lib/example.dart'],
    });
    api.onDelta!('При');
    api.onDelta!('вет');
    await _waitUntil(() => controller.state.messagesFor(conversationId).any(
          (message) =>
              message.metadata['transportStreaming'] == true &&
              message.text == 'Привет',
        ));

    api.reply
        .complete(const WesiAiReply(answer: 'Привет', requestId: 'stream-1'));
    await sending;
    final messages = controller.state.messagesFor(conversationId);
    expect(
        messages
            .where((message) => message.author == WesiAiMessageAuthor.zane)
            .length,
        1);
    expect(messages.last.text, 'Привет');
    expect(messages.last.metadata['transportStreamed'], isTrue);
    final activity = messages.last.metadata['activity'];
    expect(activity, isA<List>());
    final toolEvent = (activity as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .singleWhere((item) => item['sourceName'] == 'github_file_upsert');
    expect(toolEvent['additions'], 4);
    expect(toolEvent['deletions'], 2);
    expect(toolEvent['files'], ['lib/example.dart']);
    expect(toolEvent['status'], 'result');
    final persisted = store.saved!.messagesFor(conversationId).last;
    expect(persisted.text, 'Привет');
    expect(persisted.metadata['activity'], isA<List>());
    expect(persisted.metadata['workStartedAt'], isNotNull);
    expect(persisted.metadata['workDurationMs'], isA<int>());
  });

  test(
      'инструмент, вызванный субагентом, подписан именем и меткой (субагент)',
      () async {
    // agentName в событии — сигнал, что инструмент запустил не сам ведущий,
    // а временный специалист. Без метки (субагент) в подписи человек не
    // может на глаз отличить его от Co-Agent, чьи события выглядят похоже.
    final api = _StreamingControlledApi();
    final store = _MemoryStore('employee-subagent-tool');
    final controller = WesiAiManagedChatController(store: store, api: api);
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);
    final conversationId = controller.state.activeConversationId!;

    final sending = controller.addUserMessage('проверь форму входа');
    await _waitUntil(() => api.onDelta != null && api.activityCallback != null);
    api.activityCallback!({
      'type': 'tool',
      'phase': 'start',
      'role': 'subagent',
      'agentName': 'Security Reviewer',
      'name': 'knowledge_search',
    });
    api.activityCallback!({
      'type': 'tool',
      'phase': 'result',
      'role': 'subagent',
      'agentName': 'Security Reviewer',
      'name': 'knowledge_search',
    });
    api.onDelta!('Готово');
    await _waitUntil(() => controller.state.messagesFor(conversationId).any(
          (message) =>
              message.metadata['transportStreaming'] == true &&
              message.text == 'Готово',
        ));

    api.reply.complete(
        const WesiAiReply(answer: 'Готово', requestId: 'subagent-tool-1'));
    await sending;
    final activity = controller.state.messagesFor(conversationId).last
        .metadata['activity'] as List;
    final toolEvent = activity
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .singleWhere((item) => item['sourceName'] == 'knowledge_search');
    expect(toolEvent['label'], contains('Security Reviewer'));
    expect(toolEvent['label'], contains('(субагент)'));
    expect(toolEvent['status'], 'result');
  });
}
