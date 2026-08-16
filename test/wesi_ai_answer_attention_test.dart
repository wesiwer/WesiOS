import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/runtime/wesi_ai_answer_attention.dart';

void main() {
  tearDown(WesiAiAnswerAttention.reset);

  test('answer-ready delivery follows chat/app lifecycle state', () {
    expect(
      WesiAiAnswerAttention.deliveryFor(
        foreground: true,
        chatVisible: true,
      ),
      WesiAiAnswerDelivery.inChat,
    );
    expect(
      WesiAiAnswerAttention.deliveryFor(
        foreground: true,
        chatVisible: false,
      ),
      WesiAiAnswerDelivery.inAppBanner,
    );
    expect(
      WesiAiAnswerAttention.deliveryFor(
        foreground: false,
        chatVisible: true,
      ),
      WesiAiAnswerDelivery.systemNotification,
    );
    expect(
      WesiAiAnswerAttention.deliveryFor(
        foreground: false,
        chatVisible: false,
      ),
      WesiAiAnswerDelivery.systemNotification,
    );
  });

  test('AI notification deep-link keeps exact conversation id', () {
    const event = WesiAiAnswerReady(
      conversationId: 'conversation_42',
      conversationTitle: 'Проверка',
      personaLabel: 'Зейн',
      preview: 'Ответ готов',
      completedAt: DateTime(2026, 8, 16, 18, 0),
    );

    expect(
      WesiAiAnswerAttention.conversationFromRoute(event.route),
      'conversation_42',
    );
    expect(
      WesiAiAnswerAttention.conversationFromRoute('/ai'),
      isNull,
    );
    expect(
      WesiAiAnswerAttention.conversationFromRoute('/tasks?conversation=x'),
      isNull,
    );
  });

  test('navigator observer distinguishes AI chat hidden under another route', () {
    final observer = WesiAiAnswerAttention.navigatorObserver;
    final ai = MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/ai'),
      builder: (_) => const SizedBox.shrink(),
    );
    final tasks = MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/tasks'),
      builder: (_) => const SizedBox.shrink(),
    );

    observer.didPush(ai, null);
    expect(WesiAiAnswerAttention.chatVisible, isTrue);

    observer.didPush(tasks, ai);
    expect(WesiAiAnswerAttention.chatVisible, isFalse);

    observer.didPop(tasks, ai);
    expect(WesiAiAnswerAttention.chatVisible, isTrue);
  });
}
