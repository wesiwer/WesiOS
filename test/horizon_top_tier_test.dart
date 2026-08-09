import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/account_liquidity_service.dart';
import 'package:wesios/features/treasury/services/forecast_backtest.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';
import 'package:wesios/features/treasury/services/horizon_calibration.dart';
import 'package:wesios/features/treasury/services/horizon_contract_memory.dart';
import 'package:wesios/features/treasury/services/horizon_scenarios.dart';

TransactionModel tx({
  required String id,
  required DateTime date,
  required double amount,
  required TransactionType type,
  String category = 'core',
  bool recurring = false,
  RecurringPeriod? period,
  String? accountId,
}) =>
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

List<TransactionModel> stableHistory(DateTime now, {int days = 240}) {
  final result = <TransactionModel>[];
  for (var i = days; i >= 1; i--) {
    final day = now.subtract(Duration(days: i));
    if (i % 2 == 0) {
      result.add(tx(
        id: 'inc-$i',
        date: day,
        amount: 1200 + (i % 7) * 35,
        type: TransactionType.income,
        category: 'services',
      ));
    }
    if (i % 3 != 0) {
      result.add(tx(
        id: 'exp-$i',
        date: day,
        amount: 420 + (i % 5) * 20,
        type: TransactionType.expense,
        category: 'operations',
      ));
    }
  }
  return result;
}

