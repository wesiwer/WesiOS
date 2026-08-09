import 'dart:convert';
import 'dart:math';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/transaction_model.dart';
import 'forecast_backtest.dart';
import 'forecast_engine.dart';
import 'forecast_engine_kind.dart';
import 'horizon_calibration.dart';
import 'multi_engine_forecast.dart';

class EngineBacktestMetric {
  final ForecastEngineKind engine;
  final int horizonDays;
  final int samples;
  final double mae;
  final double? mape;
  final double coverage;
  final double quantileLoss;
  final double brierScore;

  const EngineBacktestMetric({
    required this.engine,
    required this.horizonDays,
    required this.samples,
    required this.mae,
    required this.mape,
    required this.coverage,
    required this.quantileLoss,
    this.brierScore = 0,
  });

  double get score {
    if (samples == 0) return double.infinity;
    final error = mape == null ? 1.5 : min(3.0, mape! / 100);
    final calibrationPenalty =
        ((coverage - horizonTargetCoverage).abs() / 0.20).clamp(0.0, 3.0);
    final q = mae <= 0 ? 0.0 : min(3.0, quantileLoss / mae);
    return error * 0.30 +
        calibrationPenalty * 0.25 +
        q * 0.30 +
        brierScore.clamp(0.0, 1.0) * 0.15;
  }

  Map<String, dynamic> toJson() => {
        'engine': engine.name,
        'horizonDays': horizonDays,
        'samples': samples,
        'mae': mae,
        'mape': mape,
        'coverage': coverage,
        'quantileLoss': quantileLoss,
        'brierScore': brierScore,
      };

  factory EngineBacktestMetric.fromJson(Map<String, dynamic> json) =>
      EngineBacktestMetric(
        engine: ForecastEngineKind.values.firstWhere(
          (e) => e.name == json['engine'],
          orElse: () => ForecastEngineKind.wesiHorizon,
        ),
        horizonDays: (json['horizonDays'] as num?)?.toInt() ?? 30,
        samples: (json['samples'] as num?)?.toInt() ?? 0,
        mae: (json['mae'] as num?)?.toDouble() ?? 0,
        mape: (json['mape'] as num?)?.toDouble(),
        coverage: (json['coverage'] as num?)?.toDouble() ?? 0,
        quantileLoss: (json['quantileLoss'] as num?)?.toDouble() ?? 0,
        brierScore: (json['brierScore'] as num?)?.toDouble() ?? 0,
      );
}

class EngineChampionship {
  final DateTime evaluatedAt;
  final List<EngineBacktestMetric> metrics;

  const EngineChampionship({
    required this.evaluatedAt,
    this.metrics = const [],
  });

  ForecastEngineKind championFor(int horizon) {
    final nearest = _nearestHorizon(horizon);
    final candidates = metrics
        .where((m) => m.horizonDays == nearest && m.samples > 0)
        .toList()
      ..sort((a, b) {
        final byScore = a.score.compareTo(b.score);
        if (byScore != 0) return byScore;
        // Equal averaging must earn a real improvement, not win a tie.
        if (a.engine == ForecastEngineKind.combined &&
            b.engine != ForecastEngineKind.combined) return 1;
        if (b.engine == ForecastEngineKind.combined &&
            a.engine != ForecastEngineKind.combined) return -1;
        return a.engine.index.compareTo(b.engine.index);
      });
    return candidates.isEmpty
        ? ForecastEngineKind.wesiHorizon
        : candidates.first.engine;
  }

  int _nearestHorizon(int horizon) {
    if (metrics.isEmpty) return 30;
    final horizons = metrics.map((e) => e.horizonDays).toSet().toList();
    var best = horizons.first;
    var dist = (best - horizon).abs();
    for (final h in horizons.skip(1)) {
      final d = (h - horizon).abs();
      if (d < dist) {
        best = h;
        dist = d;
      }
    }
    return best;
  }

  Map<String, dynamic> toJson() => {
        'evaluatedAt': evaluatedAt.toIso8601String(),
        'metrics': metrics.map((e) => e.toJson()).toList(),
      };

  factory EngineChampionship.fromJson(Map<String, dynamic> json) =>
      EngineChampionship(
        evaluatedAt: DateTime.tryParse('${json['evaluatedAt'] ?? ''}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        metrics: [
          for (final raw in (json['metrics'] as List? ?? const []))
            if (raw is Map)
              EngineBacktestMetric.fromJson(Map<String, dynamic>.from(raw)),
        ],
      );
}

class SmartCombinedResult {
  final ForecastResult? result;
  final ForecastEngineKind selectedKind;
  final bool combinedWasRejected;

  const SmartCombinedResult({
    required this.result,
    required this.selectedKind,
    this.combinedWasRejected = false,
  });
}

class _EnginePoint {
  final double actual;
  final double p10;
  final double p50;
  final double p90;
  final double gapRisk;

  const _EnginePoint({
    required this.actual,
    required this.p10,
    required this.p50,
    required this.p90,
    required this.gapRisk,
  });
}

