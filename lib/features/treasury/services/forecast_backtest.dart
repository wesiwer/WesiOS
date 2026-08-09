import 'dart:math';

import '../models/transaction_model.dart';
import 'forecast_engine.dart';
import 'horizon_calibration.dart';

class BacktestPoint {
  final DateTime date;
  final double actual;
  final double p10;
  final double p50;
  final double p90;
  final double gapRisk;

  const BacktestPoint({
    required this.date,
    required this.actual,
    required this.p10,
    required this.p50,
    required this.p90,
    this.gapRisk = 0,
  });

  double get error => actual - p50;
  bool get inBand => actual >= p10 && actual <= p90;
  bool get actualGap => actual < 0;
}

class BacktestResult {
  final List<BacktestPoint> points;
  final DateTime asOf;
  final int horizonDays;
  final double mae;
  final double? mape;
  final double coverage;
  final double bias;
  final double quantileLoss;
  final double brierScore;
  final int seedCount;
  final bool insufficientData;

  const BacktestResult({
    required this.points,
    required this.asOf,
    required this.horizonDays,
    required this.mae,
    required this.mape,
    required this.coverage,
    required this.bias,
    this.quantileLoss = 0,
    this.brierScore = 0,
    this.seedCount = 1,
    this.insufficientData = false,
  });

  factory BacktestResult.empty(DateTime asOf, int horizonDays) => BacktestResult(
        points: const [],
        asOf: asOf,
        horizonDays: horizonDays,
        mae: 0,
        mape: null,
        coverage: 0,
        bias: 0,
        insufficientData: true,
      );

  BacktestGrade get grade {
    if (insufficientData) return BacktestGrade.unknown;
    if (coverage >= 0.7 && brierScore <= 0.22) return BacktestGrade.good;
    if (coverage >= 0.5) return BacktestGrade.fair;
    return BacktestGrade.poor;
  }
}

enum BacktestGrade { unknown, poor, fair, good }

class HorizonBacktestMetrics {
  final int horizonDays;
  final int samples;
  final double mae;
  final double? mape;
  final double coverage;
  final double bias;
  final double quantileLoss;
  final double brierScore;
  final List<({double predicted, bool actual})> riskObservations;

  const HorizonBacktestMetrics({
    required this.horizonDays,
    required this.samples,
    required this.mae,
    required this.mape,
    required this.coverage,
    required this.bias,
    required this.quantileLoss,
    required this.brierScore,
    this.riskObservations = const [],
  });

  double get normalizedScore {
    final pct = mape == null ? 1.0 : min(3.0, mape! / 100.0);
    final coveragePenalty = (coverage - horizonTargetCoverage).abs();
    return pct + coveragePenalty * 0.8 + brierScore * 0.6;
  }

  HorizonCalibrationBucket toCalibrationBucket() {
    final shrink = min(1.0, samples / 80.0);
    return HorizonCalibrationBucket(
      horizonDays: horizonDays,
      intervalScale: intervalScaleFromCoverage(coverage),
      biasCorrection: bias * shrink,
      coverage: coverage,
      mape: mape,
      quantileLoss: quantileLoss,
      riskBins: _riskBins(riskObservations),
      samples: samples,
    );
  }

  static List<RiskCalibrationBin> _riskBins(
    List<({double predicted, bool actual})> observations,
  ) {
    const edges = [0.0, 0.05, 0.10, 0.25, 0.50, 0.75, 1.000001];
    final bins = <RiskCalibrationBin>[];
    for (var i = 0; i < edges.length - 1; i++) {
      final lower = edges[i];
      final upper = edges[i + 1];
      final own = observations
          .where((o) => o.predicted >= lower && o.predicted < upper)
          .toList();
      if (own.isEmpty) continue;
      final events = own.where((o) => o.actual).length;
      bins.add(RiskCalibrationBin(
        lower: lower,
        upper: upper >= 1 ? 1 : upper,
        observedRate: events / own.length,
        samples: own.length,
      ));
    }
    return bins;
  }
}

class MultiHorizonBacktest {
  final List<HorizonBacktestMetrics> metrics;
  final HorizonTuning tuning;
  final int seedCount;
  final DateTime evaluatedAt;

  const MultiHorizonBacktest({
    required this.metrics,
    required this.tuning,
    required this.seedCount,
    required this.evaluatedAt,
  });

  HorizonBacktestMetrics? forHorizon(int days) {
    if (metrics.isEmpty) return null;
    var best = metrics.first;
    var distance = (best.horizonDays - days).abs();
    for (final metric in metrics.skip(1)) {
      final next = (metric.horizonDays - days).abs();
      if (next < distance) {
        best = metric;
        distance = next;
      }
    }
    return best;
  }

