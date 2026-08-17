import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_attachment.dart';
import 'package:wesios/features/ai/models/wesi_ai_conversation.dart';
import 'package:wesios/features/ai/models/wesi_ai_message.dart';
import 'package:wesios/features/ai/models/wesi_ai_project.dart';
import 'package:wesios/features/ai/models/wesi_ai_tier.dart';
import 'package:wesios/features/ai/storage/wesi_ai_local_store.dart';
import 'package:wesios/features/ai/wesi_ai_api.dart';
import 'package:wesios/features/ai/wesi_ai_managed_controller.dart';
import 'package:wesios/features/ai/wesi_ai_memory_api.dart';
import 'package:wesios/features/ai/wesi_ai_memory_engine.dart';

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
    void Function(Map<String, dynamic> event)? onActivity,
    WesiAiRequestCancellation? cancellation,
    bool thinkingMode = false,
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

void main() {
  test('memory engine compacts old turns but preserves recent context', () async {
    final store = _MemoryStore('employee-memory');
    final api = _CaptureApi();
    final memoryApi = _FakeMemoryApi();
    final controller = WesiAiManagedChatController(
      store: store,
      api: api,
      memoryApi: memoryApi,
      memoryCompactAfterMessages: 6,
      memoryKeepRecentMessages: 4,
    );

    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);

    for (var i = 0; i < 4; i++) {
      await controller.send('Сообщение $i');
    }

    expect(memoryApi.calls, greaterThanOrEqualTo(1));
    expect(controller.state.conversationSummaries, isNotEmpty);
    expect(api.histories.last.length, lessThanOrEqualTo(4));
  });

  test('memory processor failure does not break the conversation', () async {
    final store = _MemoryStore('employee-memory-fail');
    final api = _CaptureApi();
    final memoryApi = _FakeMemoryApi(fail: true);
    final controller = WesiAiManagedChatController(
      store: store,
      api: api,
      memoryApi: memoryApi,
      memoryCompactAfterMessages: 2,
      memoryKeepRecentMessages: 2,
    );

    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);
    await controller.send('Первое');
    await controller.send('Второе');

    expect(controller.currentMessages.last.content, 'Готово');
    expect(controller.currentConversation?.memoryProcessing, isFalse);
  });
}
