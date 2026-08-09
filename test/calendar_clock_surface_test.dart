import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('completed Calendar is the only legacy calendar entry point', () {
    final legacy =
        File('lib/features/calendar/calendar_screen.dart').readAsStringSync();
    final calendar = File('lib/features/calendar/calendar_v2_screen.dart')
        .readAsStringSync();

    expect(legacy.trim(), "export 'calendar_v2_screen.dart';");
    expect(calendar, contains('ModuleStage.ready'));
    expect(calendar, contains('_CalendarView.month'));
    expect(calendar, contains('_CalendarView.week'));
    expect(calendar, contains('_CalendarView.year'));
    expect(calendar, contains('CalendarEventService'));
    expect(calendar, contains('onChanged: (_) => setDialogState(() {})'));
    expect(calendar, isNot(contains('ModuleStage.partial')));
  });

  test('home clock opens the four-tool Time Center', () {
    final home = File('lib/features/home/home_screen.dart').readAsStringSync();
    final router = File('lib/core/routes/app_router.dart').readAsStringSync();
    final screen = File('lib/features/time_center/time_center_screen.dart')
        .readAsStringSync();

    expect(home, contains("Navigator.pushNamed(context, '/time')"));
    expect(
      home,
      isNot(contains("onTap: () => Navigator.pushNamed(context, '/calendar')")),
    );
    expect(home, contains('Открыть центр времени'));
    expect(router, contains("case '/time':"));
    expect(router, contains('TimeCenterScreen'));
    expect(screen, contains('Icons.alarm_rounded'));
    expect(screen, contains('Icons.notifications_active_outlined'));
    expect(screen, contains('Icons.hourglass_bottom_rounded'));
    expect(screen, contains('Icons.timer_outlined'));
    expect(screen, contains('onChanged: (_) => setDialogState(() {})'));
  });

  test(
      'persistent schedules are restored and Android can schedule exact alarms',
      () {
    final main = File('lib/main.dart').readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final scheduler = File(
      'lib/features/time_center/services/time_notification_scheduler.dart',
    ).readAsStringSync();

    expect(main, contains('TimeScheduleAutomation.shared.start();'));
    expect(pubspec, contains('timezone: ^0.9.4'));
    expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
    expect(manifest, contains('ScheduledNotificationReceiver'));
    expect(manifest, contains('ScheduledNotificationBootReceiver'));
    expect(scheduler, contains('zonedSchedule('));
    expect(scheduler, contains('requestExactAlarmsPermission'));
  });
}
