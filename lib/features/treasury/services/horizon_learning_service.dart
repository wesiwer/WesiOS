import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/transaction_model.dart';
import 'forecast_backtest.dart';
import 'horizon_calibration.dart';

class HorizonLearningSnapshot {
  final DateTime updatedAt;
  final HorizonCalibrationProfile profile;
  final MultiHorizonBacktest evaluation;

  const HorizonLearningSnapshot({
    required this.updatedAt,
    required this.profile,
    required this.evaluation,
  });
}

/// Persisted, bounded self-learning for Wesi Horizon.
///
/// This is deliberately NOT an unconstrained optimizer. Once per calendar
/// month it chooses among a few interpretable tuning candidates, then learns
/// interval width, median bias and probability calibration from rolling
/// 14/30/90/180-day backtests evaluated with multiple random seeds.
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
      // Forecasting must fail soft if local learning state was damaged.
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

    // With short history, marking the month as "learned" would postpone the
    // first meaningful calibration. Leave identity in place and try later.
    if (transactions.length < 20) return null;

    try {
      final tuning = ForecastBacktest.selectTuning(
        transactions: transactions,
        currentBalance: currentBalance,
        now: date,
      );
      final evaluation = ForecastBacktest.runMultiHorizon(
        transactions: transactions,
        currentBalance: currentBalance,
        now: date,
        tuning: tuning,
      );
      final useful = evaluation.metrics.any((m) => m.samples >= 10);
      if (!useful) return null;

      final learned = evaluation.toCalibrationProfile();
      final profile = HorizonCalibrationProfile(
        updatedAt: date,
        tuning: learned.tuning,
        buckets: learned.buckets,
        source: 'monthly-learning-loop',
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
      }));
      if (history.length > 12) history.removeRange(0, history.length - 12);
      await box.put(_historyKey, history);

      return HorizonLearningSnapshot(
        updatedAt: date,
        profile: profile,
        evaluation: evaluation,
      );
    } catch (_) {
      // Never damage live forecasting because the learning pass failed.
      return null;
    }
  }

  static Future<void> clearForTest() async {
    final box = await _open();
    await box.clear();
  }
}
