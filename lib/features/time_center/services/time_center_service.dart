import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/sync/sync_account_scope.dart';
import '../models/time_center_models.dart';
import 'time_notification_scheduler.dart';

class TimeCenterService {
  TimeCenterService({TimeNotificationScheduler? scheduler})
      : _scheduler = scheduler ?? TimeNotificationScheduler.instance;

  static const String baseBoxName = 'wesios_time_center';
  static String get boxName => SyncAccountScope.boxName(baseBoxName);
  static const String _alarmsKey = 'alarms';
  static const String _remindersKey = 'reminders';
  static const String _timerKey = 'timer';
  static const String _stopwatchKey = 'stopwatch';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final TimeNotificationScheduler _scheduler;
  Box<dynamic>? _box;
  String? _openedBoxName;

  Future<Box<dynamic>> get _store async {
    final currentName = boxName;
    if (_box?.isOpen == true && _openedBoxName == currentName) return _box!;
    if (_box?.isOpen == true && _openedBoxName != currentName) {
      await _box!.close();
    }
    _box = await Hive.openBox<dynamic>(currentName);
    _openedBoxName = currentName;
    return _box!;
  }

  Future<List<TimeAlarm>> getAlarms() async {
    final raw = (await _store).get(_alarmsKey);
    if (raw is! List) return <TimeAlarm>[];
    final result = <TimeAlarm>[];
    for (final item in raw) {
      if (item is Map) {
        try {
          result.add(TimeAlarm.fromJson(item));
        } catch (_) {}
      }
    }
    result.sort((a, b) {
      final aa = a.nextOccurrences(DateTime.now(), count: 1);
      final bb = b.nextOccurrences(DateTime.now(), count: 1);
      if (aa.isEmpty && bb.isEmpty) return a.label.compareTo(b.label);
      if (aa.isEmpty) return 1;
      if (bb.isEmpty) return -1;
      return aa.first.compareTo(bb.first);
    });
    return result;
  }

  Future<void> saveAlarm(TimeAlarm alarm) async {
    final list = await getAlarms();
    final index = list.indexWhere((item) => item.id == alarm.id);
    if (index < 0) {
      list.add(alarm);
    } else {
      list[index] = alarm;
    }
    await _saveAlarms(list);
    await _scheduleAlarm(alarm);
  }

  Future<void> deleteAlarm(String id) async {
    final list = await getAlarms()
      ..removeWhere((item) => item.id == id);
    await _saveAlarms(list);
    await _scheduler.cancelSeries('alarm_$id');
  }

  Future<void> setAlarmEnabled(TimeAlarm alarm, bool enabled) async {
    await saveAlarm(alarm.copyWith(enabled: enabled));
  }

  Future<void> _saveAlarms(List<TimeAlarm> alarms) async {
    await (await _store).put(
      _alarmsKey,
      alarms.map((item) => item.toJson()).toList(),
    );
    revision.value++;
  }

  Future<List<TimeReminder>> getReminders() async {
    final raw = (await _store).get(_remindersKey);
    if (raw is! List) return <TimeReminder>[];
    final result = <TimeReminder>[];
    for (final item in raw) {
      if (item is Map) {
        try {
          result.add(TimeReminder.fromJson(item));
        } catch (_) {}
      }
    }
    result.sort((a, b) => a.at.compareTo(b.at));
    return result;
  }

  Future<void> saveReminder(TimeReminder reminder) async {
    final list = await getReminders();
    final index = list.indexWhere((item) => item.id == reminder.id);
    if (index < 0) {
      list.add(reminder);
    } else {
      list[index] = reminder;
    }
    await _saveReminders(list);
    await _scheduleReminder(reminder);
  }

  Future<void> deleteReminder(String id) async {
    final list = await getReminders()
      ..removeWhere((item) => item.id == id);
    await _saveReminders(list);
    await _scheduler.cancelSeries('reminder_$id');
  }

  Future<void> setReminderEnabled(TimeReminder reminder, bool enabled) async {
    await saveReminder(reminder.copyWith(enabled: enabled));
  }

  Future<void> _saveReminders(List<TimeReminder> reminders) async {
    await (await _store).put(
      _remindersKey,
      reminders.map((item) => item.toJson()).toList(),
    );
    revision.value++;
  }

  Future<TimeTimerState> getTimer() async {
    final raw = (await _store).get(_timerKey);
    if (raw is Map) return TimeTimerState.fromJson(raw);
    return const TimeTimerState();
  }

  Future<TimeTimerState> setTimerDuration(Duration duration) async {
    final ms = duration.inMilliseconds.clamp(1000, 24 * 60 * 60 * 1000);
    final state = TimeTimerState(durationMs: ms, remainingMs: ms);
    await _saveTimer(state);
    await _scheduler.cancel('timer_main');
    return state;
  }

  Future<TimeTimerState> startTimer({DateTime? now}) async {
    final currentNow = now ?? DateTime.now();
    final current = await getTimer();
    final remaining = current.remainingAt(currentNow);
    if (remaining <= 0) return current;
    final target = currentNow.add(Duration(milliseconds: remaining));
    final state = current.copyWith(
      remainingMs: remaining,
      targetAtMs: target.millisecondsSinceEpoch,
      running: true,
    );
    await _saveTimer(state);
    await _scheduler.schedule(
      key: 'timer_main',
      at: target,
      title: WesiLocale.isRussian ? 'Таймер завершён' : 'Timer finished',
      body:
          WesiLocale.isRussian ? 'Время вышло.' : 'The countdown has finished.',
    );
    return state;
  }

