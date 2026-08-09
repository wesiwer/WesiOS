import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/transaction_model.dart';
import 'forecast_backtest.dart';
import 'horizon_calibration.dart';
import 'horizon_prediction_registry.dart';
import 'horizon_tuning_optimizer.dart';

class HorizonLearningSnapshot {
  final DateTime updatedAt;
  final HorizonCalibrationProfile profile;
  final MultiHorizonBacktest evaluation;
  final int realizedForecastSamples;
  final double tuningObjective;

  const HorizonLearningSnapshot({
    required this.updatedAt,
    required this.profile,
    required this.evaluation,
    this.realizedForecastSamples = 0,
    this.tuningObjective = double.infinity,
  });
}

/// Persisted, bounded self-learning for Wesi Horizon.
///
/// There are deliberately two evidence sources:
/// 1) rolling multi-origin reconstruction, which gives enough observations
///    even early in the product lifecycle;
/// 2) the production prediction registry, which evaluates the exact forecast
///    that was actually issued to the user against the later realized cash.
///
/// As live evidence accumulates it receives progressively more weight. This
/// prevents a new installation from overfitting two observations while also
/// preventing the model from hiding forever behind synthetic backtests.
class HorizonLearningService {
  HorizonLearningService._();

  static const String boxName = 'wesios_horizon_learning';
  static const String _profileKey = 'calibration_profile_v1';
  static const String _lastMonthKey = 'last_learning_month_v1';
  static const String _historyKey = 'learning_history_v1';

  static Future<Box<dynamic>> _open() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<dynamic>(boxName);
    return Hive.openBox<dynamic>(boxName);
  }

  static Future<HorizonCalibrationProfile> load() async {
    try {
      final box = await _open();
      final raw = box.get(_profileKey);
      if (raw is! String || raw.isEmpty) {
        return HorizonCalibrationProfile.identity;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return HorizonCalibrationProfile.identity;
      return HorizonCalibrationProfile.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return HorizonCalibrationProfile.identity;
    }
  }

  static String _monthId(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  static Future<bool> isDue([DateTime? now]) async {
    final date = now ?? DateTime.now();
    try {
      final box = await _open();
      return box.get(_lastMonthKey) != _monthId(date);
    } catch (_) {
      return false;
    }
  }

  static Future<HorizonLearningSnapshot?> updateIfDue({
    required List<TransactionModel> transactions,
    required double currentBalance,
    DateTime? now,
    bool force = false,
  }) async {
    final date = now ?? DateTime.now();
    final previous = await load();
    if (!force && !await isDue(date)) return null;

    // Do not mark a month as learned until there is enough historical
    // structure for at least the short-horizon backtest to mean something.
    if (transactions.length < 20) return null;

    try {
      final optimized = HorizonTuningOptimizer.select(
        transactions: transactions,
        currentBalance: currentBalance,
        now: date,
      );
      final backtest = optimized.backtest;
      final live = await HorizonPredictionRegistry.evaluateRealized(
        transactions: transactions,
        currentBalance: currentBalance,
        now: date,
      );
      final evaluation = HorizonPredictionRegistry.blendWithBacktest(
        backtest: backtest,
        live: live,
        tuning: optimized.tuning,
      );

      final useful = evaluation.metrics.any((m) => m.samples >= 10);
      if (!useful) return null;

      final learned = evaluation.toCalibrationProfile();
      final profile = HorizonCalibrationProfile(
        updatedAt: date,
        tuning: learned.tuning,
        buckets: learned.buckets,
        source: live.samples > 0
            ? 'monthly-learning:backtest+issued-forecast-actual'
            : 'monthly-learning:rolling-backtest',
      );

      final box = await _open();
      await box.put(_profileKey, jsonEncode(profile.toJson()));
      await box.put(_lastMonthKey, _monthId(date));

      final oldHistory = box.get(_historyKey);
      final history = oldHistory is List
          ? oldHistory.map((e) => '$e').toList()
          : <String>[];
      history.add(jsonEncode({
        'updatedAt': date.toIso8601String(),
        'previousSource': previous.source,
        'profile': profile.toJson(),
        'tuningObjective': optimized.objective,
        'realizedForecastSamples': live.samples,
        'metrics': [
          for (final metric in evaluation.metrics)
            {
              'horizon': metric.horizonDays,
              'samples': metric.samples,
              'mape': metric.mape,
              'coverage': metric.coverage,
              'bias': metric.bias,
              'quantileLoss': metric.quantileLoss,
              'brier': metric.brierScore,
            },
        ],
        'liveMetrics': [
          for (final metric in live.metrics)
            {
              'horizon': metric.horizonDays,
              'samples': metric.samples,
              'coverage': metric.coverage,
              'bias': metric.bias,
              'quantileLoss': metric.quantileLoss,
              'brier': metric.brierScore,
            },
        ],
      }));
      if (history.length > 24) history.removeRange(0, history.length - 24);
      await box.put(_historyKey, history);

      return HorizonLearningSnapshot(
        updatedAt: date,
        profile: profile,
        evaluation: evaluation,
        realizedForecastSamples: live.samples,
        tuningObjective: optimized.objective,
      );
    } catch (_) {
      // Learning must never be able to take live Treasury down.
      return null;
    }
  }

  static Future<List<String>> history() async {
    try {
      final raw = (await _open()).get(_historyKey);
      return raw is List ? raw.map((e) => '$e').toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> clearForTest() async {
    final box = await _open();
    await box.clear();
  }
}
