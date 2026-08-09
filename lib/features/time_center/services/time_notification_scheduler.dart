import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';
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

class _WindowsScheduledItem {
  final String key;
  final DateTime at;
  final String title;
  final String body;

  const _WindowsScheduledItem({
    required this.key,
    required this.at,
    required this.title,
    required this.body,
  });
}

/// Системное расписание для будильников, напоминаний, таймера и Calendar.
///
/// Android получает настоящие scheduled notifications, которые переживают
/// закрытие приложения и перезагрузку устройства. Windows регистрирует
/// одноразовые задачи в Task Scheduler: в нужный момент система запускает
/// WesiOS в notification-only режиме, показывает toast и сразу завершает
/// процесс, не открывая обычный интерфейс. Для macOS/Linux остаётся
/// in-process fallback с восстановлением расписания при следующем запуске.
class TimeNotificationScheduler {
  TimeNotificationScheduler._();

  static final TimeNotificationScheduler instance =
      TimeNotificationScheduler._();

  static const String _windowsLaunchFlag = '--wesios-time-notification';
  static const String _windowsKeyArg = '--wesi-key';
  static const String _windowsTitleArg = '--wesi-title';
  static const String _windowsBodyArg = '--wesi-body';

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

  /// Ранний Windows entrypoint для задач Task Scheduler.
  ///
  /// Вызывается из main() до window_manager/Hive. Если процесс был запущен
  /// системным планировщиком, обычный WesiOS UI вообще не поднимается.
  static Future<bool> handleLaunchArguments(List<String> arguments) async {
    if (kIsWeb || !Platform.isWindows) return false;
    if (!arguments.contains(_windowsLaunchFlag)) return false;

    final payload = decodeWindowsLaunchArguments(arguments);
    if (payload == null) {
      // Повреждённая системная задача не должна внезапно открыть WesiOS.
      return true;
    }

    try {
      await localNotifier.setup(
        appName: 'WesiOS',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      final toast = LocalNotification(
        title: payload['title']!,
        body: payload['body']!,
      );
      await toast.show();
    } catch (error) {
      debugPrint('Windows time notification failed: $error');
    }

    final key = payload['key']!;
    if (key.isNotEmpty) {
      // Одноразовая задача больше не нужна. Ошибка удаления не критична:
      // она всё равно не повторится, а следующее сохранение перезапишет её.
      try {
        await instance._cancelWindowsTasks([key]);
      } catch (_) {}
    }
    return true;
  }

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

    final now = DateTime.now();
    if (!at.isAfter(now)) {
      if (now.difference(at) <= const Duration(minutes: 5)) {
        await _showFallback(key, title, body);
        return true;
      }
      return false;
    }

    if (!kIsWeb && Platform.isAndroid) {
      await cancel(key);
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

    if (!kIsWeb && Platform.isWindows) {
      _desktopTimers.remove(key)?.cancel();
      final registered = await _scheduleWindowsBatch([
        _WindowsScheduledItem(key: key, at: at, title: title, body: body),
      ]);
      if (registered) return true;

      // Корпоративная политика Windows может запретить Task Scheduler.
      // Пока приложение открыто, всё равно сохраняем рабочий fallback.
      _scheduleDesktopTimer(key: key, at: at, title: title, body: body);
      return true;
    }

    await cancel(key);
    _scheduleDesktopTimer(key: key, at: at, title: title, body: body);
    return true;
  }

  Future<void> scheduleSeries({
    required String keyPrefix,
    required List<ScheduledTimeNotification> notifications,
    int capacity = 24,
  }) async {
    await init();
    final limited = notifications.take(capacity).toList();

    if (!kIsWeb && Platform.isWindows) {
      final allKeys = [
        for (var i = 0; i < capacity; i++) '${keyPrefix}_$i',
      ];
      for (final key in allKeys) {
        _desktopTimers.remove(key)?.cancel();
      }
      await _cancelWindowsTasks(allKeys);

      final now = DateTime.now();
      final items = <_WindowsScheduledItem>[];
      for (var i = 0; i < limited.length; i++) {
        final item = limited[i];
        final key = '${keyPrefix}_$i';
        if (!item.at.isAfter(now)) {
          if (now.difference(item.at) <= const Duration(minutes: 5)) {
            await _showFallback(key, item.title, item.body);
          }
          continue;
        }
        items.add(_WindowsScheduledItem(
          key: key,
          at: item.at,
          title: item.title,
          body: item.body,
        ));
      }

      final registered = await _scheduleWindowsBatch(items);
      if (!registered) {
        for (final item in items) {
          _scheduleDesktopTimer(
            key: item.key,
            at: item.at,
            title: item.title,
            body: item.body,
          );
        }
      }
      return;
    }

    await cancelSeries(keyPrefix, capacity: capacity);
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
      return;
    }
    if (!kIsWeb && Platform.isWindows) {
      await _cancelWindowsTasks([key]);
    }
  }

