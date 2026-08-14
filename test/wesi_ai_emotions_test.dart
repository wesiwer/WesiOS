import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_emotions.dart';

void main() {
  test('mood fades faster than relational traces', () {
    final start = DateTime(2026, 8, 14, 10);
    final state = WesiAiPersonaEmotionState(
      levels: const {
        WesiAiEmotion.sadness: 0.9,
        WesiAiEmotion.anger: 0.6,
      },
      traces: [
        WesiAiEmotionTrace(
          id: 'hurt-1',
          subject: 'user',
          summary: 'Пользователь поддержал неприятную шутку.',
          weight: 0.9,
          createdAt: start,
          updatedAt: start,
        ),
      ],
      updatedAt: start,
      stance: 'всё ещё ждёт извинений',
    );

    final afterDay = state.decayed(start.add(const Duration(hours: 24)));

    expect(afterDay.level(WesiAiEmotion.sadness), lessThan(0.3));
    expect(afterDay.level(WesiAiEmotion.anger), lessThan(0.25));
    expect(afterDay.traces, isNotEmpty);
    expect(afterDay.traces.first.weight, greaterThan(0.6));
  });

  test('multiple emotions can remain active at the same time', () {
    final now = DateTime(2026, 8, 14, 10);
    final state = WesiAiPersonaEmotionState(
      levels: const {
        WesiAiEmotion.joy: 0.72,
        WesiAiEmotion.surprise: 0.41,
        WesiAiEmotion.trust: 0.55,
      },
      updatedAt: now,
    );

    expect(state.active.length, 3);
    expect(state.active.first.key, WesiAiEmotion.joy);
  });

  test('old state json without emotions stays backwards compatible', () {
    final snapshot = WesiAiEmotionSnapshot.fromJson(null);
    expect(snapshot.zane.active, isEmpty);
    expect(snapshot.nirvana.active, isEmpty);
  });
}
