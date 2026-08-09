import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/time_center/models/time_center_models.dart';

void main() {
  group('TimeAlarm', () {
    test('one-shot alarm returns only its future occurrence', () {
      final alarm = TimeAlarm(
        id: 'once',
        label: 'Wake',
        firstAt: DateTime(2026, 8, 10, 7, 30),
      );

      expect(
        alarm.nextOccurrences(DateTime(2026, 8, 9, 12)),
        [DateTime(2026, 8, 10, 7, 30)],
      );
      expect(
        alarm.nextOccurrences(DateTime(2026, 8, 10, 8)),
        isEmpty,
      );
    });

    test('weekday alarm keeps selected weekdays and clock time', () {
      final alarm = TimeAlarm(
        id: 'work',
        label: 'Work',
        firstAt: DateTime(2026, 8, 1, 6, 45),
        repeatWeekdays: const {DateTime.monday, DateTime.wednesday},
      );
      final next = alarm.nextOccurrences(DateTime(2026, 8, 9, 12), count: 3);

      expect(next, [
        DateTime(2026, 8, 10, 6, 45),
        DateTime(2026, 8, 12, 6, 45),
        DateTime(2026, 8, 17, 6, 45),
      ]);
    });
  });

  group('TimeReminder', () {
    test('monthly repeat clamps 31st into short month', () {
      final reminder = TimeReminder(
        id: 'billing',
        title: 'Billing',
        at: DateTime(2028, 1, 31, 18),
        repeat: ReminderRepeat.monthly,
      );
      final next = reminder.nextOccurrences(DateTime(2028, 2, 1), count: 2);

      expect(next.first, DateTime(2028, 2, 29, 18));
      expect(next.last, DateTime(2028, 3, 29, 18));
    });
  });

  group('persistent timer', () {
    test('remaining time is calculated from absolute target', () {
      final now = DateTime(2026, 8, 9, 12);
      final state = TimeTimerState(
        durationMs: 600000,
        remainingMs: 600000,
        targetAtMs: now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
        running: true,
      );

      expect(state.remainingAt(now.add(const Duration(minutes: 4))), 360000);
      expect(state.remainingAt(now.add(const Duration(minutes: 11))), 0);
      expect(state.isFinishedAt(now.add(const Duration(minutes: 11))), isTrue);
    });
  });

  group('persistent stopwatch', () {
    test('elapsed time includes time passed since start timestamp', () {
      final started = DateTime(2026, 8, 9, 12);
      final state = TimeStopwatchState(
        accumulatedMs: 1250,
        startedAtMs: started.millisecondsSinceEpoch,
      );

      expect(
        state.elapsedAt(started.add(const Duration(seconds: 3))),
        4250,
      );
    });

    test('json roundtrip preserves laps and running state', () {
      const state = TimeStopwatchState(
        accumulatedMs: 5000,
        startedAtMs: 123456,
        lapsMs: [4200, 2100],
      );
      final restored = TimeStopwatchState.fromJson(state.toJson());

      expect(restored.accumulatedMs, 5000);
      expect(restored.startedAtMs, 123456);
      expect(restored.lapsMs, [4200, 2100]);
      expect(restored.running, isTrue);
    });
  });
}