  Future<void> cancelSeries(String keyPrefix, {int capacity = 24}) async {
    if (!kIsWeb && Platform.isWindows) {
      final keys = [
        for (var i = 0; i < capacity; i++) '${keyPrefix}_$i',
      ];
      for (final key in keys) {
        _desktopTimers.remove(key)?.cancel();
      }
      await _cancelWindowsTasks(keys);
      return;
    }

    for (var i = 0; i < capacity; i++) {
      await cancel('${keyPrefix}_$i');
    }
  }

  void _scheduleDesktopTimer({
    required String key,
    required DateTime at,
    required String title,
    required String body,
  }) {
    _desktopTimers.remove(key)?.cancel();
    final delay = at.difference(DateTime.now());
    if (delay <= Duration.zero) {
      unawaited(_showFallback(key, title, body));
      return;
    }
    _desktopTimers[key] = Timer(delay, () async {
      _desktopTimers.remove(key);
      await _showFallback(key, title, body);
    });
  }

  Future<bool> _scheduleWindowsBatch(
    List<_WindowsScheduledItem> items,
  ) async {
    if (items.isEmpty) return true;

    final executable = Platform.resolvedExecutable;
    final script = StringBuffer()
      ..writeln(r"$ErrorActionPreference = 'Stop'")
      ..writeln(r'$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable');

    for (final item in items) {
      final launchArgs = windowsLaunchArgumentsFor(
        key: item.key,
        title: item.title,
        body: item.body,
      ).join(' ');
      final localIso = item.at.toLocal().toIso8601String();
      script
        ..writeln(
          '\$action = New-ScheduledTaskAction -Execute ${_powerShellQuote(executable)} -Argument ${_powerShellQuote(launchArgs)}',
        )
        ..writeln(
          '\$trigger = New-ScheduledTaskTrigger -Once -At ([DateTime]::Parse(${_powerShellQuote(localIso)}, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeLocal))',
        )
        ..writeln(
          'Register-ScheduledTask -TaskName ${_powerShellQuote(windowsTaskNameFor(item.key))} -Action \$action -Trigger \$trigger -Settings \$settings -Force | Out-Null',
        );
    }

    return _runPowerShell(script.toString());
  }

  Future<bool> _cancelWindowsTasks(List<String> keys) async {
    if (keys.isEmpty) return true;
    final script = StringBuffer()
      ..writeln(r"$ErrorActionPreference = 'SilentlyContinue'");
    for (final key in keys) {
      script.writeln(
        'Unregister-ScheduledTask -TaskName ${_powerShellQuote(windowsTaskNameFor(key))} -Confirm:\$false -ErrorAction SilentlyContinue',
      );
    }
    return _runPowerShell(script.toString());
  }

  Future<bool> _runPowerShell(String script) async {
    if (kIsWeb || !Platform.isWindows) return false;
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final powershell =
        '$root\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
    try {
      final result = await Process.run(
        powershell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          script,
        ],
      );
      if (result.exitCode != 0) {
        debugPrint(
          'Windows Task Scheduler failed (${result.exitCode}): ${result.stderr}',
        );
        return false;
      }
      return true;
    } catch (error) {
      debugPrint('Windows Task Scheduler unavailable: $error');
      return false;
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
  static List<String> windowsLaunchArgumentsFor({
    required String key,
    required String title,
    required String body,
  }) =>
      [
        _windowsLaunchFlag,
        '$_windowsKeyArg=${_encodeArgument(key)}',
        '$_windowsTitleArg=${_encodeArgument(title)}',
        '$_windowsBodyArg=${_encodeArgument(body)}',
      ];

  @visibleForTesting
  static Map<String, String>? decodeWindowsLaunchArguments(
    List<String> arguments,
  ) {
    if (!arguments.contains(_windowsLaunchFlag)) return null;

    String? rawValue(String name) {
      final prefix = '$name=';
      for (final argument in arguments) {
        if (argument.startsWith(prefix)) {
          return argument.substring(prefix.length);
        }
      }
      return null;
    }

    final key = _decodeArgument(rawValue(_windowsKeyArg));
    final title = _decodeArgument(rawValue(_windowsTitleArg));
    final body = _decodeArgument(rawValue(_windowsBodyArg));
    if (key == null || title == null || body == null) return null;
    return {'key': key, 'title': title, 'body': body};
  }

  static String _encodeArgument(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');

  static String? _decodeArgument(String? value) {
    if (value == null) return null;
    try {
      final padding = (4 - value.length % 4) % 4;
      final normalized = '$value${'=' * padding}';
      return utf8.decode(base64Url.decode(normalized));
    } catch (_) {
      return null;
    }
  }

  static String _powerShellQuote(String value) =>
      "'${value.replaceAll("'", "''")}'";

  @visibleForTesting
  static String windowsTaskNameFor(String value) =>
      'WesiOS_Time_${stableId(value)}';

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
