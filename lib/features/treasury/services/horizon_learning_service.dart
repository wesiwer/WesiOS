import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../../organizations/models/organization_model.dart';
import '../../organizations/services/organization_context.dart';
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

class HorizonLearningService {
  HorizonLearningService._();

  static const String boxName = 'wesios_horizon_learning';
  static const String _legacyProfileKey = 'calibration_profile_v1';
  static const String _legacyLastMonthKey = 'last_learning_month_v1';
  static const String _legacyHistoryKey = 'learning_history_v1';

  static String _org(String? value) =>
      value ?? OrganizationContext.currentOrganizationId;
  static String _scope(String? value) =>
      value ?? OrganizationContext.scope.name;

  static String _scoped(
    String base, {
    String? organizationId,
    String? organizationScope,
  }) {
    final org = _org(organizationId);
    final scope = _scope(organizationScope);
    return org == OrganizationModel.rootId && scope == 'only'
        ? base
        : '$base.$org.$scope';
  }

  static Future<Box<dynamic>> _open() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<dynamic>(boxName);
    return Hive.openBox<dynamic>(boxName);
  }

  static Future<HorizonCalibrationProfile> load({
    String? organizationId,
    String? organizationScope,
  }) async {
    try {
      final box = await _open();
      final raw = box.get(_scoped(
        _legacyProfileKey,
        organizationId: organizationId,
        organizationScope: organizationScope,
      ));
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

  static Future<bool> isDue(
    DateTime? now, {
    String? organizationId,
    String? organizationScope,
  }) async {
    final date = now ?? DateTime.now();
    try {
      final box = await _open();
      return box.get(_scoped(
            _legacyLastMonthKey,
            organizationId: organizationId,
            organizationScope: organizationScope,
          )) !=
          _monthId(date);
    } catch (_) {
      return false;
    }
  }

  static Future<HorizonLearningSnapshot?> updateIfDue({
    required List<TransactionModel> transactions,
    required double currentBalance,
    DateTime? now,
    bool force = false,
    String? organizationId,
    String? organizationScope,
  }) async {
    final date = now ?? DateTime.now();
    final org = _org(organizationId);
    final scope = _scope(organizationScope);
    final previous = await load(
      organizationId: org,
      organizationScope: scope,
    );
    if (!force &&
        !await isDue(
          date,
          organizationId: org,
          organizationScope: scope,
        )) return null;
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
        organizationId: org,
        organizationScope: scope,
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
      final profileKey = _scoped(
        _legacyProfileKey,
        organizationId: org,
        organizationScope: scope,
      );
      final lastMonthKey = _scoped(
        _legacyLastMonthKey,
        organizationId: org,
        organizationScope: scope,
      );
      final historyKey = _scoped(
        _legacyHistoryKey,
        organizationId: org,
        organizationScope: scope,
      );
      await box.put(profileKey, jsonEncode(profile.toJson()));
      await box.put(lastMonthKey, _monthId(date));

      final oldHistory = box.get(historyKey);
      final history = oldHistory is List
          ? oldHistory.map((e) => '$e').toList()
          : <String>[];
      history.add(jsonEncode({
        'updatedAt': date.toIso8601String(),
        'organizationId': org,
        'organizationScope': scope,
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
      await box.put(historyKey, history);

      return HorizonLearningSnapshot(
        updatedAt: date,
        profile: profile,
        evaluation: evaluation,
        realizedForecastSamples: live.samples,
        tuningObjective: optimized.objective,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>> history({
    String? organizationId,
    String? organizationScope,
  }) async {
    try {
      final raw = (await _open()).get(_scoped(
        _legacyHistoryKey,
        organizationId: organizationId,
        organizationScope: organizationScope,
      ));
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