  HorizonCalibrationProfile toCalibrationProfile() => HorizonCalibrationProfile(
        updatedAt: evaluatedAt,
        tuning: tuning,
        buckets: metrics
            .where((e) => e.samples > 0)
            .map((e) => e.toCalibrationBucket())
            .toList(),
        source: 'rolling-multi-horizon-backtest',
      );
}

class ForecastBacktest {
  static const int minHistoryBeforeAsOf = 21;
  static const List<int> topTierHorizons = [14, 30, 90, 180];
  static const List<int> evaluationSeeds = [11, 29, 47, 83, 131];

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static double balanceOn(
    DateTime day,
    List<TransactionModel> transactions,
    double currentBalance,
  ) {
    final cutoff = _dateOnly(day);
    var future = 0.0;
    for (final tx in transactions) {
      if (_dateOnly(tx.date).isAfter(cutoff)) {
        future += tx.type == TransactionType.income ? tx.amount : -tx.amount;
      }
    }
    return currentBalance - future;
  }

  static BacktestResult run({
    required List<TransactionModel> transactions,
    required double currentBalance,
    int horizonDays = 30,
    DateTime? now,
    double annualDiscountRate = 0,
    int seed = 42,
    int paths = 1200,
    HorizonCalibrationProfile calibration = HorizonCalibrationProfile.identity,
    HorizonTuning? tuning,
  }) {
    final today = _dateOnly(now ?? DateTime.now());
    final asOf = today.subtract(Duration(days: horizonDays));
    return _runAt(
      transactions: transactions,
      currentBalance: currentBalance,
      asOf: asOf,
      horizonDays: horizonDays,
      annualDiscountRate: annualDiscountRate,
      seeds: [seed],
      paths: paths,
      calibration: calibration,
      tuning: tuning,
    );
  }

  static BacktestResult _runAt({
    required List<TransactionModel> transactions,
    required double currentBalance,
    required DateTime asOf,
    required int horizonDays,
    required List<int> seeds,
    required int paths,
    double annualDiscountRate = 0,
    HorizonCalibrationProfile calibration = HorizonCalibrationProfile.identity,
    HorizonTuning? tuning,
  }) {
    if (horizonDays <= 0 || transactions.length < 3) {
      return BacktestResult.empty(asOf, horizonDays);
    }
    final past = transactions.where((t) => !_dateOnly(t.date).isAfter(asOf)).toList();
    if (past.length < 3) return BacktestResult.empty(asOf, horizonDays);
    var earliest = asOf;
    for (final tx in past) {
      final day = _dateOnly(tx.date);
      if (day.isBefore(earliest)) earliest = day;
    }
    if (asOf.difference(earliest).inDays < minHistoryBeforeAsOf) {
      return BacktestResult.empty(asOf, horizonDays);
    }

    final balanceAtAsOf = balanceOn(asOf, transactions, currentBalance);
    final forecasts = <ForecastResult>[];
    for (final seed in seeds) {
      final forecast = ForecastEngine.generate(
        transactions: past,
        currentBalance: balanceAtAsOf,
        days: horizonDays,
        annualDiscountRate: annualDiscountRate,
        asOf: asOf,
        seed: seed,
        paths: paths,
        calibration: calibration,
        tuning: tuning,
      );
      if (!forecast.insufficientData && forecast.p50.isNotEmpty) {
        forecasts.add(forecast);
      }
    }
    if (forecasts.isEmpty) return BacktestResult.empty(asOf, horizonDays);

    final n = min(horizonDays, forecasts.map((f) => f.p50.length).reduce(min));
    final points = <BacktestPoint>[];
    for (var i = 0; i < n; i++) {
      double avg(List<double> Function(ForecastResult) read) =>
          forecasts.map((f) => read(f)[i]).reduce((a, b) => a + b) /
          forecasts.length;
      points.add(BacktestPoint(
        date: asOf.add(Duration(days: i + 1)),
        actual: balanceOn(asOf.add(Duration(days: i + 1)), transactions, currentBalance),
        p10: avg((f) => f.p10),
        p50: avg((f) => f.p50),
        p90: avg((f) => f.p90),
        gapRisk: avg((f) => f.belowZeroProbability),
      ));
    }
    return _summarize(points, asOf, horizonDays, forecasts.length);
  }

