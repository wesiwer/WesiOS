import 'dart:math';

/// Tunable parameters of Wesi Horizon. They are deliberately compact and
/// interpretable: the monthly learning loop may move them inside safe bounds,
/// but cannot turn the model into an opaque black box.
class HorizonTuning {
  final double meanReversionDays;
  final double trendDecayDays;
  final double seasonalityDecayDays;
  final double regimeStrength;
  final double lowDataUncertainty;

  const HorizonTuning({
    this.meanReversionDays = 45,
    this.trendDecayDays = 28,
    this.seasonalityDecayDays = 75,
    this.regimeStrength = 1,
    this.lowDataUncertainty = 1.65,
  });

  static const defaults = HorizonTuning();

  HorizonTuning clamped() => HorizonTuning(
        meanReversionDays: meanReversionDays.clamp(21.0, 120.0).toDouble(),
        trendDecayDays: trendDecayDays.clamp(14.0, 90.0).toDouble(),
        seasonalityDecayDays: seasonalityDecayDays.clamp(30.0, 180.0).toDouble(),
        regimeStrength: regimeStrength.clamp(0.35, 1.5).toDouble(),
        lowDataUncertainty: lowDataUncertainty.clamp(1.2, 3.0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'meanReversionDays': meanReversionDays,
        'trendDecayDays': trendDecayDays,
        'seasonalityDecayDays': seasonalityDecayDays,
        'regimeStrength': regimeStrength,
        'lowDataUncertainty': lowDataUncertainty,
      };

  factory HorizonTuning.fromJson(Map<String, dynamic> json) => HorizonTuning(
        meanReversionDays:
            (json['meanReversionDays'] as num?)?.toDouble() ?? 45,
        trendDecayDays: (json['trendDecayDays'] as num?)?.toDouble() ?? 28,
        seasonalityDecayDays:
            (json['seasonalityDecayDays'] as num?)?.toDouble() ?? 75,
        regimeStrength:
            (json['regimeStrength'] as num?)?.toDouble() ?? 1,
        lowDataUncertainty:
            (json['lowDataUncertainty'] as num?)?.toDouble() ?? 1.65,
      ).clamped();
}

class RiskCalibrationBin {
  final double lower;
  final double upper;
  final double observedRate;
  final int samples;

  const RiskCalibrationBin({
    required this.lower,
    required this.upper,
    required this.observedRate,
    required this.samples,
  });

  bool contains(double p) => p >= lower && (p < upper || upper >= 1);

  Map<String, dynamic> toJson() => {
        'lower': lower,
        'upper': upper,
        'observedRate': observedRate,
        'samples': samples,
      };

  factory RiskCalibrationBin.fromJson(Map<String, dynamic> json) =>
      RiskCalibrationBin(
        lower: (json['lower'] as num?)?.toDouble() ?? 0,
        upper: (json['upper'] as num?)?.toDouble() ?? 1,
        observedRate: (json['observedRate'] as num?)?.toDouble() ?? 0,
        samples: (json['samples'] as num?)?.toInt() ?? 0,
      );
}

/// Calibration learned from backtests for one horizon bucket.
class HorizonCalibrationBucket {
  final int horizonDays;
  final double intervalScale;

  /// actual - predicted terminal/trajectory balance. Positive means the old
  /// model was too pessimistic and P50 has to move up.
  final double biasCorrection;
  final double coverage;
  final double? mape;
  final double quantileLoss;
  final List<RiskCalibrationBin> riskBins;
  final int samples;

  const HorizonCalibrationBucket({
    required this.horizonDays,
    this.intervalScale = 1,
    this.biasCorrection = 0,
    this.coverage = 0.8,
    this.mape,
    this.quantileLoss = 0,
    this.riskBins = const [],
    this.samples = 0,
  });

  double calibrateRisk(double probability) {
    final p = probability.clamp(0.0, 1.0).toDouble();
    if (riskBins.isEmpty) return p;
    for (final bin in riskBins) {
      if (!bin.contains(p)) continue;
      // Shrink sparse empirical bins back toward the model probability. This
      // avoids turning two historical events into a fake 0%/100% certainty.
      const prior = 12.0;
      return ((bin.observedRate * bin.samples) + (p * prior)) /
          (bin.samples + prior);
    }
    return p;
  }

