import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../time_center/services/time_notification_scheduler.dart';
import '../models/calendar_event.dart';

class CalendarEventService {
  CalendarEventService({TimeNotificationScheduler? scheduler})
      : _scheduler = scheduler ?? TimeNotificationScheduler.instance;

  static const String boxName = 'wesios_calendar_events';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final TimeNotificationScheduler _scheduler;
  Box<dynamic>? _box;

  Future<Box<dynamic>> get _store async {
    _box ??= await Hive.openBox<dynamic>(boxName);
    return _box!;
  }

  Future<List<CalendarEvent>> getAll() async {
    final box = await _store;
    final result = <CalendarEvent>[];
    for (final value in box.values) {
      if (value is Map) {
        try {
          final event = CalendarEvent.fromJson(value);
          if (event.id.isNotEmpty && event.title.trim().isNotEmpty) {
            result.add(event);
          }
        } catch (_) {}
      }
    }
    result.sort((a, b) => a.startAt.compareTo(b.startAt));
    return result;
  }

  Future<void> save(CalendarEvent event) async {
    await (await _store).put(event.id, event.toJson());
    revision.value++;
    await _scheduleEvent(event);
  }

  Future<void> delete(String id) async {
    await (await _store).delete(id);
    revision.value++;
    await _scheduler.cancelSeries('calendar_$id');
  }

  Future<void> setEnabled(CalendarEvent event, bool enabled) async {
    await save(event.copyWith(enabled: enabled));
  }

  Future<void> restoreSchedules({DateTime? now}) async {
    final currentNow = now ?? DateTime.now();
    for (final event in await getAll()) {
      await _scheduleEvent(event, now: currentNow);
    }
  }

  Future<void> _scheduleEvent(CalendarEvent event, {DateTime? now}) async {
    final prefix = 'calendar_${event.id}';
    final minutes = event.reminderMinutesBefore;
    if (!event.enabled || minutes == null) {
      await _scheduler.cancelSeries(prefix);
      return;
    }

    final currentNow = now ?? DateTime.now();
    final occurrences = event.nextOccurrences(currentNow, count: 24);
    final reminders = <ScheduledTimeNotification>[];
    for (final occurrence in occurrences) {
      final at = occurrence.subtract(Duration(minutes: minutes));
      if (!at.isAfter(currentNow)) continue;
      reminders.add(
        ScheduledTimeNotification(
          at: at,
          title: event.title,
          body: event.notes.trim().isEmpty
              ? (WesiLocale.isRussian
                  ? 'Событие календаря WesiOS'
                  : 'WesiOS calendar event')
              : event.notes.trim(),
        ),
      );
    }
    await _scheduler.scheduleSeries(
      keyPrefix: prefix,
      notifications: reminders,
    );
  }
}
