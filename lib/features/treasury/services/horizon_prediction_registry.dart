import 'calendar_days.dart';
import 'dart:convert';
import 'dart:math';

import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/sync/sync_account_scope.dart';
import '../../organizations/models/organization_model.dart';
import '../../organizations/services/organization_context.dart';
import '../models/transaction_model.dart';
import 'forecast_backtest.dart';
import 'forecast_engine.dart';
import 'horizon_calibration.dart';

class HorizonIssuedPrediction {
  final int horizonDays;
  final DateTime targetDate;
  final double p10;
  final double p50;
  final double p90;
  final double gapRisk;

  const HorizonIssuedPrediction({
    required this.horizonDays,
    required this.targetDate,
    required this.p10,
    required this.p50,
    required this.p90,
    required this.gapRisk,
  });

  Map<String, dynamic> toJson() => {
        'horizonDays': horizonDays,
        'targetDate': targetDate.toIso8601String(),
        'p10': p10,
        'p50': p50,
        'p90': p90,
        'gapRisk': gapRisk,
      };

  factory HorizonIssuedPrediction.fromJson(Map<String, dynamic> json) =>
      HorizonIssuedPrediction(
        horizonDays: (json['horizonDays'] as num?)?.toInt() ?? 30,
        targetDate: DateTime.tryParse('${json['targetDate'] ?? ''}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        p10: (json['p10'] as num?)?.toDouble() ?? 0,
        p50: (json['p50'] as num?)?.toDouble() ?? 0,
        p90: (json['p90'] as num?)?.toDouble() ?? 0,
        gapRisk: ((json['gapRisk'] as num?)?.toDouble() ?? 0)
            .clamp(0.0, 1.0)
            .toDouble(),
      );
}

class HorizonPredictionRecord {
  final String id;
  final DateTime issuedAt;
  final double startingBalance;
  final String calibrationSource;
  final List<HorizonIssuedPrediction> predictions;
  final String organizationId;
  final String organizationScope;