  Map<String, dynamic> toJson() => {
        'horizonDays': horizonDays,
        'intervalScale': intervalScale,
        'biasCorrection': biasCorrection,
        'coverage': coverage,
        'mape': mape,
        'quantileLoss': quantileLoss,
        'riskBins': riskBins.map((e) => e.toJson()).toList(),
        'samples': samples,
      };

  factory HorizonCalibrationBucket.fromJson(Map<String, dynamic> json) =>
      HorizonCalibrationBucket(
        horizonDays: (json['horizonDays'] as num?)?.toInt() ?? 30,
        intervalScale:
            (json['intervalScale'] as num?)?.toDouble().clamp(0.55, 3.0).toDouble() ?? 1,
        biasCorrection:
            (json['biasCorrection'] as num?)?.toDouble() ?? 0,
        coverage: (json['coverage'] as num?)?.toDouble() ?? 0.8,
        mape: (json['mape'] as num?)?.toDouble(),
        quantileLoss: (json['quantileLoss'] as num?)?.toDouble() ?? 0,
        riskBins: [
          for (final raw in (json['riskBins'] as List? ?? const []))
            if (raw is Map)
              RiskCalibrationBin.fromJson(Map<String, dynamic>.from(raw)),
        ],
        samples: (json['samples'] as num?)?.toInt() ?? 0,
      );
}

class HorizonCalibrationProfile {
  final DateTime? updatedAt;
  final HorizonTuning tuning;
  final List<HorizonCalibrationBucket> buckets;
  final String source;

  const HorizonCalibrationProfile({
    this.updatedAt,
    this.tuning = HorizonTuning.defaults,
    this.buckets = const [],
    this.source = 'identity',
  });

  static const identity = HorizonCalibrationProfile();

  HorizonCalibrationBucket bucketFor(int days) {
    if (buckets.isEmpty) {
      return HorizonCalibrationBucket(horizonDays: days);
    }
    HorizonCalibrationBucket best = buckets.first;
    var distance = (best.horizonDays - days).abs();
    for (final bucket in buckets.skip(1)) {
      final nextDistance = (bucket.horizonDays - days).abs();
      if (nextDistance < distance) {
        best = bucket;
        distance = nextDistance;
      }
    }
    return best;
  }

  Map<String, dynamic> toJson() => {
        'updatedAt': updatedAt?.toIso8601String(),
        'tuning': tuning.toJson(),
        'buckets': buckets.map((e) => e.toJson()).toList(),
        'source': source,
      };

  factory HorizonCalibrationProfile.fromJson(Map<String, dynamic> json) =>
      HorizonCalibrationProfile(
        updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}'),
        tuning: json['tuning'] is Map
            ? HorizonTuning.fromJson(
                Map<String, dynamic>.from(json['tuning'] as Map))
            : HorizonTuning.defaults,
        buckets: [
          for (final raw in (json['buckets'] as List? ?? const []))
            if (raw is Map)
              HorizonCalibrationBucket.fromJson(
                  Map<String, dynamic>.from(raw)),
        ],
        source: '${json['source'] ?? 'stored'}',
      );
}

/// Safe candidate set for the monthly learning loop. We tune only a handful
/// of interpretable knobs and keep hard bounds. This is intentionally not a
/// free-form optimizer that can overfit a short personal cash history.
class HorizonTuningCandidates {
  static const values = <HorizonTuning>[
    HorizonTuning(
      meanReversionDays: 30,
      trendDecayDays: 21,
      seasonalityDecayDays: 60,
      regimeStrength: 0.8,
    ),
    HorizonTuning(),
    HorizonTuning(
      meanReversionDays: 60,
      trendDecayDays: 35,
      seasonalityDecayDays: 90,
      regimeStrength: 1.0,
    ),
    HorizonTuning(
      meanReversionDays: 90,
      trendDecayDays: 50,
      seasonalityDecayDays: 120,
      regimeStrength: 0.7,
    ),
  ];
}

/// Coverage target of a P10..P90 interval.
const double horizonTargetCoverage = 0.80;

/// Width calibration: under-coverage expands aggressively; persistent 100%
/// coverage is allowed to narrow. The output is bounded so a noisy backtest
/// cannot explode or collapse the forecast in one month.
double intervalScaleFromCoverage(double coverage) {
  if (!coverage.isFinite || coverage <= 0) return 1.8;
  final raw = horizonTargetCoverage / coverage;
  return raw.clamp(0.65, 2.5).toDouble();
}

double pinballLoss(double actual, double predicted, double quantile) {
  final error = actual - predicted;
  return max(quantile * error, (quantile - 1) * error);
}
