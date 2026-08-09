import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/time_center/services/time_notification_scheduler.dart';

void main() {
  test('Windows notification launch arguments round-trip arbitrary text', () {
    final args = TimeNotificationScheduler.windowsLaunchArgumentsFor(
      key: 'alarm_утро_07:30',
      title: 'Будильник: подъём',
      body: 'Проверка символов: & | < > " \' / Привет',
    );

    final decoded =
        TimeNotificationScheduler.decodeWindowsLaunchArguments(args);

    expect(decoded, isNotNull);
    expect(decoded!['key'], 'alarm_утро_07:30');
    expect(decoded['title'], 'Будильник: подъём');
    expect(decoded['body'], 'Проверка символов: & | < > " \' / Привет');
  });

  test('Windows notification launch parser rejects incomplete payload', () {
    expect(
      TimeNotificationScheduler.decodeWindowsLaunchArguments(
        const ['--wesios-time-notification'],
      ),
      isNull,
    );
  });

  test('Windows task names are deterministic and Task Scheduler safe', () {
    final first = TimeNotificationScheduler.windowsTaskNameFor('timer_main');
    final second = TimeNotificationScheduler.windowsTaskNameFor('timer_main');
    final other = TimeNotificationScheduler.windowsTaskNameFor('alarm_main');

    expect(first, second);
    expect(first, isNot(other));
    expect(first, matches(RegExp(r'^WesiOS_Time_[0-9]+$')));
  });

  test('main handles notification-only launch before normal desktop startup', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final handler =
        mainSource.indexOf('TimeNotificationScheduler.handleLaunchArguments');
    final desktopStartup = mainSource.indexOf('windowManager.ensureInitialized');
    final hiveStartup = mainSource.indexOf('Hive.initFlutter');

    expect(mainSource, contains('void main(List<String> arguments) async'));
    expect(handler, greaterThanOrEqualTo(0));
    expect(desktopStartup, greaterThan(handler));
    expect(hiveStartup, greaterThan(handler));
  });

  test('Windows scheduling uses Task Scheduler with process fallback', () {
    final scheduler = File(
      'lib/features/time_center/services/time_notification_scheduler.dart',
    ).readAsStringSync();

    expect(scheduler, contains('Register-ScheduledTask'));
    expect(scheduler, contains('New-ScheduledTaskTrigger -Once'));
    expect(scheduler, contains('New-ScheduledTaskSettingsSet -StartWhenAvailable'));
    expect(scheduler, contains('Platform.resolvedExecutable'));
    expect(scheduler, contains('_scheduleDesktopTimer'));
  });
}
