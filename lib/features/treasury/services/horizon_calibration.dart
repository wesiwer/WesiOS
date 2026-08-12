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
        seasonalityDecayDays:
            seasonalityDecayDays.clamp(30.0, 180.0).toDouble(),
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
        regimeStrength: (json['regimeStrength'] as num?)?.toDouble() ?? 1,
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
  double get midpoint => ((lower + min(upper, 1.0)) / 2).clamp(0.0, 1.0);

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

  /// Отдельные множители для нижней и верхней половины интервала.
  ///
  /// Один общий множитель растягивал обе стороны одинаково, а денежные
  /// исходы несимметричны: снизу редкие крупные списания и сорванные
  /// поступления, сверху — просто «пришло чуть больше обычного». Хвосты
  /// поэтому промахиваются по-разному, и подтягивать их надо порознь.
  ///
  /// Считаются как эмпирические квантили нормализованных промахов из
  /// ретро-проверки — так же, как это делает конформный прогноз: берётся не
  /// предположение о форме распределения, а то, насколько модель на самом
  /// деле промахнулась в прошлом. Ноль означает «раздельной калибровки ещё
  /// нет», и тогда работает общий [intervalScale] — так старые сохранённые
  /// профили продолжают читаться без миграции.
  final double lowerScale;
  final double upperScale;

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
    this.lowerScale = 0,
    this.upperScale = 0,
    this.biasCorrection = 0,
    this.coverage = 0.8,
    this.mape,
    this.quantileLoss = 0,
    this.riskBins = const [],
    this.samples = 0,
  });

  /// Monotone empirical probability calibration.
  ///
  /// Sparse bins are Bayesian-shrunk toward their predicted midpoint. The
  /// resulting calibration curve is forced to be non-decreasing and then
  /// linearly interpolated. This avoids impossible behavior such as a raw 30%
  /// gap risk being calibrated below a raw 10% risk merely because adjacent
  /// bins were noisy.
  double calibrateRisk(double probability) {
    final p = probability.clamp(0.0, 1.0).toDouble();
    if (riskBins.isEmpty) return p;

    final ordered = [...riskBins]..sort((a, b) => a.midpoint.compareTo(b.midpoint));
    const prior = 12.0;
    final x = <double>[];
    final y = <double>[];
    var floor = 0.0;
    for (final bin in ordered) {
      if (bin.samples <= 0) continue;
      final center = bin.midpoint;
      final shrunk = ((bin.observedRate.clamp(0.0, 1.0) * bin.samples) +
              (center * prior)) /
          (bin.samples + prior);
      final monotone = max(floor, shrunk).clamp(0.0, 1.0).toDouble();
      x.add(center);
      y.add(monotone);
      floor = monotone;
    }
    if (x.isEmpty) return p;
    if (x.length == 1) {
      final evidence = min(1.0, ordered.first.samples / 40.0);
      return (p * (1 - evidence) + y.first * evidence)
          .clamp(0.0, 1.0)
          .toDouble();
    }
    if (p <= x.first) {
      final slope = (y[1] - y[0]) / max(1e-9, x[1] - x[0]);
      return (y.first + slope * (p - x.first)).clamp(0.0, 1.0).toDouble();
    }
    if (p >= x.last) {
      final n = x.length;
      final slope = (y[n - 1] - y[n - 2]) /
          max(1e-9, x[n - 1] - x[n - 2]);
      return (y.last + slope * (p - x.last)).clamp(0.0, 1.0).toDouble();
    }
    for (var i = 1; i < x.length; i++) {
      if (p > x[i]) continue;
      final t = (p - x[i - 1]) / max(1e-9, x[i] - x[i - 1]);
      return (y[i - 1] + (y[i] - y[i - 1]) * t)
          .clamp(0.0, 1.0)
          .toDouble();
    }
    return p;
  }

  Map<String, dynamic> toJson() => {
        'horizonDays': horizonDays,
        'intervalScale': intervalScale,
        'lowerScale': lowerScale,
        'upperScale': upperScale,
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
        intervalScale: (json['intervalScale'] as num?)
                ?.toDouble()
                .clamp(0.55, 3.0)
                .toDouble() ??
            1,
        lowerScale: (json['lowerScale'] as num?)
                ?.toDouble()
                .clamp(0.0, 3.0)
                .toDouble() ??
            0,
        upperScale: (json['upperScale'] as num?)
                ?.toDouble()
                .clamp(0.0, 3.0)
                .toDouble() ??
            0,
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

/// Width calibration with explicit error-awareness.
///
/// Severe under-coverage expands faster than the naive 0.8/coverage ratio.
/// Conversely, a near-100% interval that still has huge MAPE is recognized as
/// an uninformatively wide band and is narrowed more aggressively. Bounds
/// prevent one bad month from exploding or collapsing future uncertainty.
double intervalScaleFromCoverage(double coverage, {double? mape}) {
  if (!coverage.isFinite || coverage <= 0) return 1.9;
  var raw = horizonTargetCoverage / coverage;
  if (coverage < 0.65) raw *= 1.10;
  if (coverage >= 0.95 && mape != null && mape.isFinite && mape > 40) {
    raw *= 0.85;
  }
  return raw.clamp(0.55, 2.75).toDouble();
}

/// Конформный множитель полуинтервала по промахам из ретро-проверки.
///
/// [ratios] — отношения «насколько модель промахнулась» к «насколько она
/// обещала промахнуться»: |факт − P50| / |граница − P50| для тех случаев,
/// когда факт оказался с этой стороны от медианы. Единица означает, что
/// граница угадана ровно, двойка — что настоящий промах вдвое больше
/// обещанного.
///
/// Берётся эмпирический квантиль порядка [level] — то же, что делает split
/// conformal prediction: никакого предположения о форме распределения, одна
/// голая статистика прошлых ошибок. Поправка (n+1)/n — стандартная для
/// конечной выборки: с малым числом наблюдений интервал обязан быть шире,
/// иначе обещанные 80% на практике окажутся семьюдесятью.
///
/// Ноль возвращается там, где наблюдений слишком мало, чтобы считать
/// квантиль: это сигнал «раздельной калибровки нет», а не «интервал нулевой».
double conformalScale(List<double> ratios, {double level = 0.80}) {
  final usable = ratios.where((r) => r.isFinite && r >= 0).toList()..sort();
  if (usable.length < 8) return 0;
  final rank = ((usable.length + 1) * level).ceil().clamp(1, usable.length);
  return usable[rank - 1].clamp(0.55, 2.75).toDouble();
}

double pinballLoss(double actual, double predicted, double quantile) {
  final error = actual - predicted;
  return max(quantile * error, (quantile - 1) * error);
}
