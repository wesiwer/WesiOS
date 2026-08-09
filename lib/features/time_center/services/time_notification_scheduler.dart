import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/notifications/wesi_notifications.dart';

class ScheduledTimeNotification {
  final DateTime at;
  final String title;
  final String body;

  const ScheduledTimeNotification({
    required this.at,
    required this.title,
    required this.body,
  });
}

/// Системное расписание для будильников, напоминаний, таймера и Calendar.
///
/// Android получает настоящие scheduled notifications, которые переживают
/// закрытие приложения и перезагрузку устройства. Desktop fallback держит
/// таймер в текущем процессе; при следующем запуске сервисы восстанавливают
/// расписание из Hive и просроченное уведомление показывается сразу.
class TimeNotificationScheduler {
  TimeNotificationScheduler._();

  static final TimeNotificationScheduler instance =
      TimeNotificationScheduler._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final Map<String, Timer> _desktopTimers = <String, Timer>{};

  bool _initialized = false;
  bool _permissionsRequested = false;

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
    'wesios_time_center',
    'WesiOS Time Center',
    channelDescription: 'Будильники, напоминания, таймеры и календарь',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    if (!kIsWeb && Platform.isAndroid) {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/launcher_icon'),
        ),
      );
    }
    _initialized = true;
  }

  Future<void> _requestPermissions() async {
    if (_permissionsRequested || kIsWeb || !Platform.isAndroid) return;
    _permissionsRequested = true;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      await android?.requestNotificationsPermission();
    } catch (_) {}
    try {
      await android?.requestExactAlarmsPermission();
    } catch (_) {
      // Если exact alarm не разрешён, schedule может быть отклонён Android.
      // Данные всё равно остаются в Hive, поэтому пользователь ничего не
      // теряет и сможет повторить после выдачи разрешения.
    }
  }

  Future<bool> schedule({
    required String key,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    await init();
    await cancel(key);

    final now = DateTime.now();
    if (!at.isAfter(now)) {
      if (now.difference(at) <= const Duration(minutes: 5)) {
        await _showFallback(key, title, body);
        return true;
      }
      return false;
    }

    if (!kIsWeb && Platform.isAndroid) {
      await _requestPermissions();
      try {
        await _plugin.zonedSchedule(
          stableId(key),
          title,
          body,
          tz.TZDateTime.from(at.toUtc(), tz.UTC),
          const NotificationDetails(android: _androidDetails),
          androidAllowWhileIdle: true,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: '/time',
        );
        return true;
      } catch (error) {
        debugPrint('Time schedule failed for $key: $error');
        return false;
      }
    }

    final delay = at.difference(now);
    _desktopTimers[key] = Timer(delay, () async {
      _desktopTimers.remove(key);
      await _showFallback(key, title, body);
    });
    return true;
  }

  Future<void> scheduleSeries({
    required String keyPrefix,
    required List<ScheduledTimeNotification> notifications,
    int capacity = 24,
  }) async {
    await cancelSeries(keyPrefix, capacity: capacity);
    final limited = notifications.take(capacity).toList();
    for (var i = 0; i < limited.length; i++) {
      final item = limited[i];
      await schedule(
        key: '${keyPrefix}_$i',
        at: item.at,
        title: item.title,
        body: item.body,
      );
    }
  }

  Future<void> cancel(String key) async {
    _desktopTimers.remove(key)?.cancel();
    if (!kIsWeb && Platform.isAndroid) {
      await init();
      try {
        await _plugin.cancel(stableId(key));
      } catch (_) {}
    }
  }

  Future<void> cancelSeries(String keyPrefix, {int capacity = 24}) async {
    for (var i = 0; i < capacity; i++) {
      await cancel('${keyPrefix}_$i');
    }
  }

  Future<void> _showFallback(String key, String title, String body) async {
    await WesiNotifications.show(
      WesiNotification(
        id: 'time_$key',
        title: title,
        body: body,
        kind: NotifyKind.alert,
        route: '/time',
      ),
    );
  }

  @visibleForTesting
  static int stableId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash & 0x7fffffff;
  }
}
