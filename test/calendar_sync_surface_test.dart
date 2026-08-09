import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('own Calendar events participate in WesiOS device sync', () {
    final codec = File('lib/core/sync/sync_codec.dart').readAsStringSync();

    expect(codec, contains('class CalendarEventsSync'));
    expect(codec, contains("String get name => 'calendar_events'"));
    expect(codec, contains('CalendarEventsSync(),'));
    expect(codec, contains('CalendarEventService.revision.value++'));
  });

  test('device-local Time Center state is not added to SyncCodec', () {
    final codec = File('lib/core/sync/sync_codec.dart').readAsStringSync();

    expect(codec, isNot(contains("String get name => 'alarms'")));
    expect(codec, isNot(contains("String get name => 'timer'")));
    expect(codec, isNot(contains("String get name => 'stopwatch'")));
  });
}
