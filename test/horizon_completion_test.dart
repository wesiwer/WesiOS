import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/forecast_backtest.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';
import 'package:wesios/features/treasury/services/horizon_behavior_monitor.dart';
import 'package:wesios/features/treasury/services/horizon_calibration.dart';
import 'package:wesios/features/treasury/services/horizon_contract_memory.dart';
import 'package:wesios/features/treasury/services/horizon_engine_competition.dart';
import 'package:wesios/features/treasury/services/horizon_explainability.dart';
import 'package:wesios/features/treasury/services/horizon_prediction_registry.dart';
import 'package:wesios/features/treasury/services/horizon_tuning_optimizer.dart';

TransactionModel _tx({
  required String id,
  required DateTime date,
  required double amount,
  required TransactionType type,
  String category = 'services',
  String? accountId,
}) =>
    TransactionModel(
      id: id,
      title: id,
      amount: amount,
      type: type,
      date: date,
      category: category,
      accountId: accountId,
    );

void main() {
  final now = DateTime(2026, 8, 9);

  group('Calibration completion', () {
    test('100% coverage with huge MAPE narrows more than coverage alone', () {
      final ordinary = intervalScaleFromCoverage(1.0);
      final inaccurate = intervalScaleFromCoverage(1.0, mape: 100);
      expect(inaccurate, lessThan(ordinary));
      expect(inaccurate, greaterThanOrEqualTo(0.55));
    });

    test('risk calibration remains monotone even when empirical bins are noisy',
        () {
      const bucket = HorizonCalibrationBucket(
        horizonDays: 30,
        riskBins: [
          RiskCalibrationBin(
              lower: 0, upper: .2, observedRate: .55, samples: 30),
          RiskCalibrationBin(
              lower: .2, upper: .5, observedRate: .10, samples: 30),
          RiskCalibrationBin(
              lower: .5, upper: 1, observedRate: .75, samples: 30),
        ],
      );
      final p10 = bucket.calibrateRisk(.10);
      final p30 = bucket.calibrateRisk(.30);
      final p70 = bucket.calibrateRisk(.70);
      expect(p30, greaterThanOrEqualTo(p10));
      expect(p70, greaterThanOrEqualTo(p30));
    });

    test('quantile loss is a first-class tuning objective', () {
      const good = HorizonBacktestMetrics(
        horizonDays: 30,
        samples: 100,
        mae: 100,
        mape: 10,
        coverage: .8,
        bias: 0,
        quantileLoss: 30,
        brierScore: .10,
      );
      const badQuantiles = HorizonBacktestMetrics(
        horizonDays: 30,
        samples: 100,
        mae: 100,
        mape: 10,
        coverage: .8,
        bias: 0,
        quantileLoss: 250,
        brierScore: .10,
      );
      expect(
        HorizonTuningOptimizer.metricObjective(badQuantiles),
        greaterThan(HorizonTuningOptimizer.metricObjective(good)),
      );
    });
  });

  group('Behavior and explainability completion', () {
    test('persistent incoming downshift is detected as a structural warning',
        () {
      final history = <TransactionModel>[];
      for (var ago = 70; ago >= 1; ago--) {
        final recent = ago <= 14;
        history.add(_tx(
          id: 'income-$ago',
          date: now.subtract(Duration(days: ago)),
          amount: recent ? 100 : 1000 + (ago % 3) * 25,
          type: TransactionType.income,
        ));
      }
      final warnings = HorizonBehaviorMonitor.analyze(
        transactions: history,
        now: now,
      );
      expect(
        warnings.any((p) => p.code == 'structural-income-downshift'),
        isTrue,
      );
    });

    test('material P50 kink receives additive event attribution', () {
      final future = _tx(
        id: 'rent',
        date: now.add(const Duration(days: 3)),
        amount: 50000,
        type: TransactionType.expense,
      );
      const forecast = ForecastResult(
        p10: [99000, 97000, 42000],
        p50: [100000, 99000, 49000],
        p90: [101000, 101000, 56000],
        trendPerDay: 0,
        dailyVolatility: 500,
        historyDaysSpan: 120,
        simulatedPaths: 1000,
        insufficientData: false,
        seasonalityApplied: true,
        committedNetByDay: [0, 0, -50000],
        uncertainMedianByDay: [0, -1000, 0],
        streamContribution: {'services': 800, 'operations': -400},
      );
      final explanations = HorizonExplainabilityService.build(
        forecast: forecast,
        transactions: [future],
        now: now,
      );
      expect(
        explanations.any(
            (e) => e.day == 3 && e.source == 'treasury-scheduled'),
        isTrue,
      );
    });
  });

  group('Liquidity completion', () {
    List<TransactionModel> historyWithFuturePayment() {
      final result = <TransactionModel>[];
      for (var ago = 40; ago >= 1; ago--) {
        result.add(_tx(
          id: 'h-$ago',
          date: now.subtract(Duration(days: ago)),
          amount: ago.isEven ? 300 : 250,
          type: ago.isEven ? TransactionType.income : TransactionType.expense,
          accountId: 'operating',
        ));
      }
      result.add(_tx(
        id: 'large-payment',
        date: now.add(const Duration(days: 2)),
        amount: 12000,
        type: TransactionType.expense,
        accountId: 'operating',
      ));
      return result;
    }

    test('late reserve cannot rescue an account before its local shortfall', () {
      final result = ForecastEngine.generate(
        transactions: historyWithFuturePayment(),
        currentBalance: 60000,
        days: 20,
        paths: 150,
        seed: 42,
        asOf: now,
        accounts: const [
          AccountLiquiditySnapshot(
            accountId: 'operating',
            name: 'Operating',
            balance: 10000,
            minimumBalance: 5000,
            currency: 'rub',
          ),
          AccountLiquiditySnapshot(
            accountId: 'reserve',
            name: 'Reserve',
            balance: 50000,
            minimumBalance: 5000,
            currency: 'rub',
            transferDelayDays: 5,
          ),
        ],
      );
      final risk = result.accountLiquidityRisks
          .firstWhere((e) => e.accountId == 'operating');
      expect(risk.riskDay, isNotNull);
      expect(risk.canBeCoveredByNetting, isFalse);
    });

    test('timely reserve is counted as nettable liquidity', () {
      final result = ForecastEngine.generate(
        transactions: historyWithFuturePayment(),
        currentBalance: 60000,
        days: 20,
        paths: 150,
        seed: 42,
        asOf: now,
        accounts: const [
          AccountLiquiditySnapshot(
            accountId: 'operating',
            name: 'Operating',
            balance: 10000,
            minimumBalance: 5000,
            currency: 'rub',
          ),
          AccountLiquiditySnapshot(
            accountId: 'reserve',
            name: 'Reserve',
            balance: 50000,
            minimumBalance: 5000,
            currency: 'rub',
            transferDelayDays: 0,
          ),
        ],
      );
      final risk = result.accountLiquidityRisks
          .firstWhere((e) => e.accountId == 'operating');
      expect(risk.riskDay, isNotNull);
      expect(risk.canBeCoveredByNetting, isTrue);
      expect(risk.nettableLiquidity, greaterThan(0));
    });
  });

  group('Learning and competition completion', () {
    test('engine championship explicitly includes the 180-day horizon', () {
      expect(HorizonEngineCompetitionService.horizons, [14, 30, 90, 180]);
    });

    test('issued prediction record roundtrips exact probabilistic statement',
        () {
      final record = HorizonPredictionRecord(
        id: '2026-08-09',
        issuedAt: now,
        startingBalance: 100000,
        calibrationSource: 'live',
        predictions: [
          HorizonIssuedPrediction(
            horizonDays: 30,
            targetDate: now.add(const Duration(days: 30)),
            p10: 80000,
            p50: 100000,
            p90: 125000,
            gapRisk: .2,
          ),
        ],
      );
      final decoded = HorizonPredictionRecord.fromJson(record.toJson());
      expect(decoded.predictions.single.horizonDays, 30);
      expect(decoded.predictions.single.gapRisk, .2);
      expect(decoded.predictions.single.p50, 100000);
    });

    test('contract outcome roundtrip preserves renewal evidence', () {
      final outcome = HorizonContractOutcome(
        id: 'lease-1',
        beatId: 'beat-1',
        artistKey: 'artist',
        closedAt: now,
        amountRub: 10000,
        renewed: true,
      );
      final decoded = HorizonContractOutcome.fromJson(outcome.toJson());
      expect(decoded.renewed, isTrue);
      expect(decoded.beatId, 'beat-1');
      expect(decoded.amountRub, 10000);
    });

    test('production wiring contains issued-forecast, contract and attribution loops',
        () {
      final treasury =
          File('lib/features/treasury/services/treasury_service.dart')
              .readAsStringSync();
      final audio = File('lib/features/audio/services/audio_vault_service.dart')
          .readAsStringSync();
      final learning =
          File('lib/features/treasury/services/horizon_learning_service.dart')
              .readAsStringSync();
      expect(treasury, contains('HorizonPredictionRegistry.recordBaseForecast'));
      expect(treasury, contains('HorizonExplainabilityService.build'));
      expect(treasury, contains('HorizonBehaviorMonitor.analyze'));
      expect(audio, contains('recordClosedLease'));
      expect(audio, contains('markRenewalIfApplicable'));
      expect(learning, contains('evaluateRealized'));
      expect(learning, contains('blendWithBacktest'));
    });
  });
}