  const HorizonPredictionRecord({
    required this.id,
    required this.issuedAt,
    required this.startingBalance,
    required this.calibrationSource,
    required this.predictions,
    this.organizationId = OrganizationModel.rootId,
    this.organizationScope = 'only',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'issuedAt': issuedAt.toIso8601String(),
        'startingBalance': startingBalance,
        'calibrationSource': calibrationSource,
        'predictions': predictions.map((e) => e.toJson()).toList(),
        'organizationId': organizationId,
        'organizationScope': organizationScope,
      };

  factory HorizonPredictionRecord.fromJson(Map<String, dynamic> json) =>
      HorizonPredictionRecord(
        id: '${json['id'] ?? ''}',
        issuedAt: DateTime.tryParse('${json['issuedAt'] ?? ''}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        startingBalance: (json['startingBalance'] as num?)?.toDouble() ?? 0,
        calibrationSource: '${json['calibrationSource'] ?? 'unknown'}',
        predictions: [
          for (final raw in (json['predictions'] as List? ?? const []))
            if (raw is Map)
              HorizonIssuedPrediction.fromJson(Map<String, dynamic>.from(raw)),
        ],
        organizationId:
            '${json['organizationId'] ?? OrganizationModel.rootId}',
        organizationScope: '${json['organizationScope'] ?? 'only'}',
      );
}

class HorizonRealizedPrediction {
  final String recordId;
  final DateTime issuedAt;
  final HorizonIssuedPrediction prediction;
  final double actualBalance;

  const HorizonRealizedPrediction({
    required this.recordId,
    required this.issuedAt,
    required this.prediction,
    required this.actualBalance,
  });

  double get error => actualBalance - prediction.p50;
  bool get covered =>
      actualBalance >= prediction.p10 && actualBalance <= prediction.p90;
  bool get actualGap => actualBalance < 0;
  double get quantileLoss =>
      (pinballLoss(actualBalance, prediction.p10, 0.10) +
          pinballLoss(actualBalance, prediction.p50, 0.50) +
          pinballLoss(actualBalance, prediction.p90, 0.90)) /
      3;
  double get brier {
    final observed = actualGap ? 1.0 : 0.0;
    final diff = prediction.gapRisk - observed;
    return diff * diff;
  }
}

class HorizonLiveCalibrationReport {
  final DateTime evaluatedAt;
  final List<HorizonRealizedPrediction> observations;
  final List<HorizonBacktestMetrics> metrics;

  const HorizonLiveCalibrationReport({
    required this.evaluatedAt,
    required this.observations,
    required this.metrics,
  });

  int get samples => observations.length;
}

class HorizonPredictionRegistry {
  HorizonPredictionRegistry._();

  static const String baseBoxName = 'wesios_horizon_prediction_registry';
  static String get boxName => SyncAccountScope.boxName(baseBoxName);
  static const String _recordsKey = 'issued_predictions_v1';
  static const List<int> trackedHorizons = [14, 30, 90, 180];
  static const int _maxRecords = 730;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static String _dayId(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<Box<dynamic>> _open() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<dynamic>(boxName);
    return Hive.openBox<dynamic>(boxName);
  }

  static Future<List<HorizonPredictionRecord>> records() async {
    try {
      final raw = (await _open()).get(_recordsKey);
      if (raw is! String || raw.isEmpty) return <HorizonPredictionRecord>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <HorizonPredictionRecord>[];
      return [
        for (final value in decoded)
          if (value is Map)
            HorizonPredictionRecord.fromJson(Map<String, dynamic>.from(value)),
      ]..sort((a, b) => a.issuedAt.compareTo(b.issuedAt));
    } catch (_) {
      return <HorizonPredictionRecord>[];
    }
  }

  static Future<void> recordBaseForecast({
    required ForecastResult forecast,
    required double currentBalance,
    required HorizonCalibrationProfile calibration,
    DateTime? now,
    String? organizationId,
    String organizationScope = 'only',
  }) async {
    if (forecast.insufficientData || forecast.p50.isEmpty) return;
    final issued = _day(now ?? DateTime.now());
    final orgId = organizationId ?? OrganizationModel.rootId;
    final existing = await records();
    final legacyIdentity =
        orgId == OrganizationModel.rootId && organizationScope == 'only';
    final id = legacyIdentity
        ? _dayId(issued)
        : '$orgId:$organizationScope:${_dayId(issued)}';
    if (existing.any((record) =>
        record.id == id ||
        (record.organizationId == orgId &&
            record.organizationScope == organizationScope &&
            _day(record.issuedAt) == issued))) {
      return;
    }

    final points = <HorizonIssuedPrediction>[];
    for (final horizon in trackedHorizons) {
      if (forecast.p50.length < horizon ||
          forecast.p10.length < horizon ||
          forecast.p90.length < horizon) {
        continue;
      }
      final risk = forecast.belowZeroProbability.length >= horizon
          ? forecast.belowZeroProbability[horizon - 1]
          : (forecast.p10[horizon - 1] < 0 ? 0.10 : 0.0);
      points.add(HorizonIssuedPrediction(
        horizonDays: horizon,
        targetDate: addDays(issued, horizon),
        p10: forecast.p10[horizon - 1],
        p50: forecast.p50[horizon - 1],
        p90: forecast.p90[horizon - 1],
        gapRisk: risk,
      ));
    }
    if (points.isEmpty) return;

    existing.add(HorizonPredictionRecord(
      id: id,
      issuedAt: issued,
      startingBalance: currentBalance,
      calibrationSource: calibration.source,
      predictions: points,
      organizationId: orgId,
      organizationScope: organizationScope,
    ));
    if (existing.length > _maxRecords) {
      existing.removeRange(0, existing.length - _maxRecords);
    }
    try {
      await (await _open()).put(
        _recordsKey,
        jsonEncode(existing.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // Forecasting remains available even if local audit storage is damaged.
    }
  }

  static Future<HorizonLiveCalibrationReport> evaluateRealized({
    required List<TransactionModel> transactions,
    required double currentBalance,
    DateTime? now,
    String? organizationId,
    String? organizationScope,
  }) async {
    final today = _day(now ?? DateTime.now());
    final orgId = organizationId ?? OrganizationContext.currentOrganizationId;
    final scope = organizationScope ?? OrganizationContext.scope.name;
    final issued = (await records())
        .where((r) => r.organizationId == orgId && r.organizationScope == scope)
        .toList();
    final observations = <HorizonRealizedPrediction>[];
    for (final record in issued) {
      for (final prediction in record.predictions) {
        if (_day(prediction.targetDate).isAfter(today)) continue;
        final actual = ForecastBacktest.balanceOn(
          prediction.targetDate,
          transactions,
          currentBalance,
          currentDate: today,
        );
        observations.add(HorizonRealizedPrediction(
          recordId: record.id,
          issuedAt: record.issuedAt,
          prediction: prediction,
          actualBalance: actual,
        ));
      }
    }

    final metrics = <HorizonBacktestMetrics>[];
    for (final horizon in trackedHorizons) {
      final own = observations
          .where((o) => o.prediction.horizonDays == horizon)
          .toList();
      if (own.isEmpty) {
        metrics.add(HorizonBacktestMetrics(
          horizonDays: horizon,
          samples: 0,
          mae: 0,
          mape: null,
          coverage: 0,
          bias: 0,
          quantileLoss: 0,
          brierScore: 0,
        ));
        continue;
      }

      var absolute = 0.0;
      var signed = 0.0;
      var covered = 0;
      var percentage = 0.0;
      var percentageSamples = 0;
      var qLoss = 0.0;
      var brier = 0.0;
      final risk = <({double predicted, bool actual})>[];
      final scale = own
              .map((o) => o.actualBalance.abs())
              .fold<double>(0, (a, b) => a + b) /
          own.length;
      final denominatorFloor = max(1.0, scale * 0.01);
      for (final observation in own) {
        absolute += observation.error.abs();
        signed += observation.error;
        if (observation.covered) covered++;
        if (observation.actualBalance.abs() >= denominatorFloor) {
          percentage +=
              observation.error.abs() / observation.actualBalance.abs();
          percentageSamples++;
        }
        qLoss += observation.quantileLoss;
        brier += observation.brier;
        risk.add((
          predicted: observation.prediction.gapRisk,
          actual: observation.actualGap,
        ));
      }
      metrics.add(HorizonBacktestMetrics(
        horizonDays: horizon,
        samples: own.length,
        mae: absolute / own.length,
        mape: percentageSamples == 0
            ? null
            : percentage / percentageSamples * 100,
        coverage: covered / own.length,
        bias: signed / own.length,
        quantileLoss: qLoss / own.length,
        brierScore: brier / own.length,
        riskObservations: risk,
      ));
    }

    return HorizonLiveCalibrationReport(
      evaluatedAt: today,
      observations: observations,
      metrics: metrics,
    );
  }

  static MultiHorizonBacktest blendWithBacktest({
    required MultiHorizonBacktest backtest,
    required HorizonLiveCalibrationReport live,
    required HorizonTuning tuning,
  }) {
    final blended = <HorizonBacktestMetrics>[];
    for (final horizon in trackedHorizons) {
      final historical = backtest.forHorizon(horizon);
      final realized = live.metrics
          .where((m) => m.horizonDays == horizon)
          .cast<HorizonBacktestMetrics?>()
          .firstOrNull;
      if (historical == null || historical.samples == 0) {
        if (realized != null) blended.add(realized);
        continue;
      }
      if (realized == null || realized.samples == 0) {
        blended.add(historical);
        continue;
      }

      final liveWeight = (realized.samples / 30.0).clamp(0.15, 0.80).toDouble();
      final backWeight = 1 - liveWeight;
      double? blendNullable(double? a, double? b) {
        if (a == null) return b;
        if (b == null) return a;
        return a * backWeight + b * liveWeight;
      }

      blended.add(HorizonBacktestMetrics(
        horizonDays: horizon,
        samples: historical.samples + realized.samples,
        mae: historical.mae * backWeight + realized.mae * liveWeight,
        mape: blendNullable(historical.mape, realized.mape),
        coverage:
            historical.coverage * backWeight + realized.coverage * liveWeight,
        bias: historical.bias * backWeight + realized.bias * liveWeight,
        quantileLoss: historical.quantileLoss * backWeight +
            realized.quantileLoss * liveWeight,
        brierScore: historical.brierScore * backWeight +
            realized.brierScore * liveWeight,
        riskObservations: [
          ...historical.riskObservations,
          ...realized.riskObservations,
        ],
      ));
    }
    return MultiHorizonBacktest(
      metrics: blended,
      tuning: tuning,
      seedCount: backtest.seedCount,
      evaluatedAt: live.evaluatedAt,
    );
  }

  static Future<void> clearForTest() async {
    final box = await _open();
    await box.clear();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
