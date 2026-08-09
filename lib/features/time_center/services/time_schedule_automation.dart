import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../calendar/services/calendar_event_service.dart';
import 'time_center_service.dart';

class TimeScheduleAutomation with WidgetsBindingObserver {
  TimeScheduleAutomation({
    TimeCenterService? timeCenter,
    CalendarEventService? calendar,
    DateTime Function()? now,
    this.minInterval = const Duration(minutes: 2),
  })  : _timeCenter = timeCenter ?? TimeCenterService(),
        _calendar = calendar ?? CalendarEventService(),
        _now = now ?? DateTime.now;

  static final TimeScheduleAutomation shared = TimeScheduleAutomation();

  final TimeCenterService _timeCenter;
  final CalendarEventService _calendar;
  final DateTime Function() _now;
  final Duration minInterval;

  Future<void>? _inFlight;
  DateTime? _lastCompletedAt;
  bool _observing = false;

  void start() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(runNow(force: true));
  }

  void stop() {
    if (!_observing) return;
    WidgetsBinding.instance.removeObserver(this);
    _observing = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(runNow());
  }

  Future<void> runNow({bool force = false}) {
    final running = _inFlight;
    if (running != null) return running;
    final previous = _lastCompletedAt;
    if (!force &&
        previous != null &&
        _now().difference(previous) < minInterval) {
      return Future<void>.value();
    }
    final future = _run();
    _inFlight = future;
    return future;
  }

  Future<void> _run() async {
    try {
      final now = _now();
      await _timeCenter.restoreSchedules(now: now);
      await _calendar.restoreSchedules(now: now);
      _lastCompletedAt = _now();
    } catch (error, stackTrace) {
      debugPrint('Time schedule restore failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _inFlight = null;
    }
  }
}