void main() {
  final now = DateTime(2026, 8, 9);

  group('Wesi Horizon honesty foundation', () {
    test(
        'a lucky recent month mean-reverts instead of becoming millionaire math',
        () {
      final history = stableHistory(now, days: 300);
      for (var i = 30; i >= 1; i--) {
        history.add(tx(
          id: 'lucky-$i',
          date: now.subtract(Duration(days: i)),
          amount: 6500 + i * 20,
          type: TransactionType.income,
          category: 'one-lucky-client',
        ));
      }

      final result = ForecastEngine.generate(
        transactions: history,
        currentBalance: 100000,
        days: 365,
        paths: 350,
        seed: 42,
        asOf: now,
      );

      expect(result.confidence, isNot(ForecastConfidence.insufficient));
      expect(result.driftCapPerDay, greaterThanOrEqualTo(0));
      expect(result.p50.last, lessThan(100000 + 6500 * 365 * 0.35));

      final firstMonthSlope = (result.p50[29] - 100000) / 30;
      final lastMonthSlope = (result.p50[364] - result.p50[334]) / 30;
      expect(
          lastMonthSlope.abs(), lessThan(firstMonthSlope.abs() * 0.75 + 150));

      // Explicit guard against absurd compounding/extrapolation from the lucky
      // month. Use the actually observed last-30-day net pace: `recentNetPerDay`
      // deliberately excludes shock days and now represents ordinary cash.
      final recentCutoff = now.subtract(const Duration(days: 30));
      final observedRecentNet = history
          .where((tx) => tx.date.isAfter(recentCutoff))
          .fold<double>(
            0,
            (sum, tx) =>
                sum +
                (tx.type == TransactionType.income ? tx.amount : -tx.amount),
          );
      final naiveLuckyYear = 100000 + (observedRecentNet / 30) * 365;
      expect(result.p50.last, lessThan(naiveLuckyYear * 0.80));
    });

    test('low-data mode admits uncertainty instead of a razor-thin truth', () {
      final result = ForecastEngine.generate(
        transactions: [
          tx(
            id: 'weak-history-a',
            date: now.subtract(const Duration(days: 7)),
            amount: 10000,
            type: TransactionType.income,
          ),
          tx(
            id: 'weak-history-b',
            date: now.subtract(const Duration(days: 3)),
            amount: 2500,
            type: TransactionType.expense,
          ),
          tx(
            id: 'weak-history-c',
            date: now.subtract(const Duration(days: 1)),
            amount: 1800,
            type: TransactionType.income,
          ),
        ],
        currentBalance: 30000,
        days: 180,
        paths: 300,
        seed: 42,
        asOf: now,
      );

      expect(result.confidence, ForecastConfidence.low);
      expect(result.uncertaintyScale, greaterThan(1));
      expect(result.p90[29] - result.p10[29], greaterThan(0));
      expect(result.p90[179] - result.p10[179],
          greaterThan(result.p90[29] - result.p10[29]));
      expect(
        result.actionPrompts.any((p) => p.code.contains('low')),
        isTrue,
      );
    });

    test('same UI seed is deterministic while alternate seed changes paths',
        () {
      final history = stableHistory(now);
      ForecastResult run(int seed) => ForecastEngine.generate(
            transactions: history,
            currentBalance: 50000,
            days: 60,
            paths: 250,
            seed: seed,
            asOf: now,
          );

      final a = run(42);
      final b = run(42);
      final c = run(83);
      expect(a.p50, b.p50);
      expect(a.p10, b.p10);
      expect(c.p10, isNot(a.p10));
    });

    test('weekly seasonality is not cloned unchanged into the far future', () {
      final history = <TransactionModel>[];
      for (var i = 210; i >= 1; i--) {
        final day = now.subtract(Duration(days: i));
        history.add(tx(
          id: 'weekly-$i',
          date: day,
          amount: day.weekday == DateTime.friday ? 5000 : 500,
          type: TransactionType.income,
          category: 'weekly',
        ));
        history.add(tx(
          id: 'weekly-exp-$i',
          date: day,
          amount: 400,
          type: TransactionType.expense,
          category: 'fixed',
        ));
      }
      final result = ForecastEngine.generate(
        transactions: history,
        currentBalance: 50000,
        days: 365,
        paths: 250,
        seed: 42,
        asOf: now,
      );
      expect(result.seasonalityApplied, isTrue);
      // Public weekday factors describe detected history; the far trajectory
      // itself must not preserve the same weekly amplitude forever.
      double weeklyRange(int start) {
        final slice = result.p50.sublist(start, start + 7);
        return slice.reduce(max) - slice.reduce(min);
      }

      expect(weeklyRange(330), lessThan(weeklyRange(7) * 1.25 + 500));
    });
  });

  group('Calibration and backtest', () {
    test('coverage calibration widens interval and bias moves the median', () {
      final history = stableHistory(now);
      final identity = ForecastEngine.generate(
        transactions: history,
        currentBalance: 60000,
        days: 30,
        paths: 300,
        seed: 42,
        asOf: now,
      );
      const bucket = HorizonCalibrationBucket(
        horizonDays: 30,
        intervalScale: 2,
        biasCorrection: -1200,
        coverage: 0.4,
        samples: 60,
      );
      const profile = HorizonCalibrationProfile(buckets: [bucket]);
      final calibrated = ForecastEngine.generate(
        transactions: history,
        currentBalance: 60000,
        days: 30,
        paths: 300,
        seed: 42,
        asOf: now,
        calibration: profile,
      );

      final rawWidth = identity.p90.last - identity.p10.last;
      final calibratedWidth = calibrated.p90.last - calibrated.p10.last;
      expect(calibratedWidth, closeTo(rawWidth * 2, rawWidth * 0.03 + 1));
      expect(calibrated.p50.last - identity.p50.last, closeTo(-1200, 2));
    });

    test(
        'risk calibration bins shrink empirical probability without fake certainty',
        () {
      const bucket = HorizonCalibrationBucket(
        horizonDays: 30,
        riskBins: [
          RiskCalibrationBin(
            lower: 0.10,
            upper: 0.25,
            observedRate: 0.40,
            samples: 40,
          ),
        ],
      );
      final adjusted = bucket.calibrateRisk(0.20);
      expect(adjusted, greaterThan(0.20));
      expect(adjusted, lessThan(0.40));
    });

    test('multi-horizon backtest keeps 14/30/90/180 separate', () {
      final history = stableHistory(now, days: 520);
      final evaluation = ForecastBacktest.runMultiHorizon(
        transactions: history,
        currentBalance: 90000,
        now: now,
        horizons: const [14, 30, 90, 180],
        seeds: const [11, 29],
        maxOriginsPerHorizon: 1,
        paths: 100,
      );
      expect(
        evaluation.metrics.map((m) => m.horizonDays).toList(),
        [14, 30, 90, 180],
      );
      expect(evaluation.metrics.every((m) => m.samples > 0), isTrue);
      expect(evaluation.seedCount, 2);
    });
  });

  group('Cash structure, stress and decisions', () {
    test('committed cash is separated and explained', () {
      final history = stableHistory(now, days: 120)
        ..add(tx(
          id: 'known-future-rent',
          date: now.add(const Duration(days: 10)),
          amount: 30000,
          type: TransactionType.expense,
          category: 'rent',
        ));
      final result = ForecastEngine.generate(
        transactions: history,
        currentBalance: 100000,
        days: 45,
        paths: 250,
        seed: 42,
        asOf: now,
      );
      expect(result.committedNearTerm, greaterThanOrEqualTo(30000));
      expect(result.committedNetByDay[9], lessThanOrEqualTo(-30000));
      expect(result.explanations.any((e) => e.day == 10), isTrue);
      expect(
          result.safetyBuffer,
          closeTo(100000 - result.recommendedReserve - result.committedNearTerm,
              1));
    });

    test(
        'uncertain business cash stays probabilistic instead of becoming committed',
        () {
      final history = stableHistory(now, days: 120);
      final result = ForecastEngine.generate(
        transactions: history,
        currentBalance: 50000,
        days: 30,
        paths: 400,
        seed: 42,
        asOf: now,
        businessEvents: [
          HorizonCashEvent(
            title: 'CRM deal',
            amount: 40000,
            date: now.add(const Duration(days: 15)),
            probability: 0.35,
            committed: false,
            source: 'crm',
          ),
        ],
      );
      expect(result.committedNetByDay[14], 0);
      expect(result.explanations.any((e) => e.source == 'crm'), isTrue);
      expect(result.knownCashShare, lessThan(1));
    });

    test(
        'stress package has base/conservative/aggressive/stress and stress worsens cash',
        () async {
      final history = stableHistory(now, days: 150);
      final base = ForecastEngine.generate(
        transactions: history,
        currentBalance: 40000,
        days: 90,
        paths: 250,
        seed: 42,
        asOf: now,
      );
      final package = await HorizonScenarioService.buildDefaultPackage(
        base: base,
        transactions: history,
        currentBalance: 40000,
        days: 90,
        calibration: HorizonCalibrationProfile.identity,
      );
      expect(package.map((e) => e.key).toSet(),
          containsAll({'base', 'conservative', 'aggressive', 'stress'}));
      final stress = package.firstWhere((e) => e.key == 'stress');
      final baseSummary = package.firstWhere((e) => e.key == 'base');
      expect(stress.endingP50, lessThan(baseSummary.endingP50));
      expect(stress.maximumGapRisk,
          greaterThanOrEqualTo(baseSummary.maximumGapRisk));
    });

    test('What-If exposes direct risk/runway delta', () {
      final history = stableHistory(now, days: 120);
      final base = ForecastEngine.generate(
        transactions: history,
        currentBalance: 25000,
        days: 60,
        paths: 300,
        seed: 42,
        asOf: now,
      );
      final stressed = ForecastEngine.generate(
        transactions: history,
        currentBalance: 25000,
        days: 60,
        paths: 300,
        seed: 42,
        asOf: now,
        whatIf: const WhatIfScenario(oneOffExpenseShock: 30000),
      );
      final delta =
          HorizonScenarioService.riskDelta(base: base, scenario: stressed);
      expect(delta.scenarioMaximumRisk,
          greaterThanOrEqualTo(delta.baseMaximumRisk));
      expect(delta.riskDelta, greaterThanOrEqualTo(0));
    });

    test('account liquidity reports risk in the needed location', () {
      final history = stableHistory(now, days: 90)
        ..add(tx(
          id: 'account-payment',
          date: now.add(const Duration(days: 5)),
          amount: 25000,
          type: TransactionType.expense,
          accountId: 'operating',
        ));
      final result = ForecastEngine.generate(
        transactions: history,
        currentBalance: 80000,
        days: 30,
        paths: 200,
        seed: 42,
        asOf: now,
        accounts: const [
          AccountLiquiditySnapshot(
            accountId: 'operating',
            name: 'Operating',
            balance: 10000,
            currency: 'rub',
            minimumBalance: 5000,
            allowNetting: true,
          ),
          AccountLiquiditySnapshot(
            accountId: 'reserve',
            name: 'Reserve',
            balance: 100000,
            currency: 'usd',
            minimumBalance: 20000,
            allowNetting: true,
          ),
        ],
      );
      final operating = result.accountLiquidityRisks
          .firstWhere((e) => e.accountId == 'operating');
      expect(operating.riskDay, isNotNull);
      expect(operating.canBeCoveredByNetting, isTrue);
    });
  });

  group('Backward-compatible domain memory', () {
    test('contract memory JSON roundtrip preserves probabilities', () {
      final memory = HorizonContractMemory(
        beatId: 'beat-1',
        leaseId: 'lease-1',
        renewalProbability: 0.72,
        renewalAmountRub: 9000,
        expectedRoyaltyRub: 3000,
        royaltyDueAt: now.add(const Duration(days: 40)),
        royaltyProbability: 0.61,
        updatedAt: now,
      );
      final restored = HorizonContractMemory.fromJson(memory.toJson());
      expect(restored.renewalProbability, 0.72);
      expect(restored.royaltyProbability, 0.61);
      expect(restored.renewalAmountRub, 9000);
    });

    test('account liquidity metadata keeps migration-free defaults', () {
      final restored = AccountLiquidityMeta.fromJson({'accountId': 'main'});
      expect(restored.currency, 'rub');
      expect(restored.allowNetting, isTrue);
      expect(restored.minimumBalanceRub, 0);
      expect(restored.fxHaircut, greaterThan(0));
    });
  });
}
