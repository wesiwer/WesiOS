import 'dart:math';

import '../models/transaction_model.dart';
import 'forecast_backtest.dart';
import 'horizon_calibration.dart';

class HorizonTuningEvaluation {
  final HorizonTuning tuning;
  final MultiHorizonBacktest backtest;
  final double objective;

  const HorizonTuningEvaluation({
    required this.tuning,
    required this.backtest,
    required this.objective,
  });
}

/// Quantile-first bounded tuning.
///
/// The objective explicitly rewards calibrated P10/P50/P90, not merely a
/// visually smooth P50. Near horizons carry more weight because Horizon's
/// product contract values 2–4 week usefulness above long-range cosmetics.
class HorizonTuningOptimizer {
  HorizonTuningOptimizer._();

  static const Map<int, double> horizonWeights = {
    14: 0.35,
    30: 0.30,
    90: 0.20,
    180: 0.15,
  };

  static double metricObjective(HorizonBacktestMetrics metric) {
    if (metric.samples == 0) return double.infinity;
    final maeScale = max(1.0, metric.mae.abs());
    final mape = metric.mape == null
        ? 1.0
        : (metric.mape! / 100).clamp(0.0, 3.0).toDouble();
    final quantile =
        (metric.quantileLoss / maeScale).clamp(0.0, 3.0).toDouble();
    final coveragePenalty =
        ((metric.coverage - horizonTargetCoverage).abs() / 0.20)
            .clamp(0.0, 3.0)
            .toDouble();
    final biasPenalty =
        (metric.bias.abs() / maeScale).clamp(0.0, 3.0).toDouble();
    final probabilityPenalty = metric.brierScore.clamp(0.0, 1.0).toDouble();

    // Quantile calibration is a first-class objective. MAPE remains useful,
    // but can no longer choose a tuning whose P10/P90 are badly calibrated.
    return mape * 0.25 +
        quantile * 0.35 +
        coveragePenalty * 0.20 +
        probabilityPenalty * 0.12 +
        biasPenalty * 0.08;
  }

  static double evaluationObjective(MultiHorizonBacktest evaluation) {
    var weighted = 0.0;
    var weightTotal = 0.0;
    for (final metric in evaluation.metrics) {
      if (metric.samples == 0) continue;
      final weight = horizonWeights[metric.horizonDays] ?? 0.05;
      final objective = metricObjective(metric);
      if (!objective.isFinite) continue;
      weighted += objective * weight;
      weightTotal += weight;
    }
    return weightTotal == 0 ? double.infinity : weighted / weightTotal;
  }

  static HorizonTuningEvaluation select({
    required List<TransactionModel> transactions,
    required double currentBalance,
    DateTime? now,
    int paths = 300,
    int maxOriginsPerHorizon = 3,
    List<int> seeds = const [11, 29, 47],
  }) {
    HorizonTuningEvaluation? best;
    for (final candidate in HorizonTuningCandidates.values) {
      final evaluation = ForecastBacktest.runMultiHorizon(
        transactions: transactions,
        currentBalance: currentBalance,
        now: now,
        horizons: const [14, 30, 90, 180],
        seeds: seeds,
        maxOriginsPerHorizon: maxOriginsPerHorizon,
        paths: paths,
        tuning: candidate,
      );
      final objective = evaluationObjective(evaluation);
      final candidateEvaluation = HorizonTuningEvaluation(
        tuning: candidate,
        backtest: evaluation,
        objective: objective,
      );
      if (best == null || objective < best.objective) {
        best = candidateEvaluation;
      }
    }
    return best ?? HorizonTuningEvaluation(
      tuning: HorizonTuning.defaults,
      backtest: ForecastBacktest.runMultiHorizon(
        transactions: transactions,
        currentBalance: currentBalance,
        now: now,
        horizons: const [14, 30, 90, 180],
        seeds: seeds,
        maxOriginsPerHorizon: maxOriginsPerHorizon,
        paths: paths,
      ),
      objective: double.infinity,
    );
  }
}