/// Historical, horizon-specific engine competition.
///
/// Every candidate is evaluated on the SAME origins and target days. Horizon
/// averages several seeds because it is stochastic; Prophet/SARIMAX are
/// deterministic. Combined is admitted only when at least two real engines
/// were available at that origin, so “Combined = Horizon” can never win by a
/// bookkeeping tie.
class HorizonEngineCompetitionService {
  HorizonEngineCompetitionService._();

  static const String boxName = 'wesios_horizon_engine_competition';
  static const String _key = 'championship_v2';
  static const List<int> horizons = [14, 30, 90, 180];
  static const List<int> _nativeSeeds = [11, 29, 47];
  static const int _originsPerHorizon = 2;

  static Future<Box<dynamic>> _open() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<dynamic>(boxName);
    return Hive.openBox<dynamic>(boxName);
  }

  static Future<EngineChampionship?> load() async {
    try {
      final raw = (await _open()).get(_key);
      if (raw is! String || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return EngineChampionship.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  static bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  static Future<EngineChampionship?> evaluateIfDue({
    required List<TransactionModel> transactions,
    required double currentBalance,
    DateTime? now,
    bool force = false,
  }) async {
    final today = now ?? DateTime.now();
    final stored = await load();
    if (!force && stored != null && _sameMonth(stored.evaluatedAt, today)) {
      return stored;
    }
    if (transactions.length < 30) return stored;

    final metrics = <EngineBacktestMetric>[];
    for (final horizon in horizons) {
      final points = <ForecastEngineKind, List<_EnginePoint>>{
        for (final engine in ForecastEngineKind.values) engine: <_EnginePoint>[],
      };
      final step = max(7, horizon ~/ 2);
      for (var origin = 0; origin < _originsPerHorizon; origin++) {
        final offset = horizon + origin * step;
        final asOf = DateTime(today.year, today.month, today.day)
            .subtract(Duration(days: offset));
        final past = transactions.where((t) => !t.date.isAfter(asOf)).toList();
        if (past.length < 14) continue;
        final balance =
            ForecastBacktest.balanceOn(asOf, transactions, currentBalance);

        final native = _nativeAverage(
          transactions: past,
          currentBalance: balance,
          horizon: horizon,
          asOf: asOf,
        );
        final prophet = await ExternalForecastBridge.run(
          engine: ForecastEngineKind.prophet,
          transactions: past,
          currentBalance: balance,
          days: horizon,
          asOf: asOf,
        );
        final sarimax = await ExternalForecastBridge.run(
          engine: ForecastEngineKind.sarimax,
          transactions: past,
          currentBalance: balance,
          days: horizon,
          asOf: asOf,
        );
        final availableSingles = <ForecastResult?>[native, prophet, sarimax]
            .whereType<ForecastResult>()
            .where((f) => !f.insufficientData && f.p50.length >= horizon)
            .toList();
        final combined = availableSingles.length >= 2
            ? combineForecastResults([native, prophet, sarimax])
            : null;

        final results = <ForecastEngineKind, ForecastResult?>{
          ForecastEngineKind.wesiHorizon: native,
          ForecastEngineKind.prophet: prophet,
          ForecastEngineKind.sarimax: sarimax,
          ForecastEngineKind.combined: combined,
        };
        for (final entry in results.entries) {
          final result = entry.value;
          if (result == null ||
              result.insufficientData ||
              result.p50.length < horizon) continue;
          for (var i = 0; i < horizon; i++) {
            final target = asOf.add(Duration(days: i + 1));
            points[entry.key]!.add(_EnginePoint(
              actual: ForecastBacktest.balanceOn(
                target,
                transactions,
                currentBalance,
              ),
              p10: result.p10[i],
              p50: result.p50[i],
              p90: result.p90[i],
              gapRisk: result.belowZeroProbability.length > i
                  ? result.belowZeroProbability[i]
                  : (result.p10[i] < 0 ? 0.10 : 0.0),
            ));
          }
        }
      }

      for (final engine in ForecastEngineKind.values) {
        final metric = _metric(engine, horizon, points[engine]!);
        if (metric != null) metrics.add(metric);
      }
    }

    if (metrics.isEmpty) return stored;
    final championship = EngineChampionship(
      evaluatedAt: today,
      metrics: metrics,
    );
    try {
      await (await _open()).put(_key, jsonEncode(championship.toJson()));
    } catch (_) {}
    return championship;
  }

  static ForecastResult? _nativeAverage({
    required List<TransactionModel> transactions,
    required double currentBalance,
    required int horizon,
    required DateTime asOf,
  }) {
    final results = <ForecastResult>[];
    for (final seed in _nativeSeeds) {
      final result = ForecastEngine.generate(
        transactions: transactions,
        currentBalance: currentBalance,
        days: horizon,
        asOf: asOf,
        paths: 450,
        seed: seed,
      );
      if (!result.insufficientData && result.p50.length >= horizon) {
        results.add(result);
      }
    }
    if (results.isEmpty) return null;
    if (results.length == 1) return results.first;

    double avg(List<double> Function(ForecastResult) read, int i) =>
        results.map((r) => read(r)[i]).fold<double>(0, (a, b) => a + b) /
        results.length;
    final p10 = List<double>.generate(horizon, (i) => avg((r) => r.p10, i));
    final p50 = List<double>.generate(horizon, (i) => avg((r) => r.p50, i));
    final p90 = List<double>.generate(horizon, (i) => avg((r) => r.p90, i));
    final risk = List<double>.generate(horizon, (i) {
      final values = results
          .where((r) => r.belowZeroProbability.length > i)
          .map((r) => r.belowZeroProbability[i])
          .toList();
      return values.isEmpty
          ? (p10[i] < 0 ? 0.10 : 0.0)
          : values.fold<double>(0, (a, b) => a + b) / values.length;
    });
    int? firstWhereRisk(double threshold) {
      for (var i = 0; i < risk.length; i++) {
        if (risk[i] > threshold) return i + 1;
      }
      return null;
    }
    int? runway;
    for (var i = 0; i < p50.length; i++) {
      if (p50[i] < 0) {
        runway = i + 1;
        break;
      }
    }
    return ForecastResult(
      p10: p10,
      p50: p50,
      p90: p90,
      trendPerDay:
          results.map((r) => r.trendPerDay).fold<double>(0, (a, b) => a + b) /
              results.length,
      dailyVolatility: results
              .map((r) => r.dailyVolatility)
              .fold<double>(0, (a, b) => a + b) /
          results.length,
      historyDaysSpan:
          results.map((r) => r.historyDaysSpan).reduce(max),
      simulatedPaths:
          results.map((r) => r.simulatedPaths).fold<int>(0, (a, b) => a + b),
      insufficientData: false,
      seasonalityApplied: results.any((r) => r.seasonalityApplied),
      belowZeroProbability: risk,
      runwayDays: runway,
      riskAlertDay: firstWhereRisk(0.05),
      risk10Day: firstWhereRisk(0.10),
      risk25Day: firstWhereRisk(0.25),
    );
  }

  static EngineBacktestMetric? _metric(
    ForecastEngineKind engine,
    int horizon,
    List<_EnginePoint> points,
  ) {
    if (points.isEmpty) return null;
    var abs = 0.0;
    var pct = 0.0;
    var pctN = 0;
    var covered = 0;
    var qLoss = 0.0;
    var brier = 0.0;
    final scale = points.map((p) => p.actual.abs()).fold<double>(0, (a, b) => a + b) /
        points.length;
    final pctFloor = max(1.0, scale * 0.01);
    for (final p in points) {
      final error = (p.actual - p.p50).abs();
      abs += error;
      if (p.actual.abs() >= pctFloor) {
        pct += error / p.actual.abs() * 100;
        pctN++;
      }
      if (p.actual >= p.p10 && p.actual <= p.p90) covered++;
      qLoss += pinballLoss(p.actual, p.p10, 0.10) +
          pinballLoss(p.actual, p.p50, 0.50) +
          pinballLoss(p.actual, p.p90, 0.90);
      final actualGap = p.actual < 0 ? 1.0 : 0.0;
      final diff = p.gapRisk - actualGap;
      brier += diff * diff;
    }
    return EngineBacktestMetric(
      engine: engine,
      horizonDays: horizon,
      samples: points.length,
      mae: abs / points.length,
      mape: pctN == 0 ? null : pct / pctN,
      coverage: covered / points.length,
      quantileLoss: qLoss / (points.length * 3),
      brierScore: brier / points.length,
    );
  }

  static Future<SmartCombinedResult> smartCombined({
    required int horizon,
    required Map<ForecastEngineKind, ForecastResult?> live,
  }) async {
    final championship = await load();
    final champion = championship?.championFor(horizon) ??
        ForecastEngineKind.wesiHorizon;

    ForecastResult? pick(ForecastEngineKind kind) {
      final result = live[kind];
      if (result == null || result.insufficientData || result.p50.isEmpty) {
        return null;
      }
      return result;
    }

    if (champion == ForecastEngineKind.combined) {
      final singles = [
        pick(ForecastEngineKind.wesiHorizon),
        pick(ForecastEngineKind.prophet),
        pick(ForecastEngineKind.sarimax),
      ].whereType<ForecastResult>().toList();
      final combined = singles.length >= 2
          ? combineForecastResults(singles)
          : null;
      if (combined != null) {
        return SmartCombinedResult(
          result: combined,
          selectedKind: ForecastEngineKind.combined,
        );
      }
    }

    final winner = pick(champion);
    if (winner != null) {
      return SmartCombinedResult(
        result: winner,
        selectedKind: champion,
        combinedWasRejected: champion != ForecastEngineKind.combined,
      );
    }

    for (final fallback in const [
      ForecastEngineKind.wesiHorizon,
      ForecastEngineKind.prophet,
      ForecastEngineKind.sarimax,
    ]) {
      final result = pick(fallback);
      if (result != null) {
        return SmartCombinedResult(
          result: result,
          selectedKind: fallback,
          combinedWasRejected: true,
        );
      }
    }
    return const SmartCombinedResult(
      result: null,
      selectedKind: ForecastEngineKind.wesiHorizon,
      combinedWasRejected: true,
    );
  }
}
