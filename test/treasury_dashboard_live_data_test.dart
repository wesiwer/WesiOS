import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Treasury Dashboard is wired to live services, not demo placeholders',
      () async {
    final source = await File(
      'lib/features/treasury/treasury_dashboard_screen.dart',
    ).readAsString();

    expect(source, contains('final TreasuryService _treasury'));
    expect(source, contains('final AnalyticsService _analyticsService'));
    expect(source, contains('getAllTransactions()'));
    expect(source, contains('getCurrentBalance()'));
    expect(source, contains('detectAnomalies()'));
    expect(source, contains('getRecurringPayments()'));
    expect(source, contains('generateForecast(days: 30)'));
    expect(source, contains('build(periodDays: 30)'));
    expect(source, contains("_go('/treasury/operations')"));
    expect(source, contains("_go('/treasury/forecast')"));

    expect(source, isNot(contains(r'$47,250.00')));
    expect(source, isNot(contains('Category Distribution')));
    expect(source, isNot(contains('P10 / P50 / P90 Forecast Chart')));
    expect(source, isNot(contains('Manage recurring payments')));
    expect(
      RegExp(r'on(?:Tap|Pressed):\s*\(\)\s*\{\s*\}').hasMatch(source),
      isFalse,
    );
  });
}
