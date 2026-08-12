import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';

void main() {
  final now = DateTime(2026, 8, 9);

  test('business incoming cash is shifted, not deleted, by delay stress', () {
    final event = HorizonCashEvent(
      title: 'Client payment',
      amount: 20000,
      date: now.add(const Duration(days: 5)),
      probability: 1,
      committed: false,
      source: 'crm',
      riskSource: 'crm:client',
    );

    ForecastResult run(WhatIfScenario scenario) => ForecastEngine.generate(
          transactions: const [],
          currentBalance: 10000,
          days: 30,
          paths: 120,
          seed: 42,
          asOf: now,
          businessEvents: [event],
          whatIf: scenario,
        );

    final base = run(WhatIfScenario.none);
    final delayed = run(const WhatIfScenario(incomeDelayDays: 10));

    expect(base.p50[4] - delayed.p50[4], greaterThan(15000));
    // The payment reappears 10 days later instead of disappearing from the
    // scenario completely.
    expect(delayed.p50[14] - delayed.p50[13], greaterThan(15000));
  });

  test('statistical incoming delay uses an explicit queue', () {
    final source = File('lib/features/treasury/services/forecast_engine.dart')
        .readAsStringSync();
    expect(source, contains('delayedSampledIncome'));
    expect(source, contains('delayedExpectedIncome'));
    expect(source, contains('delayedIncomeShock'));
    expect(
      source,
      isNot(contains(
          'whatIf.incomeDelayDays > 0 && day <= whatIf.incomeDelayDays')),
    );
  });
}
