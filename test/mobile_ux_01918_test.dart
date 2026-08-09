import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';
import 'package:wesios/features/treasury/services/what_if_store.dart';

void main() {
  test('home keeps WesiOS name and exact balance', () {
    final source =
        File('lib/features/home/home_screen.dart').readAsStringSync();
    expect(source, contains('showText: true'));
    expect(source, contains('CurrencyService.formatExactSmart(_balance)'));
    expect(source, contains('onCalendarTap:'));
  });

  test('more tab marks calendar ready and respects system inset', () {
    final source = File('lib/features/home/more_tab.dart').readAsStringSync();
    expect(source, contains('MediaQuery.paddingOf(context).top'));
    final start = source.indexOf("route: '/calendar'");
    expect(start, greaterThanOrEqualTo(0));
    expect(source.substring(start, (start + 620).clamp(0, source.length)),
        contains('stage: ModuleStage.ready'));
  });

  test('transaction editor has both date and time picker', () {
    final source =
        File('lib/features/treasury/widgets/add_transaction_dialog.dart')
            .readAsStringSync();
    expect(source, contains('showDatePicker'));
    expect(source, contains('showTimePicker'));
    expect(source, contains('_formatTime(_selectedDate)'));
  });

  test('operations have date sections and visible operation time', () {
    final source =
        File('lib/features/treasury/operations_screen.dart').readAsStringSync();
    expect(source, contains('List<Widget> _transactionRows()'));
    expect(source, contains('Widget _dateHeader(DateTime day)'));
    expect(source, contains('_formatTime(tx.date)'));
  });

  test('theme applies launcher icon and light alias is distinct', () {
    final main = File('lib/main.dart').readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(main,
        contains('ThemeNotifier.instance.addListener(AppIconService.apply)'));
    expect(manifest, contains('@drawable/launcher_icon_light'));
  });

  test('roadmap exposes zoom and team picker', () {
    final source =
        File('lib/features/roadmap/roadmap_screen.dart').readAsStringSync();
    expect(source, contains('double _timelineZoom = 1.0'));
    expect(source, contains('final double zoom;'));
    expect(source, contains('EmployeeOrCustomField('));
  });

  test('short forecast no longer forces 30 days of history', () {
    final source = File('lib/features/treasury/forecast_chart_screen.dart')
        .readAsStringSync();
    expect(source, contains('_forecastDays.clamp(7, 90)'));
  });

  test('recurring what-if survives preset JSON roundtrip', () {
    final preset = WhatIfPreset(
      id: 'recurring',
      name: 'Monthly investment',
      createdAt: DateTime.now(),
      scenario: WhatIfScenario(
        events: [
          WhatIfEvent(
            title: 'Investment',
            amount: 10000,
            type: TransactionType.income,
            date: DateTime.now().add(const Duration(days: 1)),
            recurringPeriod: RecurringPeriod.monthly,
          ),
        ],
      ),
    );
    final decoded = WhatIfPreset.fromJson(preset.toJson());
    expect(decoded, isNotNull);
    expect(decoded!.scenario.events.first.recurringPeriod,
        RecurringPeriod.monthly);
  });

  test('stopwatch source no longer formats hundredths', () {
    final source = File('lib/features/time_center/time_center_screen.dart')
        .readAsStringSync();
    final start = source.indexOf('String _formatStopwatchMs');
    expect(start, greaterThanOrEqualTo(0));
    final window =
        source.substring(start, (start + 700).clamp(0, source.length));
    expect(window, isNot(contains('hundredths')));
  });
}