  Future<TimeTimerState> pauseTimer({DateTime? now}) async {
    final currentNow = now ?? DateTime.now();
    final current = await getTimer();
    final remaining = current.remainingAt(currentNow);
    final state = current.copyWith(
      remainingMs: remaining,
      clearTarget: true,
      running: false,
    );
    await _saveTimer(state);
    await _scheduler.cancel('timer_main');
    return state;
  }

  Future<TimeTimerState> resetTimer() async {
    final current = await getTimer();
    final state = TimeTimerState(
      durationMs: current.durationMs,
      remainingMs: current.durationMs,
    );
    await _saveTimer(state);
    await _scheduler.cancel('timer_main');
    return state;
  }

  Future<TimeTimerState> reconcileTimer({DateTime? now}) async {
    final currentNow = now ?? DateTime.now();
    final current = await getTimer();
    if (!current.running || !current.isFinishedAt(currentNow)) return current;
    final finished = current.copyWith(
      remainingMs: 0,
      clearTarget: true,
      running: false,
    );
    await _saveTimer(finished);
    return finished;
  }

  Future<void> _saveTimer(TimeTimerState state) async {
    await (await _store).put(_timerKey, state.toJson());
    revision.value++;
  }

  Future<TimeStopwatchState> getStopwatch() async {
    final raw = (await _store).get(_stopwatchKey);
    if (raw is Map) return TimeStopwatchState.fromJson(raw);
    return const TimeStopwatchState();
  }

  Future<TimeStopwatchState> toggleStopwatch({DateTime? now}) async {
    final currentNow = now ?? DateTime.now();
    final current = await getStopwatch();
    final TimeStopwatchState next;
    if (current.running) {
      next = current.copyWith(
        accumulatedMs: current.elapsedAt(currentNow),
        clearStart: true,
      );
    } else {
      next = current.copyWith(startedAtMs: currentNow.millisecondsSinceEpoch);
    }
    await _saveStopwatch(next);
    return next;
  }

  Future<TimeStopwatchState> addLap({DateTime? now}) async {
    final currentNow = now ?? DateTime.now();
    final current = await getStopwatch();
    if (!current.running) return current;
    final elapsed = current.elapsedAt(currentNow);
    final next = current.copyWith(lapsMs: <int>[elapsed, ...current.lapsMs]);
    await _saveStopwatch(next);
    return next;
  }

  Future<TimeStopwatchState> resetStopwatch() async {
    const state = TimeStopwatchState();
    await _saveStopwatch(state);
    return state;
  }

  Future<void> _saveStopwatch(TimeStopwatchState state) async {
    await (await _store).put(_stopwatchKey, state.toJson());
    revision.value++;
  }

  Future<void> restoreSchedules({DateTime? now}) async {
    final currentNow = now ?? DateTime.now();

    final alarms = await getAlarms();
    var alarmsChanged = false;
    for (var i = 0; i < alarms.length; i++) {
      var alarm = alarms[i];
      if (alarm.enabled &&
          !alarm.repeats &&
          !alarm.firstAt.isAfter(currentNow)) {
        alarm = alarm.copyWith(enabled: false);
        alarms[i] = alarm;
        alarmsChanged = true;
      }
      await _scheduleAlarm(alarm, now: currentNow);
    }
    if (alarmsChanged) await _saveAlarms(alarms);

    final reminders = await getReminders();
    var remindersChanged = false;
    for (var i = 0; i < reminders.length; i++) {
      var reminder = reminders[i];
      if (reminder.enabled &&
          reminder.repeat == ReminderRepeat.none &&
          !reminder.at.isAfter(currentNow)) {
        reminder = reminder.copyWith(enabled: false);
        reminders[i] = reminder;
        remindersChanged = true;
      }
      await _scheduleReminder(reminder, now: currentNow);
    }
    if (remindersChanged) await _saveReminders(reminders);

    final timer = await reconcileTimer(now: currentNow);
    if (timer.running && timer.targetAtMs != null) {
      await _scheduler.schedule(
        key: 'timer_main',
        at: DateTime.fromMillisecondsSinceEpoch(timer.targetAtMs!),
        title: WesiLocale.isRussian ? 'Таймер завершён' : 'Timer finished',
        body: WesiLocale.isRussian
            ? 'Время вышло.'
            : 'The countdown has finished.',
      );
    }
  }

  Future<void> _scheduleAlarm(TimeAlarm alarm, {DateTime? now}) async {
    final prefix = 'alarm_${alarm.id}';
    if (!alarm.enabled) {
      await _scheduler.cancelSeries(prefix);
      return;
    }
    final occurrences = alarm.nextOccurrences(now ?? DateTime.now());
    final title = alarm.label.trim().isEmpty
        ? (WesiLocale.isRussian ? 'Будильник' : 'Alarm')
        : alarm.label.trim();
    await _scheduler.scheduleSeries(
      keyPrefix: prefix,
      notifications: occurrences
          .map((at) => ScheduledTimeNotification(
                at: at,
                title: title,
                body:
                    WesiLocale.isRussian ? 'Будильник WesiOS' : 'WesiOS alarm',
              ))
          .toList(),
    );
  }

  Future<void> _scheduleReminder(TimeReminder reminder, {DateTime? now}) async {
    final prefix = 'reminder_${reminder.id}';
    if (!reminder.enabled) {
      await _scheduler.cancelSeries(prefix);
      return;
    }
    final occurrences = reminder.nextOccurrences(now ?? DateTime.now());
    await _scheduler.scheduleSeries(
      keyPrefix: prefix,
      notifications: occurrences
          .map((at) => ScheduledTimeNotification(
                at: at,
                title: reminder.title,
                body: reminder.notes.trim().isEmpty
                    ? (WesiLocale.isRussian
                        ? 'Напоминание WesiOS'
                        : 'WesiOS reminder')
                    : reminder.notes.trim(),
              ))
          .toList(),
    );
  }
}