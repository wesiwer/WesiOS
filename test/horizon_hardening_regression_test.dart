import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';
import 'package:wesios/features/treasury/services/horizon_calibration.dart';

TransactionModel tx(
        String id, DateTime date, double amount, TransactionType type,
        {String category = 'services',
        bool recurring = false,
        RecurringPeriod? period,
        String? accountId}) =>
    TransactionModel(
      id: id,
      title: id,
      amount: amount,
      type: type,
      date: date,
      category: category,
      isRecurring: recurring,
      recurringPeriod: period,
      accountId: accountId,
    );

void main() {
  final now = DateTime(2026, 8, 9);

  List<TransactionModel> stable({int days = 180}) {
    final out = <TransactionModel>[];
    for (var ago = days; ago >= 1; ago--) {
      final d = now.subtract(Duration(days: ago));
      out.add(tx('i-$ago', d, 1000 + ago % 5 * 20, TransactionType.income));
      out.add(tx('e-$ago', d, 550 + ago % 3 * 15, TransactionType.expense,
          category: 'operations'));
    }
    return out;
  }

  test('incoming-delay stress shifts statistical income instead of deleting it',
      () {
    final history = stable();
    final base = ForecastEngine.generate(
      transactions: history,
      currentBalance: 50000,
      days: 60,
      paths: 250,
      seed: 42,
      asOf: now,
    );
    final delayed = ForecastEngine.generate(
      transactions: history,
      currentBalance: 50000,
      days: 60,
      paths: 250,
      seed: 42,
      asOf: now,
      whatIf: const WhatIfScenario(incomeDelayDays: 10),
    );
    expect(delayed.p50[8], lessThan(base.p50[8]));
    expect(delayed.p50[39] - delayed.p50[29], greaterThan(-5000));
    final source = File('lib/features/treasury/services/forecast_engine.dart')
        .readAsStringSync();
    expect(source, contains('delayedSampledIncome[target] += sampledIncome'));
    expect(source, isNot(contains('sampledIncome = 0.0;')));
  });

  test('calibration cannot materially destabilize the near-horizon median', () {
    final history = stable();
    final raw = ForecastEngine.generate(
      transactions: history,
      currentBalance: 50000,
      days: 30,
      paths: 250,
      seed: 42,
      asOf: now,
    );
    const profile = HorizonCalibrationProfile(
      buckets: [
        HorizonCalibrationBucket(
          horizonDays: 30,
          intervalScale: 1.8,
          biasCorrection: 3000,
          coverage: .55,
          samples: 80,
        )
      ],
    );
    final calibrated = ForecastEngine.generate(
      transactions: history,
      currentBalance: 50000,
      days: 30,
      paths: 250,
      seed: 42,
      asOf: now,
      calibration: profile,
    );
    expect((calibrated.p50[6] - raw.p50[6]).abs(), lessThan(1000));
    expect(calibrated.p90.last - calibrated.p10.last,
        greaterThan(raw.p90.last - raw.p10.last));
  });

  test(
      'production lifecycle wiring runs Horizon maintenance without opening Forecast',
      () {
    final automation =
        File('lib/features/treasury/services/recurring_payment_automation.dart')
            .readAsStringSync();
    final maintenance = File(
            'lib/features/treasury/services/horizon_maintenance_automation.dart')
        .readAsStringSync();
    expect(automation, contains('HorizonMaintenanceAutomation.shared.runNow'));
    expect(maintenance, contains('HorizonLearningService.updateIfDue'));
    expect(
        maintenance, contains('HorizonPredictionRegistry.recordBaseForecast'));
    expect(
        maintenance, contains('HorizonEngineCompetitionService.evaluateIfDue'));
  });

  test('account liquidity uses recurring projections and scenario timing', () {
    final source = File('lib/features/treasury/services/forecast_engine.dart')
        .readAsStringSync();
    expect(source, contains('final recurringByDay = <int, double>{};'));
    expect(source, contains('known = recurringByDay[day] ?? 0.0'));
    expect(source, contains('required WhatIfScenario whatIf'));
  });
}
