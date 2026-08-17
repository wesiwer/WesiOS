import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_chat_models.dart';
import 'package:wesios/features/ai/wesi_ai_api.dart';

void main() {
  test('transport history bounds long prior replies and keeps newest context',
      () {
    final now = DateTime(2026, 8, 17);
    final history = List<WesiAiMessage>.generate(90, (index) {
      final payload = index == 89
          ? 'newest-${List<String>.filled(50000, 'x').join()}'
          : 'message-$index-${List<String>.filled(5000, 'y').join()}';
      return WesiAiMessage(
        id: 'm$index',
        conversationId: 'conversation',
        employeeId: 'owner',
        author:
            index.isEven ? WesiAiMessageAuthor.user : WesiAiMessageAuthor.zane,
        text: payload,
        createdAt: now.add(Duration(seconds: index)),
      );
    });

    final result = WesiAiApi.transportHistory(history);
    expect(result.length,
        lessThanOrEqualTo(WesiAiApi.maxTransportHistoryMessages));
    expect(
      result.every((item) =>
          (item['text'] ?? '').length <=
          WesiAiApi.maxTransportHistoryMessageChars),
      isTrue,
    );
    expect(
      result.fold<int>(0, (sum, item) => sum + (item['text'] ?? '').length),
      lessThanOrEqualTo(WesiAiApi.maxTransportHistoryTotalChars),
    );
    expect(result.last['text'], startsWith('newest-'));
    expect(
      result.any(
          (item) => (item['text'] ?? '').contains('WESI_AI_HISTORY_TRUNCATED')),
      isTrue,
    );
  });
}
