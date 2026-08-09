import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/calendar/models/calendar_event.dart';

void main() {
  group('CalendarEvent recurrence', () {
    test('weekly event occurs only on matching weekday after start', () {
      final event = CalendarEvent(
        id: 'weekly',
        title: 'Weekly sync',
        startAt: DateTime(2026, 8, 3, 10, 30), // Monday
        repeat: CalendarRepeat.weekly,
      );

      expect(event.occursOn(DateTime(2026, 8, 10)), isTrue);
      expect(event.occursOn(DateTime(2026, 8, 11)), isFalse);
      expect(event.occursOn(DateTime(2026, 7, 27)), isFalse);
    });

    test('monthly event clamps day to the last day of short month', () {
      final event = CalendarEvent(
        id: 'month-end',
        title: 'Month end',
        startAt: DateTime(2028, 1, 31, 9),
        repeat: CalendarRepeat.monthly,
      );

      expect(event.occursOn(DateTime(2028, 2, 29)), isTrue);
      expect(event.occursOn(DateTime(2028, 2, 28)), isFalse);
      expect(event.occursOn(DateTime(2028, 4, 30)), isTrue);
    });

    test('yearly leap-day event clamps in a non-leap year', () {
      final event = CalendarEvent(
        id: 'leap',
        title: 'Leap event',
        startAt: DateTime(2028, 2, 29, 12),
        repeat: CalendarRepeat.yearly,
      );

      expect(event.occursOn(DateTime(2029, 2, 28)), isTrue);
      expect(event.occursOn(DateTime(2029, 2, 27)), isFalse);
    });

    test('nextOccurrences never returns a past occurrence', () {
      final event = CalendarEvent(
        id: 'daily',
        title: 'Daily',
        startAt: DateTime(2026, 8, 1, 8),
        repeat: CalendarRepeat.daily,
      );
      final now = DateTime(2026, 8, 9, 9);
      final next = event.nextOccurrences(now, count: 3);

      expect(next, hasLength(3));
      expect(next.first, DateTime(2026, 8, 10, 8));
      expect(next.every((value) => value.isAfter(now)), isTrue);
    });
  });
}