  static BacktestResult _summarize(
    List<BacktestPoint> points,
    DateTime asOf,
    int horizonDays,
    int seedCount,
  ) {
    if (points.isEmpty) return BacktestResult.empty(asOf, horizonDays);
    var absSum = 0.0;
    var signedSum = 0.0;
    var inBand = 0;
    var pctSum = 0.0;
    var pctCount = 0;
    var qLoss = 0.0;
    var brier = 0.0;
    final scale = points.map((p) => p.actual.abs()).reduce((a, b) => a + b) /
        points.length;
    final pctFloor = max(1.0, scale * 0.01);
    for (final point in points) {
      absSum += point.error.abs();
      signedSum += point.error;
      if (point.inBand) inBand++;
      if (point.actual.abs() >= pctFloor) {
        pctSum += point.error.abs() / point.actual.abs();
        pctCount++;
      }
      qLoss += pinballLoss(point.actual, point.p10, 0.10);
      qLoss += pinballLoss(point.actual, point.p50, 0.50);
      qLoss += pinballLoss(point.actual, point.p90, 0.90);
      final actualGap = point.actualGap ? 1.0 : 0.0;
      final diff = point.gapRisk - actualGap;
      brier += diff * diff;
    }
    return BacktestResult(
      points: points,
      asOf: asOf,
      horizonDays: horizonDays,
      mae: absSum / points.length,
      mape: pctCount == 0 ? null : pctSum / pctCount * 100,
      coverage: inBand / points.length,
      bias: signedSum / points.length,
      quantileLoss: qLoss / (points.length * 3),
      brierScore: brier / points.length,
      seedCount: seedCount,
    );
  }

  /// Rolling multi-origin, multi-seed backtest. A single lucky cut-off can no
  /// longer declare the model "accurate".
  static MultiHorizonBacktest runMultiHorizon({
    required List<TransactionModel> transactions,
    required double currentBalance,
    DateTime? now,
    List<int> horizons = topTierHorizons,
    List<int> seeds = evaluationSeeds,
    int maxOriginsPerHorizon = 4,
    int paths = 450,
    HorizonTuning tuning = HorizonTuning.defaults,
  }) {
    final today = _dateOnly(now ?? DateTime.now());
    final metrics = <HorizonBacktestMetrics>[];
    for (final horizon in horizons) {
      final allPoints = <BacktestPoint>[];
      var origins = 0;
      // Recent origins matter more, but require a full future horizon. Step by
      // roughly half a horizon to avoid evaluating the same days repeatedly.
      final step = max(7, horizon ~/ 2);
      for (var offset = horizon; origins < maxOriginsPerHorizon; offset += step) {
        final asOf = today.subtract(Duration(days: offset));
        final result = _runAt(
          transactions: transactions,
          currentBalance: currentBalance,
          asOf: asOf,
          horizonDays: horizon,
          seeds: seeds,
          paths: paths,
          tuning: tuning,
        );
        if (result.insufficientData) {
          if (offset > 365 * 4) break;
          continue;
        }
        allPoints.addAll(result.points);
        origins++;
      }
      metrics.add(_metricsFromPoints(horizon, allPoints));
    }
    return MultiHorizonBacktest(
      metrics: metrics,
      tuning: tuning,
      seedCount: seeds.length,
      evaluatedAt: today,
    );
  }

  static HorizonBacktestMetrics _metricsFromPoints(
    int horizon,
    List<BacktestPoint> points,
  ) {
    if (points.isEmpty) {
      return HorizonBacktestMetrics(
        horizonDays: horizon,
        samples: 0,
        mae: 0,
        mape: null,
        coverage: 0,
        bias: 0,
        quantileLoss: 0,
        brierScore: 0,
      );
    }
    final summary = _summarize(points, DateTime(2000), horizon, 1);
    return HorizonBacktestMetrics(
      horizonDays: horizon,
      samples: points.length,
      mae: summary.mae,
      mape: summary.mape,
      coverage: summary.coverage,
      bias: summary.bias,
      quantileLoss: summary.quantileLoss,
      brierScore: summary.brierScore,
      riskObservations: [
        for (final point in points)
          (predicted: point.gapRisk, actual: point.actualGap),
      ],
    );
  }

  /// Safe hyperparameter selection. Candidates are intentionally few and
  /// interpretable; 14/30-day quality has more weight than long-horizon fit.
  static HorizonTuning selectTuning({
    required List<TransactionModel> transactions,
    required double currentBalance,
    DateTime? now,
  }) {
    HorizonTuning best = HorizonTuning.defaults;
    var bestScore = double.infinity;
    for (final candidate in HorizonTuningCandidates.values) {
      final evaluation = runMultiHorizon(
        transactions: transactions,
        currentBalance: currentBalance,
        now: now,
        horizons: const [14, 30, 90],
        seeds: const [29],
        maxOriginsPerHorizon: 3,
        paths: 250,
        tuning: candidate,
      );
      var score = 0.0;
      var weightTotal = 0.0;
      for (final metric in evaluation.metrics) {
        if (metric.samples == 0) continue;
        final weight = switch (metric.horizonDays) {
          14 => 0.45,
          30 => 0.35,
          _ => 0.20,
        };
        score += metric.normalizedScore * weight;
        weightTotal += weight;
      }
      if (weightTotal == 0) continue;
      score /= weightTotal;
      if (score < bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return best;
  }
}
