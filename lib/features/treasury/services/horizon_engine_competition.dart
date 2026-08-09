import 'dart:convert';
import 'dart:math';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/transaction_model.dart';
import 'forecast_backtest.dart';
import 'forecast_engine.dart';
import 'forecast_engine_kind.dart';
import 'multi_engine_forecast.dart';

class EngineBacktestMetric {
  final ForecastEngineKind engine;
  final int horizonDays;
  final int samples;
  final double mae;
  final double? mape;
  final double coverage;
  final double quantileLoss;

  const EngineBacktestMetric({
    required this.engine,
    required this.horizonDays,
    required this.samples,
    required this.mae,
    required this.mape,
    required this.coverage,
    required this.quantileLoss,
  });

  double get score {
    if (samples == 0) return double.infinity;
    final error = mape == null ? 1.5 : min(3.0, mape! / 100);
    final calibrationPenalty = (coverage - 0.8).abs() * 0.9;
    final q = mae <= 0 ? 0 : min(2.0, quantileLoss / mae);
    return error + calibrationPenalty + q * 0.25;
  }

  Map<String, dynamic> toJson() => {
        'engine': engine.name,
        'horizonDays': horizonDays,
        'samples': samples,
        'mae': mae,
        'mape': mape,
        'coverage': coverage,
        'quantileLoss': quantileLoss,
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
      ..sort((a, b) => a.score.compareTo(b.score));
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

/// Competition is historical and horizon-specific. “Combined” is allowed to
/// win only if its own backtest beats the best available single engine.
class HorizonEngineCompetitionService {
  HorizonEngineCompetitionService._();

  static const String boxName = 'wesios_horizon_engine_competition';
  static const String _key = 'championship_v1';
  static const List<int> horizons = [14, 30, 90];

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
    final native = ForecastBacktest.runMultiHorizon(
      transactions: transactions,
      currentBalance: currentBalance,
      now: today,
      horizons: horizons,
      seeds: ForecastBacktest.evaluationSeeds,
      maxOriginsPerHorizon: 3,
      paths: 400,
    );
    for (final metric in native.metrics) {
      metrics.add(EngineBacktestMetric(
        engine: ForecastEngineKind.wesiHorizon,
        horizonDays: metric.horizonDays,
        samples: metric.samples,
        mae: metric.mae,
        mape: metric.mape,
        coverage: metric.coverage,
        quantileLoss: metric.quantileLoss,
      ));
    }

    // Prophet/SARIMAX are optional and Windows-only. When unavailable there
    // is no synthetic zero score: they simply do not enter the competition.
    for (final engine in const [
      ForecastEngineKind.prophet,
      ForecastEngineKind.sarimax,
    ]) {
      for (final horizon in horizons) {
        final evaluated = await _evaluateExternal(
          engine: engine,
          horizon: horizon,
          transactions: transactions,
          currentBalance: currentBalance,
          today: today,
        );
        if (evaluated != null) metrics.add(evaluated);
      }
    }

    // Evaluate equal-combined on the same historical origins. It is recorded
    // as a candidate, never assumed to be superior merely because it exists.
    for (final horizon in horizons) {
      final combined = await _evaluateCombined(
        horizon: horizon,
        transactions: transactions,
        currentBalance: currentBalance,
        today: today,
      );
      if (combined != null) metrics.add(combined);
    }

    final championship = EngineChampionship(
      evaluatedAt: today,
      metrics: metrics,
    );
    try {
      await (await _open()).put(_key, jsonEncode(championship.toJson()));
    } catch (_) {}
    return championship;
  }

  static Future<EngineBacktestMetric?> _evaluateExternal({
    required ForecastEngineKind engine,
    required int horizon,
    required List<TransactionModel> transactions,
    required double currentBalance,
    required DateTime today,
  }) async {
    final points = <({double actual, double p10, double p50, double p90})>[];
    for (var origin = 1; origin <= 2; origin++) {
      final asOf = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: horizon * origin));
      final past = transactions.where((t) => !t.date.isAfter(asOf)).toList();
      if (past.length < 14) continue;
      final balance = ForecastBacktest.balanceOn(asOf, transactions, currentBalance);
      final result = await ExternalForecastBridge.run(
        engine: engine,
        transactions: past,
        currentBalance: balance,
        days: horizon,
        asOf: asOf,
      );
      if (result == null || result.p50.length < horizon) return null;
      for (var i = 0; i < horizon; i++) {
        final date = asOf.add(Duration(days: i + 1));
        points.add((
          actual: ForecastBacktest.balanceOn(date, transactions, currentBalance),
          p10: result.p10[i],
          p50: result.p50[i],
          p90: result.p90[i],
        ));
      }
    }
    return _metric(engine, horizon, points);
  }

  static Future<EngineBacktestMetric?> _evaluateCombined({
    required int horizon,
    required List<TransactionModel> transactions,
    required double currentBalance,
    required DateTime today,
  }) async {
    final points = <({double actual, double p10, double p50, double p90})>[];
    for (var origin = 1; origin <= 2; origin++) {
      final asOf = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: horizon * origin));
      final past = transactions.where((t) => !t.date.isAfter(asOf)).toList();
      if (past.length < 14) continue;
      final balance = ForecastBacktest.balanceOn(asOf, transactions, currentBalance);
      final native = ForecastEngine.generate(
        transactions: past,
        currentBalance: balance,
        days: horizon,
        asOf: asOf,
        paths: 500,
        seed: 29,
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
      final combined = combineForecastResults([native, prophet, sarimax]);
      if (combined == null || combined.p50.length < horizon) continue;
      for (var i = 0; i < horizon; i++) {
        final date = asOf.add(Duration(days: i + 1));
        points.add((
          actual: ForecastBacktest.balanceOn(date, transactions, currentBalance),
          p10: combined.p10[i],
          p50: combined.p50[i],
          p90: combined.p90[i],
        ));
      }
    }
    return _metric(ForecastEngineKind.combined, horizon, points);
  }

  static EngineBacktestMetric? _metric(
    ForecastEngineKind engine,
    int horizon,
    List<({double actual, double p10, double p50, double p90})> points,
  ) {
    if (points.isEmpty) return null;
    var abs = 0.0;
    var pct = 0.0;
    var pctN = 0;
    var covered = 0;
    var qLoss = 0.0;
    for (final p in points) {
      final error = (p.actual - p.p50).abs();
      abs += error;
      if (p.actual.abs() > 100) {
        pct += error / p.actual.abs() * 100;
        pctN++;
      }
      if (p.actual >= p.p10 && p.actual <= p.p90) covered++;
      qLoss += pinballLoss(p.actual, p.p10, 0.10) +
          pinballLoss(p.actual, p.p50, 0.50) +
          pinballLoss(p.actual, p.p90, 0.90);
    }
    return EngineBacktestMetric(
      engine: engine,
      horizonDays: horizon,
      samples: points.length,
      mae: abs / points.length,
      mape: pctN == 0 ? null : pct / pctN,
      coverage: covered / points.length,
      quantileLoss: qLoss / (points.length * 3),
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
      final combined = combineForecastResults([
        pick(ForecastEngineKind.wesiHorizon),
        pick(ForecastEngineKind.prophet),
        pick(ForecastEngineKind.sarimax),
      ]);
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
