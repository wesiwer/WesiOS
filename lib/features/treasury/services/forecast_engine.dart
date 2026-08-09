import 'dart:math';

import '../models/transaction_model.dart';
import 'horizon_calibration.dart';
import 'recurring_engine.dart';

/// One hypothetical future income/expense for What-If. It never touches the
/// real Treasury ledger.
class WhatIfEvent {
  final String title;
  final double amount;
  final TransactionType type;
  final DateTime date;
  final RecurringPeriod? recurringPeriod;

  const WhatIfEvent({
    required this.title,
    required this.amount,
    required this.type,
    required this.date,
    this.recurringPeriod,
  });

  bool get isRecurring => recurringPeriod != null;
}

/// Virtual scenario. New stress fields are optional so old saved presets keep
/// their exact semantics.
class WhatIfScenario {
  final List<WhatIfEvent> events;
  final double incomeMultiplier;
  final double expenseMultiplier;

  /// Zero means the multiplier applies for the full selected horizon. A
  /// positive value limits it to the first N future days (stress library).
  final int incomeMultiplierDays;
  final int expenseMultiplierDays;

  /// Delay all uncertain incoming cash by this many days. Used by the stress
  /// library; zero preserves the old behaviour.
  final int incomeDelayDays;

  /// For the first N days the main uncertain income stream is mostly absent.
  /// This represents losing the main source without pretending it lasts
  /// forever.
  final int mainIncomeLossDays;

  /// Immediate unexpected expense on day 1.
  final double oneOffExpenseShock;

  const WhatIfScenario({
    this.events = const [],
    this.incomeMultiplier = 1.0,
    this.expenseMultiplier = 1.0,
    this.incomeMultiplierDays = 0,
    this.expenseMultiplierDays = 0,
    this.incomeDelayDays = 0,
    this.mainIncomeLossDays = 0,
    this.oneOffExpenseShock = 0,
  });

  bool get isEmpty =>
      events.isEmpty &&
      incomeMultiplier == 1.0 &&
      expenseMultiplier == 1.0 &&
      incomeMultiplierDays == 0 &&
      expenseMultiplierDays == 0 &&
      incomeDelayDays == 0 &&
      mainIncomeLossDays == 0 &&
      oneOffExpenseShock == 0;

  WhatIfScenario merge(WhatIfScenario other) => WhatIfScenario(
        events: [...events, ...other.events],
        incomeMultiplier: incomeMultiplier * other.incomeMultiplier,
        expenseMultiplier: expenseMultiplier * other.expenseMultiplier,
        incomeMultiplierDays:
            max(incomeMultiplierDays, other.incomeMultiplierDays),
        expenseMultiplierDays:
            max(expenseMultiplierDays, other.expenseMultiplierDays),
        incomeDelayDays: max(incomeDelayDays, other.incomeDelayDays),
        mainIncomeLossDays: max(mainIncomeLossDays, other.mainIncomeLossDays),
        oneOffExpenseShock: oneOffExpenseShock + other.oneOffExpenseShock,
      );

  static const WhatIfScenario none = WhatIfScenario();
}

enum ForecastConfidence { insufficient, low, medium, high }

enum CashRegime { downturn, stable, growth }

enum ForecastPromptSeverity { info, warning, critical }

class HorizonCashEvent {
  final String title;

  /// Signed amount: income positive, expense negative.
  final double amount;
  final DateTime date;
  final double probability;
  final bool committed;
  final String source;
  final String? accountId;

  const HorizonCashEvent({
    required this.title,
    required this.amount,
    required this.date,
    this.probability = 1,
    this.committed = false,
    this.source = 'external',
    this.accountId,
  });
}

class AccountLiquiditySnapshot {
  final String accountId;
  final String name;
  final String currency;
  final double balance;
  final double minimumBalance;
  final bool allowNetting;
  final double fxHaircut;
  final int transferDelayDays;

  const AccountLiquiditySnapshot({
    required this.accountId,
    required this.name,
    required this.balance,
    this.currency = 'RUB',
    this.minimumBalance = 0,
    this.allowNetting = true,
    this.fxHaircut = 0.03,
    this.transferDelayDays = 0,
  });
}

class AccountLiquidityRisk {
  final String accountId;
  final String name;
  final String currency;
  final double currentBalance;
  final double projectedP10;
  final int? riskDay;
  final bool canBeCoveredByNetting;
  final double nettableLiquidity;
  final int? earliestNettingDay;

  const AccountLiquidityRisk({
    required this.accountId,
    required this.name,
    required this.currency,
    required this.currentBalance,
    required this.projectedP10,
    required this.riskDay,
    required this.canBeCoveredByNetting,
    this.nettableLiquidity = 0,
    this.earliestNettingDay,
  });
}

class ForecastExplanation {
  final int day;
  final String source;
  final String titleRu;
  final String titleEn;
  final double impact;

  const ForecastExplanation({
    required this.day,
    required this.source,
    required this.titleRu,
    required this.titleEn,
    required this.impact,
  });
}

class ForecastActionPrompt {
  final String code;
  final ForecastPromptSeverity severity;
  final String textRu;
  final String textEn;
  final double? amount;
  final int? day;

  const ForecastActionPrompt({
    required this.code,
    required this.severity,
    required this.textRu,
    required this.textEn,
    this.amount,
    this.day,
  });
}

class ForecastScenarioSummary {
  final String key;
  final String labelRu;
  final String labelEn;
  final double endingP50;
  final double minimumP10;
  final double maximumGapRisk;
  final int? runwayDays;

  const ForecastScenarioSummary({
    required this.key,
    required this.labelRu,
    required this.labelEn,
    required this.endingP50,
    required this.minimumP10,
    required this.maximumGapRisk,
    this.runwayDays,
  });
}

class WhatIfRiskDelta {
  final double baseMaximumRisk;
  final double scenarioMaximumRisk;
  final int? baseRunwayDays;
  final int? scenarioRunwayDays;

  const WhatIfRiskDelta({
    required this.baseMaximumRisk,
    required this.scenarioMaximumRisk,
    this.baseRunwayDays,
    this.scenarioRunwayDays,
  });

  double get riskDelta => scenarioMaximumRisk - baseMaximumRisk;
}

/// Result of Wesi Horizon. The original public fields remain intact so old UI
/// and external engines keep compiling; top-tier diagnostics are additive.
class ForecastResult {
  final List<double> p10;
  final List<double> p50;
  final List<double> p90;
  final double trendPerDay;
  final double dailyVolatility;
  final int historyDaysSpan;
  final int simulatedPaths;
  final bool insufficientData;
  final bool seasonalityApplied;
  final List<double> weekdayFactor;
  final List<double> belowZeroProbability;
  final int? runwayDays;
  final int? riskAlertDay;

  final ForecastConfidence confidence;
  final double longRunBaselinePerDay;
  final double recentNetPerDay;
  final double driftCapPerDay;
  final double uncertaintyScale;
  final double committedNearTerm;
  final double recommendedReserve;
  final double safetyBuffer;
  final int? risk10Day;
  final int? risk25Day;
  final double intervalCalibrationScale;
  final double biasCorrection;
  final double calibrationCoverage;
  final int calibrationSamples;
  final String calibrationSource;
  final CashRegime regime;
  final Map<CashRegime, double> regimeProbabilities;
  final Map<String, double> streamContribution;
  final List<double> committedNetByDay;
  final List<double> uncertainMedianByDay;
  final List<ForecastExplanation> explanations;
  final List<ForecastActionPrompt> actionPrompts;
  final List<ForecastScenarioSummary> scenarioSummaries;
  final WhatIfRiskDelta? whatIfRiskDelta;
  final List<AccountLiquidityRisk> accountLiquidityRisks;
  final double knownCashShare;

  const ForecastResult({
    required this.p10,
    required this.p50,
    required this.p90,
    required this.trendPerDay,
    required this.dailyVolatility,
    required this.historyDaysSpan,
    required this.simulatedPaths,
    required this.insufficientData,
    required this.seasonalityApplied,
    this.weekdayFactor = const [],
    this.belowZeroProbability = const [],
    this.runwayDays,
    this.riskAlertDay,
    this.confidence = ForecastConfidence.medium,
    this.longRunBaselinePerDay = 0,
    this.recentNetPerDay = 0,
    this.driftCapPerDay = 0,
    this.uncertaintyScale = 1,
    this.committedNearTerm = 0,
    this.recommendedReserve = 0,
    this.safetyBuffer = 0,
    this.risk10Day,
    this.risk25Day,
    this.intervalCalibrationScale = 1,
    this.biasCorrection = 0,
    this.calibrationCoverage = 0,
    this.calibrationSamples = 0,
    this.calibrationSource = 'identity',
    this.regime = CashRegime.stable,
    this.regimeProbabilities = const {CashRegime.stable: 1},
    this.streamContribution = const {},
    this.committedNetByDay = const [],
    this.uncertainMedianByDay = const [],
    this.explanations = const [],
    this.actionPrompts = const [],
    this.scenarioSummaries = const [],
    this.whatIfRiskDelta,
    this.accountLiquidityRisks = const [],
    this.knownCashShare = 0,
  });

  factory ForecastResult.empty() => const ForecastResult(
        p10: [],
        p50: [],
        p90: [],
        trendPerDay: 0,
        dailyVolatility: 0,
        historyDaysSpan: 0,
        simulatedPaths: 0,
        insufficientData: true,
        seasonalityApplied: false,
        confidence: ForecastConfidence.insufficient,
      );

  double get maximumGapRisk =>
      belowZeroProbability.isEmpty ? 0 : belowZeroProbability.reduce(max);

  ForecastResult copyWith({
    List<ForecastScenarioSummary>? scenarioSummaries,
    WhatIfRiskDelta? whatIfRiskDelta,
    bool clearWhatIfRiskDelta = false,
    List<AccountLiquidityRisk>? accountLiquidityRisks,
    List<ForecastActionPrompt>? actionPrompts,
    List<ForecastExplanation>? explanations,
  }) =>
      ForecastResult(
        p10: p10,
        p50: p50,
        p90: p90,
        trendPerDay: trendPerDay,
        dailyVolatility: dailyVolatility,
        historyDaysSpan: historyDaysSpan,
        simulatedPaths: simulatedPaths,
        insufficientData: insufficientData,
        seasonalityApplied: seasonalityApplied,
        weekdayFactor: weekdayFactor,
        belowZeroProbability: belowZeroProbability,
        runwayDays: runwayDays,
        riskAlertDay: riskAlertDay,
        confidence: confidence,
        longRunBaselinePerDay: longRunBaselinePerDay,
        recentNetPerDay: recentNetPerDay,
        driftCapPerDay: driftCapPerDay,
        uncertaintyScale: uncertaintyScale,
        committedNearTerm: committedNearTerm,
        recommendedReserve: recommendedReserve,
        safetyBuffer: safetyBuffer,
        risk10Day: risk10Day,
        risk25Day: risk25Day,
        intervalCalibrationScale: intervalCalibrationScale,
        biasCorrection: biasCorrection,
        calibrationCoverage: calibrationCoverage,
        calibrationSamples: calibrationSamples,
        calibrationSource: calibrationSource,
        regime: regime,
        regimeProbabilities: regimeProbabilities,
        streamContribution: streamContribution,
        committedNetByDay: committedNetByDay,
        uncertainMedianByDay: uncertainMedianByDay,
        explanations: explanations ?? this.explanations,
        actionPrompts: actionPrompts ?? this.actionPrompts,
        scenarioSummaries: scenarioSummaries ?? this.scenarioSummaries,
        whatIfRiskDelta: clearWhatIfRiskDelta
            ? null
            : (whatIfRiskDelta ?? this.whatIfRiskDelta),
        accountLiquidityRisks:
            accountLiquidityRisks ?? this.accountLiquidityRisks,
        knownCashShare: knownCashShare,
      );

  Map<String, List<double>> toMap() => {'p10': p10, 'p50': p50, 'p90': p90};
}

class _StreamStats {
  final String key;
  final TransactionType type;
  final List<double> weekdayFactor;
  final double baselineFrequency;
  final double recentFrequency;
  final double baselineAmount;
  final double recentAmount;
  final double recentSlope;
  final double volatility;
  final double dailyBaseline;
  final double dailyRecent;

  const _StreamStats({
    required this.key,
    required this.type,
    required this.weekdayFactor,
    required this.baselineFrequency,
    required this.recentFrequency,
    required this.baselineAmount,
    required this.recentAmount,
    required this.recentSlope,
    required this.volatility,
    required this.dailyBaseline,
    required this.dailyRecent,
  });

  static _StreamStats compute({
    required String key,
    required TransactionType type,
    required List<double> dense,
    required DateTime minDay,
    required Set<int> excludedDays,
    required bool seasonalityApplied,
  }) {
    final usable = <double>[];
    final positive = <double>[];
    for (var i = 0; i < dense.length; i++) {
      if (excludedDays.contains(i)) continue;
      usable.add(dense[i]);
      if (dense[i] > 0) positive.add(dense[i]);
    }
    final baselineFrequency = usable.isEmpty
        ? 0.0
        : usable.where((v) => v > 0).length / usable.length;
    final baselineAmount = positive.isEmpty ? 0.0 : _winsorMean(positive);

    final recentStart = max(0, dense.length - 21);
    var recentWeight = 1.0;
    var weightedOccurrence = 0.0;
    var totalOccurrenceWeight = 0.0;
    var weightedAmount = 0.0;
    var amountWeight = 0.0;
    var recentUsableDays = 0;
    for (var i = dense.length - 1; i >= recentStart; i--) {
      if (!excludedDays.contains(i)) {
        recentUsableDays++;
        totalOccurrenceWeight += recentWeight;
        if (dense[i] > 0) {
          weightedOccurrence += recentWeight;
          weightedAmount += dense[i] * recentWeight;
          amountWeight += recentWeight;
        }
      }
      recentWeight *= 0.88;
    }
    final recentEvidenceIsThin = recentUsableDays < 7;
    final recentFrequency = recentEvidenceIsThin || totalOccurrenceWeight == 0
        ? baselineFrequency
        : weightedOccurrence / totalOccurrenceWeight;
    final recentAmount = recentEvidenceIsThin || amountWeight == 0
        ? baselineAmount
        : weightedAmount / amountWeight;

    final weekdayFactor = List<double>.filled(7, 0);
    final dailyBaseline = baselineFrequency * baselineAmount;
    if (seasonalityApplied && dense.isNotEmpty) {
      final sum = List<double>.filled(7, 0);
      final count = List<int>.filled(7, 0);
      for (var i = 0; i < dense.length; i++) {
        if (excludedDays.contains(i)) continue;
        final wd = minDay.add(Duration(days: i)).weekday - 1;
        sum[wd] += dense[i];
        count[wd]++;
      }
      for (var wd = 0; wd < 7; wd++) {
        if (count[wd] > 0)
          weekdayFactor[wd] = sum[wd] / count[wd] - dailyBaseline;
      }
    }

    final slopeValues = <double>[];
    for (var i = max(0, dense.length - 21); i < dense.length; i++) {
      slopeValues.add(dense[i]);
    }
    final recentSlope = _linearSlope(slopeValues);
    final residuals = <double>[];
    for (var i = 0; i < dense.length; i++) {
      if (excludedDays.contains(i)) continue;
      final wd = minDay.add(Duration(days: i)).weekday - 1;
      residuals.add(dense[i] - dailyBaseline - weekdayFactor[wd]);
    }

    return _StreamStats(
      key: key,
      type: type,
      weekdayFactor: weekdayFactor,
      baselineFrequency: baselineFrequency,
      recentFrequency: recentFrequency,
      baselineAmount: baselineAmount,
      recentAmount: recentAmount,
      recentSlope: recentSlope,
      volatility: _stdDev(residuals),
      dailyBaseline: dailyBaseline,
      dailyRecent: recentFrequency * recentAmount,
    );
  }

  double expectedForDay(int day, int weekday, HorizonTuning tuning) {
    // Explicit horizon contract:
    //  1..14  — recent rhythm/facts dominate;
    // 15..60  — recent pace mean-reverts materially;
    // 61+     — long-run baseline dominates and recent luck dies quickly.
    final double recentWeight;
    if (day <= 14) {
      recentWeight = 1.0 - 0.15 * (day / 14.0);
    } else if (day <= 60) {
      recentWeight =
          0.85 * exp(-(day - 14) / (tuning.meanReversionDays * 0.90));
    } else {
      final at60 = 0.85 * exp(-46 / (tuning.meanReversionDays * 0.90));
      recentWeight =
          at60 * exp(-(day - 60) / (tuning.meanReversionDays * 0.55));
    }
    final base = dailyBaseline + (dailyRecent - dailyBaseline) * recentWeight;
    final slopeCap = max(dailyBaseline.abs() * 0.02, volatility * 0.025);
    final cappedSlope = recentSlope.clamp(-slopeCap, slopeCap);
    final horizonTrendDecay = day <= 14
        ? 1.0
        : day <= 60
            ? exp(-(day - 14) / tuning.trendDecayDays)
            : exp(-46 / tuning.trendDecayDays) *
                exp(-(day - 60) / (tuning.trendDecayDays * 0.55));
    final drift = cappedSlope * min(day, 60) * horizonTrendDecay;
    final seasonalityWeight =
        day <= 14 ? 1.0 : exp(-(day - 14) / tuning.seasonalityDecayDays);
    return max(0, base + drift + weekdayFactor[weekday] * seasonalityWeight);
  }

  double get driftCap => max(dailyBaseline.abs() * 0.02, volatility * 0.025);

  static double _winsorMean(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.of(values)..sort();
    final lo =
        sorted[(sorted.length * 0.05).floor().clamp(0, sorted.length - 1)];
    final hi =
        sorted[(sorted.length * 0.95).floor().clamp(0, sorted.length - 1)];
    var sum = 0.0;
    for (final value in values) {
      sum += value.clamp(lo, hi).toDouble();
    }
    return sum / values.length;
  }

  static double _linearSlope(List<double> values) {
    if (values.length < 3) return 0;
    final xMean = (values.length - 1) / 2.0;
    final yMean = values.reduce((a, b) => a + b) / values.length;
    var num = 0.0;
    var den = 0.0;
    for (var i = 0; i < values.length; i++) {
      final dx = i - xMean;
      num += dx * (values[i] - yMean);
      den += dx * dx;
    }
    return den == 0 ? 0 : num / den;
  }

  static double _stdDev(List<double> values) {
    if (values.length < 2) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    var sum = 0.0;
    for (final value in values) {
      final d = value - mean;
      sum += d * d;
    }
    return sqrt(sum / (values.length - 1));
  }
}

class _RegimeModel {
  final CashRegime current;
  final Map<CashRegime, double> probabilities;
  final Map<CashRegime, Map<CashRegime, double>> transitions;

  const _RegimeModel(this.current, this.probabilities, this.transitions);

  static const Map<CashRegime, Map<CashRegime, double>> _prior = {
    CashRegime.downturn: {
      CashRegime.downturn: 0.64,
      CashRegime.stable: 0.30,
      CashRegime.growth: 0.06,
    },
    CashRegime.stable: {
      CashRegime.downturn: 0.10,
      CashRegime.stable: 0.80,
      CashRegime.growth: 0.10,
    },
    CashRegime.growth: {
      CashRegime.downturn: 0.06,
      CashRegime.stable: 0.32,
      CashRegime.growth: 0.62,
    },
  };

  static _RegimeModel detect(List<double> denseNet) {
    if (denseNet.length < 14) {
      return const _RegimeModel(
        CashRegime.stable,
        {CashRegime.stable: 1},
        _prior,
      );
    }

    final baselineWindow = denseNet.length > 120
        ? denseNet.sublist(denseNet.length - 120)
        : denseNet;
    final baseline =
        baselineWindow.reduce((a, b) => a + b) / baselineWindow.length;
    final vol = max(1.0, _StreamStats._stdDev(baselineWindow));

    CashRegime classify(List<double> values) {
      if (values.isEmpty) return CashRegime.stable;
      final mean = values.reduce((a, b) => a + b) / values.length;
      final z = (mean - baseline) / vol;
      if (z >= 0.45) return CashRegime.growth;
      if (z <= -0.45) return CashRegime.downturn;
      return CashRegime.stable;
    }

    // Learn transitions from non-overlapping weekly states. A Bayesian prior
    // prevents a short history from inventing 0%/100% transition certainty.
    final weekly = <CashRegime>[];
    for (var end = 7; end <= denseNet.length; end += 7) {
      weekly.add(classify(denseNet.sublist(max(0, end - 7), end)));
    }
    if (weekly.isEmpty) weekly.add(CashRegime.stable);

    final counts = <CashRegime, Map<CashRegime, double>>{
      for (final from in CashRegime.values)
        from: {
          for (final to in CashRegime.values)
            to: (_prior[from]?[to] ?? 0) * 8.0,
        },
    };
    for (var i = 1; i < weekly.length; i++) {
      counts[weekly[i - 1]]![weekly[i]] =
          (counts[weekly[i - 1]]![weekly[i]] ?? 0) + 1;
    }
    final learned = <CashRegime, Map<CashRegime, double>>{};
    for (final from in CashRegime.values) {
      final row = counts[from]!;
      final total = row.values.fold<double>(0, (a, b) => a + b);
      learned[from] = {
        for (final to in CashRegime.values) to: row[to]! / total,
      };
    }

    final recent = denseNet.sublist(max(0, denseNet.length - 14));
    final recentMean = recent.reduce((a, b) => a + b) / recent.length;
    final z = (recentMean - baseline) / vol;
    final growthRaw = _sigmoid(z - 0.25);
    final downturnRaw = _sigmoid(-z - 0.25);
    final stableRaw = exp(-z.abs() * 0.8);
    final total = growthRaw + downturnRaw + stableRaw;
    final probs = <CashRegime, double>{
      CashRegime.growth: growthRaw / total,
      CashRegime.downturn: downturnRaw / total,
      CashRegime.stable: stableRaw / total,
    };
    final current =
        probs.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return _RegimeModel(current, probs, learned);
  }

  static double _sigmoid(double x) => 1 / (1 + exp(-x));

  static CashRegime sampleInitial(Random rng, Map<CashRegime, double> p) =>
      _sample(rng, p);

  CashRegime transition(Random rng, CashRegime from) =>
      _sample(rng, transitions[from] ?? _prior[from]!);

  static CashRegime _sample(Random rng, Map<CashRegime, double> p) {
    final value = rng.nextDouble();
    var cursor = 0.0;
    for (final regime in CashRegime.values) {
      cursor += p[regime] ?? 0;
      if (value <= cursor) return regime;
    }
    return CashRegime.stable;
  }
}

class _ShockPool {
  final List<double> income;
  final List<double> expense;
  final double incomeProbability;
  final double expenseProbability;
  final Set<int> incomeDays;
  final Set<int> expenseDays;

  const _ShockPool({
    required this.income,
    required this.expense,
    required this.incomeProbability,
    required this.expenseProbability,
    required this.incomeDays,
    required this.expenseDays,
  });

  static _ShockPool detect(
    List<TransactionModel> txs,
    DateTime minDay,
    int spanDays,
  ) {
    List<TransactionModel> outliers(TransactionType type) {
      final typed = txs.where((t) => t.type == type).toList();
      if (typed.length < 5) return const [];
      final values = typed.map((e) => e.amount).toList()..sort();
      final median = _median(values);
      final deviations = values.map((e) => (e - median).abs()).toList()..sort();
      final mad = _median(deviations);
      if (mad <= 0) {
        final mean = values.reduce((a, b) => a + b) / values.length;
        final sd = _StreamStats._stdDev(values);
        if (sd == 0) return const [];
        return typed.where((t) => (t.amount - mean).abs() / sd > 2.5).toList();
      }
      return typed
          .where((t) => (0.6745 * (t.amount - median) / mad).abs() > 3.5)
          .toList();
    }

    final incomeTx = outliers(TransactionType.income);
    final expenseTx = outliers(TransactionType.expense);
    Set<int> daySet(List<TransactionModel> list) => {
          for (final tx in list)
            DateTime(tx.date.year, tx.date.month, tx.date.day)
                .difference(minDay)
                .inDays,
        }..removeWhere((i) => i < 0 || i >= spanDays);

    int shockEpisodes(List<TransactionModel> list) {
      final days = daySet(list).toList()..sort();
      if (days.isEmpty) return 0;
      var episodes = 1;
      for (var i = 1; i < days.length; i++) {
        if (days[i] - days[i - 1] > 2) episodes++;
      }
      return episodes;
    }

    final incomeEpisodes = shockEpisodes(incomeTx);
    final expenseEpisodes = shockEpisodes(expenseTx);
    return _ShockPool(
      income: incomeTx.map((e) => e.amount).toList(),
      expense: expenseTx.map((e) => e.amount).toList(),
      incomeProbability:
          spanDays == 0 ? 0 : (incomeEpisodes / spanDays).clamp(0.0, 0.12),
      expenseProbability:
          spanDays == 0 ? 0 : (expenseEpisodes / spanDays).clamp(0.0, 0.12),
      incomeDays: daySet(incomeTx),
      expenseDays: daySet(expenseTx),
    );
  }

  static double _median(List<double> sorted) {
    if (sorted.isEmpty) return 0;
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }
}

class ForecastEngine {
  static const int defaultPaths = 5000;
  static const int _minPaths = 100;
  static const int _defaultSeed = 42;
  static const int _seasonalityMinSpanDays = 21;
  static const int minHistorySpanDays = 7;
  static const double _legacyRiskAlertThreshold = 0.05;
  static const int _fullPathsHorizonDays = 120;
  static const int _longHorizonMinPaths = 800;

  static int pathsForHorizon(int days, [int requested = defaultPaths]) {
    final base = requested < _minPaths ? _minPaths : requested;
    if (days <= _fullPathsHorizonDays) return base;
    final scaled = (base * _fullPathsHorizonDays / days).round();
    return scaled < _longHorizonMinPaths ? _longHorizonMinPaths : scaled;
  }

  static ForecastResult generate({
    required List<TransactionModel> transactions,
    required double currentBalance,
    int days = 30,
    int paths = defaultPaths,
    int seed = _defaultSeed,
    WhatIfScenario whatIf = WhatIfScenario.none,
    double annualDiscountRate = 0,
    DateTime? asOf,
    HorizonCalibrationProfile calibration = HorizonCalibrationProfile.identity,
    HorizonTuning? tuning,
    List<HorizonCashEvent> businessEvents = const [],
    Map<String, double> recurringReliability = const {},
    List<AccountLiquiditySnapshot> accounts = const [],
  }) {
    if (days <= 0) return ForecastResult.empty();
    final today = asOf ?? DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final activeTuning = (tuning ?? calibration.tuning).clamped();

    final history = transactions.where((tx) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      return !day.isAfter(todayOnly);
    }).toList();
    final scheduledOneOff = transactions.where((tx) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      return day.isAfter(todayOnly) && !tx.isRecurring;
    }).toList();
    final recurringTxs = history
        .where((t) => t.isRecurring && t.recurringPeriod != null)
        .toList();

    DateTime minDay = todayOnly;
    for (final tx in history) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (day.isBefore(minDay)) minDay = day;
    }
    final spanDays = todayOnly.difference(minDay).inDays + 1;
    final hasKnownForwardCash = recurringTxs.isNotEmpty ||
        businessEvents.isNotEmpty ||
        scheduledOneOff.isNotEmpty;
    if (!hasKnownForwardCash &&
        (history.length < 3 || spanDays < minHistorySpanDays)) {
      return ForecastResult.empty();
    }
    final confidence = _confidence(spanDays, history.length);
    final hasStatisticalHistory =
        spanDays >= minHistorySpanDays && history.length >= 3;
    final seasonalityApplied = spanDays >= _seasonalityMinSpanDays;

    final recurringIds = recurringTxs.map((e) => e.id).toSet();
    final recurringIncomeIds = recurringTxs
        .where((e) => e.type == TransactionType.income)
        .map((e) => e.id)
        .toList();
    bool autoMaterializedIncome(TransactionModel tx) =>
        !tx.isRecurring &&
        recurringIncomeIds.any((id) => tx.id.startsWith('${id}_'));
    final nonRecurring = history
        .where(
            (e) => !recurringIds.contains(e.id) && !autoMaterializedIncome(e))
        .toList();
    final shocks = _ShockPool.detect(nonRecurring, minDay, spanDays);

    final streamKeys = _topStreamKeys(nonRecurring);
    final incomeStreams = <_StreamStats>[];
    final expenseStreams = <_StreamStats>[];
    final denseIncome = List<double>.filled(spanDays, 0);
    final denseExpense = List<double>.filled(spanDays, 0);

    for (final type in TransactionType.values) {
      for (final key in streamKeys) {
        final dense = List<double>.filled(spanDays, 0);
        for (final tx in nonRecurring) {
          if (tx.type != type || _streamKey(tx, streamKeys) != key) continue;
          final idx = DateTime(tx.date.year, tx.date.month, tx.date.day)
              .difference(minDay)
              .inDays;
          if (idx < 0 || idx >= spanDays) continue;
          dense[idx] += tx.amount;
          if (type == TransactionType.income) {
            denseIncome[idx] += tx.amount;
          } else {
            denseExpense[idx] += tx.amount;
          }
        }
        final excluded = type == TransactionType.income
            ? shocks.incomeDays
            : shocks.expenseDays;
        if (dense.every((v) => v == 0)) continue;
        final stats = _StreamStats.compute(
          key: key,
          type: type,
          dense: dense,
          minDay: minDay,
          excludedDays: excluded,
          seasonalityApplied: seasonalityApplied,
        );
        if (type == TransactionType.income) {
          incomeStreams.add(stats);
        } else {
          expenseStreams.add(stats);
        }
      }
    }

    double expectedHistorical(int i, List<_StreamStats> streams) {
      if (streams.isEmpty) return 0;
      final wd = minDay.add(Duration(days: i)).weekday - 1;
      var sum = 0.0;
      for (final s in streams) {
        sum += s.dailyBaseline + (seasonalityApplied ? s.weekdayFactor[wd] : 0);
      }
      return sum;
    }

    final incomeResidual = List<double>.generate(spanDays, (i) {
      if (shocks.incomeDays.contains(i)) return 0;
      return denseIncome[i] - expectedHistorical(i, incomeStreams);
    });
    final expenseResidual = List<double>.generate(spanDays, (i) {
      if (shocks.expenseDays.contains(i)) return 0;
      return denseExpense[i] - expectedHistorical(i, expenseStreams);
    });

    final denseNet = List<double>.generate(
      spanDays,
      (i) => denseIncome[i] - denseExpense[i],
    );
    final regimeModel = _RegimeModel.detect(denseNet);

    final committedByOffset = List<double>.filled(days, 0);
    final knownMagnitudeByOffset = List<double>.filled(days, 0);
    final recurringOccurrences = <int,
        List<
            ({
              double net,
              double probability,
              String title,
              String? accountId
            })>>{};
    final effectiveRecurringReliability = <String, double>{};

    for (final tx in recurringTxs) {
      final projected = RecurringEngine.projectFutureContributions(
        [tx],
        days: days,
        from: todayOnly,
      );
      final reliability = (recurringReliability[tx.id] ??
              _estimateRecurringReliability(tx, transactions, todayOnly))
          .clamp(0.05, 1.0)
          .toDouble();
      effectiveRecurringReliability[tx.id] = reliability;
      for (final entry in projected.entries) {
        final probability = tx.type == TransactionType.expense
            ? max(0.95, reliability)
            : reliability;
        final shiftedOffset = tx.type == TransactionType.income
            ? entry.key + whatIf.incomeDelayDays
            : entry.key;
        if (shiftedOffset < 1 || shiftedOffset > days) continue;

        var modeledNet = entry.value;
        if (modeledNet > 0 &&
            (whatIf.incomeMultiplierDays <= 0 ||
                shiftedOffset <= whatIf.incomeMultiplierDays)) {
          modeledNet *= whatIf.incomeMultiplier;
        } else if (modeledNet < 0 &&
            (whatIf.expenseMultiplierDays <= 0 ||
                shiftedOffset <= whatIf.expenseMultiplierDays)) {
          modeledNet *= whatIf.expenseMultiplier;
        }

        (recurringOccurrences[shiftedOffset] ??= []).add((
          net: modeledNet,
          probability: probability,
          title: tx.title,
          accountId: tx.accountId,
        ));
        if (probability >= 0.9 || tx.type == TransactionType.expense) {
          committedByOffset[shiftedOffset - 1] += modeledNet * probability;
          knownMagnitudeByOffset[shiftedOffset - 1] +=
              modeledNet.abs() * probability;
        }
      }
    }

    final externalByOffset = <int, List<HorizonCashEvent>>{};
    for (final tx in scheduledOneOff) {
      final offset = DateTime(tx.date.year, tx.date.month, tx.date.day)
          .difference(todayOnly)
          .inDays;
      if (offset < 1 || offset > days) continue;
      final event = HorizonCashEvent(
        title: tx.title,
        amount: tx.type == TransactionType.income ? tx.amount : -tx.amount,
        date: tx.date,
        probability: 1,
        committed: true,
        source: 'treasury-scheduled',
        accountId: tx.accountId,
      );
      final shiftedOffset =
          event.amount > 0 ? offset + whatIf.incomeDelayDays : offset;
      if (shiftedOffset >= 1 && shiftedOffset <= days) {
        (externalByOffset[shiftedOffset] ??= []).add(event);
        committedByOffset[shiftedOffset - 1] += event.amount;
        knownMagnitudeByOffset[shiftedOffset - 1] += event.amount.abs();
      }
    }
    for (final event in businessEvents) {
      final offset = DateTime(event.date.year, event.date.month, event.date.day)
          .difference(todayOnly)
          .inDays;
      if (offset < 1 || offset > days) continue;
      final shiftedOffset =
          event.amount > 0 ? offset + whatIf.incomeDelayDays : offset;
      if (shiftedOffset < 1 || shiftedOffset > days) continue;
      (externalByOffset[shiftedOffset] ??= []).add(event);
      if (event.committed) {
        committedByOffset[shiftedOffset - 1] +=
            event.amount * event.probability;
        knownMagnitudeByOffset[shiftedOffset - 1] +=
            event.amount.abs() * event.probability;
      }
    }

    final whatIfByOffset = _projectWhatIf(whatIf, todayOnly, days);
    final fallbackDailyVolatility = _fallbackDailyVolatility(
      history: history,
      events: [...businessEvents, ...externalByOffset.values.expand((e) => e)],
      currentBalance: currentBalance,
    );
    final effectivePaths = pathsForHorizon(days, paths);
    final balances =
        List.generate(days, (_) => List<double>.filled(effectivePaths, 0));
    final minBalances = List<double>.filled(effectivePaths, currentBalance);
    final expectedUncertainNet = List<double>.filled(days, 0);
    final expectedComponentCount = List<int>.filled(days, 0);
    final rng = Random(seed);

    var incomeBaseline = 0.0;
    var expenseBaseline = 0.0;
    var incomeRecent = 0.0;
    var expenseRecent = 0.0;
    var maxDriftCap = 0.0;
    final streamContribution = <String, double>{};
    for (final s in incomeStreams) {
      incomeBaseline += s.dailyBaseline;
      incomeRecent += s.dailyRecent;
      maxDriftCap += s.driftCap;
      streamContribution[s.key] =
          (streamContribution[s.key] ?? 0) + s.dailyBaseline;
    }
    for (final s in expenseStreams) {
      expenseBaseline += s.dailyBaseline;
      expenseRecent += s.dailyRecent;
      maxDriftCap += s.driftCap;
      streamContribution[s.key] =
          (streamContribution[s.key] ?? 0) - s.dailyBaseline;
    }
    final primaryIncomeKey = incomeStreams.isEmpty
        ? null
        : incomeStreams
            .reduce((a, b) => a.dailyBaseline >= b.dailyBaseline ? a : b)
            .key;

    for (var path = 0; path < effectivePaths; path++) {
      var balance = currentBalance;
      var regime = _RegimeModel.sampleInitial(rng, regimeModel.probabilities);
      var blockRemaining = 0;
      var blockIndex = 0;
      var blockLength = 0;
      for (var i = 0; i < days; i++) {
        final day = i + 1;
        final futureDay = todayOnly.add(Duration(days: day));
        final weekday = futureDay.weekday - 1;
        if (i > 0 && i % 7 == 0) regime = regimeModel.transition(rng, regime);

        var expectedIncome = 0.0;
        var expectedExpense = 0.0;
        if (hasStatisticalHistory) {
          for (final s in incomeStreams) {
            var component = s.expectedForDay(day, weekday, activeTuning);
            if (whatIf.mainIncomeLossDays >= day && s.key == primaryIncomeKey) {
              component *= 0.15;
            }
            expectedIncome += component;
          }
          for (final s in expenseStreams) {
            expectedExpense += s.expectedForDay(day, weekday, activeTuning);
          }
        }

        final regimeStrength = activeTuning.regimeStrength;
        switch (regime) {
          case CashRegime.growth:
            expectedIncome *= 1 + 0.12 * regimeStrength;
            expectedExpense *= 1 + 0.015 * regimeStrength;
            break;
          case CashRegime.downturn:
            expectedIncome *= max(0, 1 - 0.22 * regimeStrength);
            expectedExpense *= 1 + 0.06 * regimeStrength;
            break;
          case CashRegime.stable:
            break;
        }

        if (whatIf.incomeMultiplierDays <= 0 ||
            day <= whatIf.incomeMultiplierDays) {
          expectedIncome *= whatIf.incomeMultiplier;
        }
        if (whatIf.expenseMultiplierDays <= 0 ||
            day <= whatIf.expenseMultiplierDays) {
          expectedExpense *= whatIf.expenseMultiplier;
        }

        var residualIncome = 0.0;
        var residualExpense = 0.0;
        if (hasStatisticalHistory && spanDays >= 3) {
          if (blockRemaining <= 0) {
            blockLength = 3 + rng.nextInt(5); // 3..7 day block-bootstrap
            blockIndex = rng.nextInt(
                max(1, spanDays - min(blockLength, spanDays) + 1).toInt());
            blockRemaining = min(blockLength, spanDays);
          }
          final index =
              (blockIndex + (blockLength - blockRemaining)) % spanDays;
          residualIncome = incomeResidual[index];
          residualExpense = expenseResidual[index];
          blockRemaining--;
        } else if (nonRecurring.isNotEmpty) {
          final observedVol = max(
            _StreamStats._stdDev(denseIncome),
            _StreamStats._stdDev(denseExpense),
          );
          // Little uncertain history must NEVER collapse to a fake deterministic line.
          // If observed variance is zero/undefined, derive a conservative
          // scale from known transaction/event amounts (or current cash).
          final fallbackVol = max(observedVol, fallbackDailyVolatility);
          residualIncome = _gaussian(rng) * fallbackVol * 0.5;
          residualExpense = _gaussian(rng) * fallbackVol * 0.5;
        }

        var uncertainty = 1 + 0.32 * sqrt(day / 30.0);
        if (confidence == ForecastConfidence.low) {
          uncertainty *= activeTuning.lowDataUncertainty;
        } else if (confidence == ForecastConfidence.medium) {
          uncertainty *= 1.18;
        }

        // Widen uncertainty around the NET cash center, not each non-negative
        // stream before clipping. Scaling income/expense residuals first and
        // then applying max(0) creates a truncation bias: simply admitting
        // more uncertainty makes distant P50 richer.
        if (whatIf.incomeMultiplierDays <= 0 ||
            day <= whatIf.incomeMultiplierDays) {
          residualIncome *= whatIf.incomeMultiplier;
        }
        if (whatIf.expenseMultiplierDays <= 0 ||
            day <= whatIf.expenseMultiplierDays) {
          residualExpense *= whatIf.expenseMultiplier;
        }

        var sampledIncome = max(0.0, expectedIncome + residualIncome);
        final sampledExpense = max(0.0, expectedExpense + residualExpense);
        if (whatIf.incomeDelayDays > 0 && day <= whatIf.incomeDelayDays) {
          sampledIncome = 0.0;
          expectedIncome = 0.0;
        }
        final expectedNetCenter = expectedIncome - expectedExpense;
        final sampledNet = sampledIncome - sampledExpense;
        var uncertainNet =
            expectedNetCenter + (sampledNet - expectedNetCenter) * uncertainty;

        if (shocks.income.isNotEmpty &&
            rng.nextDouble() < shocks.incomeProbability) {
          uncertainNet += shocks.income[rng.nextInt(shocks.income.length)];
        }
        if (shocks.expense.isNotEmpty &&
            rng.nextDouble() < shocks.expenseProbability) {
          uncertainNet -= shocks.expense[rng.nextInt(shocks.expense.length)];
        }

        var knownNet = 0.0;
        for (final recurring in recurringOccurrences[day] ?? const []) {
          if (rng.nextDouble() <= recurring.probability)
            knownNet += recurring.net;
        }
        for (final event in externalByOffset[day] ?? const []) {
          if (rng.nextDouble() <= event.probability) knownNet += event.amount;
        }

        var scenarioNet = whatIfByOffset[day] ?? 0.0;
        if (day == 1 && whatIf.oneOffExpenseShock > 0) {
          scenarioNet -= whatIf.oneOffExpenseShock;
        }

        balance += uncertainNet + knownNet + scenarioNet;
        balances[i][path] = balance;
        if (balance < minBalances[path]) minBalances[path] = balance;

        expectedUncertainNet[i] += uncertainNet;
        expectedComponentCount[i]++;
      }
    }

    for (var i = 0; i < days; i++) {
      if (expectedComponentCount[i] > 0) {
        expectedUncertainNet[i] /= expectedComponentCount[i];
      }
    }

    final p10 = <double>[];
    final p50 = <double>[];
    final p90 = <double>[];
    final gapRisk = <double>[];
    int? runway;
    int? riskAlert;
    int? risk10;
    int? risk25;

    for (var i = 0; i < days; i++) {
      final sorted = List<double>.of(balances[i])..sort();
      final raw10 = _percentile(sorted, 0.10);
      final raw50 = _percentile(sorted, 0.50);
      final raw90 = _percentile(sorted, 0.90);
      final bucket = calibration.bucketFor(i + 1);
      final progress = min(1.0, (i + 1) / max(1, bucket.horizonDays));
      final adjusted50 = raw50 + bucket.biasCorrection * progress;
      final scale = bucket.intervalScale;
      p10.add(adjusted50 - (raw50 - raw10) * scale);
      p50.add(adjusted50);
      p90.add(adjusted50 + (raw90 - raw50) * scale);

      var negative = sorted.indexWhere((v) => v >= 0);
      if (negative == -1) negative = sorted.length;
      final rawRisk = negative / sorted.length;
      final calibratedRisk =
          bucket.calibrateRisk(rawRisk).clamp(0.0, 1.0).toDouble();
      gapRisk.add(calibratedRisk);

      if (runway == null && p50.last < 0) runway = i + 1;
      if (riskAlert == null && calibratedRisk > _legacyRiskAlertThreshold) {
        riskAlert = i + 1;
      }
      if (risk10 == null && calibratedRisk > 0.10) risk10 = i + 1;
      if (risk25 == null && calibratedRisk > 0.25) risk25 = i + 1;
    }

    if (annualDiscountRate > 0) {
      for (var i = 0; i < days; i++) {
        final factor = 1 / pow(1 + annualDiscountRate, (i + 1) / 365.0);
        p10[i] *= factor;
        p50[i] *= factor;
        p90[i] *= factor;
      }
    }

    final requiredReserveSamples = minBalances
        .map((minBalance) => max(0.0, currentBalance - minBalance))
        .toList()
      ..sort();
    final rawDrawdownReserve = _percentile(requiredReserveSamples, 0.90);
    var committedOutflow30 = 0.0;
    var knownTotal = 0.0;
    var uncertainTotal = 0.0;
    for (var i = 0; i < days; i++) {
      if (i < 30 && committedByOffset[i] < 0) {
        committedOutflow30 += -committedByOffset[i];
      }
      knownTotal += knownMagnitudeByOffset[i];
      uncertainTotal += expectedUncertainNet[i].abs();
    }
    final committedNearTerm = committedOutflow30;
    final recommendedReserve = (rawDrawdownReserve - committedNearTerm)
        .clamp(0.0, double.infinity)
        .toDouble();
    final safetyBuffer =
        currentBalance - recommendedReserve - committedNearTerm;
    final knownShare = knownTotal + uncertainTotal == 0
        ? 0.0
        : knownTotal / (knownTotal + uncertainTotal);

    final volatility = sqrt(
      pow(_StreamStats._stdDev(incomeResidual), 2) +
          pow(_StreamStats._stdDev(expenseResidual), 2),
    );
    final explanations = _buildExplanations(
      days: days,
      committedByOffset: committedByOffset,
      externalByOffset: externalByOffset,
      expectedUncertainNet: expectedUncertainNet,
      volatility: volatility,
      regime: regimeModel.current,
      whatIfByOffset: whatIfByOffset,
      oneOffShock: whatIf.oneOffExpenseShock,
    );
    final prompts = _buildPrompts(
      confidence: confidence,
      currentBalance: currentBalance,
      p10: p10,
      risk10Day: risk10,
      risk25Day: risk25,
      runway: runway,
      safetyBuffer: safetyBuffer,
      committedNearTerm: committedNearTerm,
      denseIncome: denseIncome,
      denseExpense: denseExpense,
      recurringReliability: effectiveRecurringReliability,
    );

    final accountRisks = _accountLiquidityRisks(
      accounts: accounts,
      transactions: transactions,
      businessEvents: businessEvents,
      today: todayOnly,
      days: days,
    );

    final endBucket = calibration.bucketFor(days);
    return ForecastResult(
      p10: p10,
      p50: p50,
      p90: p90,
      trendPerDay: incomeRecent - expenseRecent,
      dailyVolatility: volatility,
      historyDaysSpan: spanDays,
      simulatedPaths: effectivePaths,
      insufficientData: false,
      seasonalityApplied: seasonalityApplied,
      weekdayFactor: _netWeekdayFactor(incomeStreams, expenseStreams),
      belowZeroProbability: gapRisk,
      runwayDays: runway,
      riskAlertDay: riskAlert,
      confidence: confidence,
      longRunBaselinePerDay: incomeBaseline - expenseBaseline,
      recentNetPerDay: incomeRecent - expenseRecent,
      driftCapPerDay: maxDriftCap,
      uncertaintyScale: (1 + 0.32 * sqrt(days / 30.0)) *
          (confidence == ForecastConfidence.low
              ? activeTuning.lowDataUncertainty
              : confidence == ForecastConfidence.medium
                  ? 1.18
                  : 1.0),
      committedNearTerm: committedNearTerm,
      recommendedReserve: recommendedReserve,
      safetyBuffer: safetyBuffer,
      risk10Day: risk10,
      risk25Day: risk25,
      intervalCalibrationScale: endBucket.intervalScale,
      biasCorrection: endBucket.biasCorrection,
      calibrationCoverage: endBucket.coverage,
      calibrationSamples: endBucket.samples,
      calibrationSource: calibration.source,
      regime: regimeModel.current,
      regimeProbabilities: regimeModel.probabilities,
      streamContribution: streamContribution,
      committedNetByDay: committedByOffset,
      uncertainMedianByDay: expectedUncertainNet,
      explanations: explanations,
      actionPrompts: prompts,
      accountLiquidityRisks: accountRisks,
      knownCashShare: knownShare,
    );
  }

  static double _fallbackDailyVolatility({
    required List<TransactionModel> history,
    required List<HorizonCashEvent> events,
    required double currentBalance,
  }) {
    final amounts = <double>[
      ...history.map((e) => e.amount.abs()),
      ...events.map((e) => e.amount.abs()),
    ]..removeWhere((e) => !e.isFinite || e <= 0);
    if (amounts.isNotEmpty) {
      amounts.sort();
      final mid = amounts.length ~/ 2;
      final median = amounts.length.isOdd
          ? amounts[mid]
          : (amounts[mid - 1] + amounts[mid]) / 2;
      // One or two observations are weak evidence, therefore 35% of the
      // typical movement is intentionally conservative rather than zero.
      return max(1.0, median * 0.35);
    }
    // Last-resort scale: with no observed movement at all, admit ignorance.
    // 2% of current liquidity/day prevents a razor-thin long-range band.
    return max(1.0, currentBalance.abs() * 0.02);
  }

  static ForecastConfidence _confidence(int spanDays, int txCount) {
    if (spanDays < minHistorySpanDays || txCount < 3) {
      return ForecastConfidence.low;
    }
    if (spanDays < 28 || txCount < 12) return ForecastConfidence.low;
    if (spanDays < 90 || txCount < 40) return ForecastConfidence.medium;
    return ForecastConfidence.high;
  }

  static String _semanticStream(TransactionModel tx) {
    final rawCategory = (tx.category ?? '').trim().toLowerCase();
    final text = '${tx.category ?? ''} ${tx.title} ${tx.description ?? ''}'
        .toLowerCase();
    bool any(List<String> words) => words.any(text.contains);
    if (any(const [
      'beat',
      'бит',
      'music',
      'музык',
      'royalty',
      'роял',
      'lease',
      'аренд'
    ])) return 'music';
    if (any(const [
      'service',
      'услуг',
      'freelance',
      'фриланс',
      'consult',
      'сведен',
      'mix',
      'master',
      'таргет',
      'design',
      'дизайн'
    ])) return 'services';
    if (any(const ['salary', 'payroll', 'зарплат', 'оклад'])) return 'payroll';
    if (any(const ['tax', 'налог', 'ндс', 'взнос'])) return 'taxes';
    if (any(const ['marketing', 'реклам', 'promotion', 'продвиж'])) {
      return 'marketing';
    }
    if (any(const [
      'server',
      'сервер',
      'hosting',
      'хостинг',
      'software',
      'софт',
      'infrastructure',
      'инфраструктур'
    ])) return 'infrastructure';
    if (any(const ['personal', 'личн', 'еда', 'food', 'rent', 'квартир'])) {
      return 'personal';
    }
    return rawCategory.isEmpty ? 'other' : rawCategory;
  }

  static List<String> _topStreamKeys(List<TransactionModel> txs) {
    final totals = <String, double>{};
    for (final tx in txs) {
      final key = _semanticStream(tx);
      totals[key] = (totals[key] ?? 0) + tx.amount.abs();
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.length <= 8) return sorted.map((e) => e.key).toList();
    return [...sorted.take(7).map((e) => e.key), 'other'];
  }

  static String _streamKey(TransactionModel tx, List<String> topKeys) {
    final key = _semanticStream(tx);
    return topKeys.contains(key) ? key : 'other';
  }

  static Map<int, double> _projectWhatIf(
    WhatIfScenario scenario,
    DateTime today,
    int days,
  ) {
    final result = <int, double>{};
    final horizon = today.add(Duration(days: days));
    for (final event in scenario.events) {
      final net =
          event.type == TransactionType.income ? event.amount : -event.amount;
      final start = DateTime(event.date.year, event.date.month, event.date.day);
      if (event.recurringPeriod == null) {
        final offset = start.difference(today).inDays;
        if (offset >= 1 && offset <= days) {
          result[offset] = (result[offset] ?? 0) + net;
        }
        continue;
      }
      var occurrence = start.isAfter(today)
          ? start
          : RecurringEngine.nextOccurrenceAfter(
              start, event.recurringPeriod!, today);
      var guard = 0;
      while (!occurrence.isAfter(horizon) && guard++ < 10000) {
        final offset = occurrence.difference(today).inDays;
        if (offset >= 1 && offset <= days) {
          result[offset] = (result[offset] ?? 0) + net;
        }
        occurrence =
            RecurringEngine.advance(occurrence, event.recurringPeriod!);
      }
    }
    return result;
  }

  static double _estimateRecurringReliability(
    TransactionModel recurring,
    List<TransactionModel> all,
    DateTime today,
  ) {
    final period = recurring.recurringPeriod;
    if (period == null) return 1;

    final lookback = switch (period) {
      RecurringPeriod.daily => 45,
      RecurringPeriod.weekly => 140,
      RecurringPeriod.monthly => 540,
      RecurringPeriod.yearly => 365 * 4,
    };
    final graceDays = switch (period) {
      RecurringPeriod.daily => 1,
      RecurringPeriod.weekly => 2,
      RecurringPeriod.monthly => 5,
      RecurringPeriod.yearly => 14,
    };
    final start = today.subtract(Duration(days: lookback));
    final anchor =
        DateTime(recurring.date.year, recurring.date.month, recurring.date.day);
    if (anchor.isAfter(today)) return 1.0;

    // Bring an old original anchor forward to the latest expected occurrence
    // not after today. If TreasuryService has already advanced the parent,
    // this loop is naturally a no-op or only a few iterations.
    var latest = anchor;
    var guard = 0;
    while (guard++ < 10000) {
      final next = RecurringEngine.advance(latest, period);
      if (next.isAfter(today)) break;
      latest = next;
    }

    DateTime previousOccurrence(DateTime date) {
      switch (period) {
        case RecurringPeriod.daily:
          return date.subtract(const Duration(days: 1));
        case RecurringPeriod.weekly:
          return date.subtract(const Duration(days: 7));
        case RecurringPeriod.monthly:
          var year = date.year;
          var month = date.month - 1;
          if (month < 1) {
            year--;
            month = 12;
          }
          final lastDay = DateTime(year, month + 1, 0).day;
          return DateTime(year, month, min(date.day, lastDay));
        case RecurringPeriod.yearly:
          final year = date.year - 1;
          final lastDay = DateTime(year, date.month + 1, 0).day;
          return DateTime(year, date.month, min(date.day, lastDay));
      }
    }

    final expectedDates = <DateTime>[];
    var occurrence = latest;
    guard = 0;
    while (!occurrence.isBefore(start) && guard++ < 10000) {
      expectedDates.add(occurrence);
      occurrence = previousOccurrence(occurrence);
    }
    expectedDates.sort();
    if (expectedDates.length < 2) return 1.0;

    final candidates = all.where((tx) {
      if (tx.isRecurring || tx.type != recurring.type) return false;
      if (tx.id.startsWith('${recurring.id}_')) {
        // Auto-materialized expenses represent obligations paid by WesiOS's
        // ledger convention. Auto income is not proof that cash arrived.
        return recurring.type == TransactionType.expense;
      }
      final sameAmount = (tx.amount - recurring.amount).abs() <=
          max(2.0, recurring.amount.abs() * 0.05);
      final sameTitle =
          tx.title.trim().toLowerCase() == recurring.title.trim().toLowerCase();
      return sameAmount && sameTitle;
    }).toList();

    var successes = 0;
    final used = <String>{};
    for (final due in expectedDates) {
      TransactionModel? match;
      var bestDistance = graceDays + 1;
      for (final tx in candidates) {
        if (used.contains(tx.id)) continue;
        final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
        final distance = day.difference(due).inDays.abs();
        if (distance <= graceDays && distance < bestDistance) {
          match = tx;
          bestDistance = distance;
        }
      }
      if (match != null) {
        used.add(match.id);
        successes++;
      }
    }

    // Beta prior: small samples stay near 75% instead of becoming fake 0/100.
    final reliability = (successes + 3.0) / (expectedDates.length + 4.0);
    if (recurring.type == TransactionType.expense) {
      return max(0.95, reliability).clamp(0.95, 1.0).toDouble();
    }
    return reliability.clamp(0.15, 1.0).toDouble();
  }

  static List<double> _netWeekdayFactor(
    List<_StreamStats> income,
    List<_StreamStats> expense,
  ) =>
      List<double>.generate(7, (wd) {
        var value = 0.0;
        for (final s in income) value += s.weekdayFactor[wd];
        for (final s in expense) value -= s.weekdayFactor[wd];
        return value;
      });

  static List<ForecastExplanation> _buildExplanations({
    required int days,
    required List<double> committedByOffset,
    required Map<int, List<HorizonCashEvent>> externalByOffset,
    required List<double> expectedUncertainNet,
    required double volatility,
    required CashRegime regime,
    required Map<int, double> whatIfByOffset,
    required double oneOffShock,
  }) {
    final result = <ForecastExplanation>[];
    final threshold = max(1.0, volatility * 0.65);
    for (var i = 0; i < days; i++) {
      final day = i + 1;
      final committed = committedByOffset[i];
      if (committed.abs() >= threshold) {
        result.add(ForecastExplanation(
          day: day,
          source: 'committed',
          titleRu: committed < 0
              ? 'Известный платёж / обязательство'
              : 'Известное поступление',
          titleEn: committed < 0 ? 'Committed payment' : 'Committed incoming',
          impact: committed,
        ));
      }
      for (final event in externalByOffset[day] ?? const []) {
        if (event.amount.abs() < threshold * 0.5) continue;
        result.add(ForecastExplanation(
          day: day,
          source: event.source,
          titleRu: event.title,
          titleEn: event.title,
          impact: event.amount * event.probability,
        ));
      }
      final whatIf = whatIfByOffset[day] ?? 0;
      if (whatIf.abs() >= threshold * 0.5) {
        result.add(ForecastExplanation(
          day: day,
          source: 'what-if',
          titleRu: 'Сценарная операция What-If',
          titleEn: 'What-If scenario event',
          impact: whatIf,
        ));
      }
      if (i > 0) {
        final change = expectedUncertainNet[i] - expectedUncertainNet[i - 1];
        if (change.abs() >= threshold) {
          result.add(ForecastExplanation(
            day: day,
            source: 'rhythm',
            titleRu: 'Изменение ритма/сезонности денежных потоков',
            titleEn: 'Cash-flow rhythm / seasonality change',
            impact: change,
          ));
        }
      }
    }
    if (oneOffShock > 0) {
      result.add(ForecastExplanation(
        day: 1,
        source: 'stress',
        titleRu: 'Стресс: внезапный крупный расход',
        titleEn: 'Stress: unexpected large expense',
        impact: -oneOffShock,
      ));
    }
    if (result.length < 2 && regime != CashRegime.stable) {
      result.add(ForecastExplanation(
        day: 7,
        source: 'regime',
        titleRu: regime == CashRegime.growth
            ? 'Текущий режим похож на рост, но его влияние затухает'
            : 'Текущий режим похож на просадку; модель допускает восстановление',
        titleEn: regime == CashRegime.growth
            ? 'Growth regime, with mean reversion'
            : 'Downturn regime, with recovery transitions',
        impact: expectedUncertainNet
            .take(min(7, expectedUncertainNet.length))
            .fold(0.0, (a, b) => a + b),
      ));
    }
    result.sort((a, b) => a.day.compareTo(b.day));
    return result.take(40).toList();
  }

  static List<ForecastActionPrompt> _buildPrompts({
    required ForecastConfidence confidence,
    required double currentBalance,
    required List<double> p10,
    required int? risk10Day,
    required int? risk25Day,
    required int? runway,
    required double safetyBuffer,
    required double committedNearTerm,
    required List<double> denseIncome,
    required List<double> denseExpense,
    required Map<String, double> recurringReliability,
  }) {
    final prompts = <ForecastActionPrompt>[];
    if (confidence == ForecastConfidence.low) {
      prompts.add(const ForecastActionPrompt(
        code: 'low-data',
        severity: ForecastPromptSeverity.warning,
        textRu:
            'Истории мало: дальний прогноз намеренно широкий. Не планируй обязательства по одной линии P50.',
        textEn:
            'Limited history: long-range uncertainty is intentionally wide. Do not plan commitments from P50 alone.',
      ));
    }
    if (risk25Day != null) {
      final worst = p10.isEmpty ? 0.0 : p10.reduce(min);
      final cut = max(0.0, -worst / max(1, risk25Day));
      prompts.add(ForecastActionPrompt(
        code: 'gap-25',
        severity: ForecastPromptSeverity.critical,
        textRu:
            'Риск кассового разрыва превышает 25% через $risk25Day дн. Снизь средние расходы примерно на ${cut.toStringAsFixed(0)} ₽/день или добавь ликвидность.',
        textEn:
            'Cash-gap risk exceeds 25% in $risk25Day days. Cut average spending by about ${cut.toStringAsFixed(0)} per day or add liquidity.',
        amount: cut,
        day: risk25Day,
      ));
    } else if (risk10Day != null) {
      prompts.add(ForecastActionPrompt(
        code: 'gap-10',
        severity: ForecastPromptSeverity.warning,
        textRu:
            'Риск кассового разрыва превышает 10% через $risk10Day дн. До этой даты лучше не брать новый крупный обязательный платёж.',
        textEn:
            'Cash-gap risk exceeds 10% in $risk10Day days. Avoid adding a large committed payment before then.',
        day: risk10Day,
      ));
    }
    if (safetyBuffer < 0) {
      prompts.add(ForecastActionPrompt(
        code: 'negative-buffer',
        severity: ForecastPromptSeverity.critical,
        textRu:
            'Свободный буфер отрицательный: текущий баланс уже меньше рекомендуемой подушки и ближайших обязательств.',
        textEn:
            'Free safety buffer is negative: current cash is below the reserve plus near-term commitments.',
        amount: -safetyBuffer,
      ));
    } else if (committedNearTerm > currentBalance * 0.7 &&
        committedNearTerm > 0) {
      prompts.add(const ForecastActionPrompt(
        code: 'commitment-load',
        severity: ForecastPromptSeverity.warning,
        textRu:
            'Ближайшие обязательные платежи забирают большую часть текущей ликвидности. Сохрани запас до их прохождения.',
        textEn:
            'Near-term committed payments consume most current liquidity. Preserve cash until they clear.',
      ));
    }

    if (denseIncome.length >= 42) {
      double nonZeroRate(List<double> values) => values.isEmpty
          ? 0
          : values.where((v) => v > 0).length / values.length;
      final recent = denseIncome.sublist(denseIncome.length - 14);
      final prior = denseIncome.sublist(
          max(0, denseIncome.length - 56), denseIncome.length - 14);
      final priorRate = nonZeroRate(prior);
      final recentRate = nonZeroRate(recent);
      if (priorRate > 0.05 && recentRate < priorRate * 0.65) {
        prompts.add(const ForecastActionPrompt(
          code: 'income-rhythm-break',
          severity: ForecastPromptSeverity.warning,
          textRu:
              'Ломается ритм входящих: за последние 14 дней дни с поступлениями стали заметно реже обычного.',
          textEn:
              'Incoming rhythm is weakening: cash-in days are materially less frequent over the last 14 days.',
        ));
      }
    }
    if (denseExpense.length >= 42) {
      double mean(List<double> values) =>
          values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
      final recent = mean(denseExpense.sublist(denseExpense.length - 14));
      final prior = mean(denseExpense.sublist(
          max(0, denseExpense.length - 56), denseExpense.length - 14));
      if (prior > 0 && recent > prior * 1.35) {
        prompts.add(const ForecastActionPrompt(
          code: 'expense-acceleration',
          severity: ForecastPromptSeverity.warning,
          textRu:
              'Расходный ритм ускорился более чем на 35% относительно предыдущего периода.',
          textEn: 'Spending pace is more than 35% above the prior period.',
        ));
      }
    }
    if (recurringReliability.values.any((r) => r < 0.65)) {
      prompts.add(const ForecastActionPrompt(
        code: 'recurring-misses',
        severity: ForecastPromptSeverity.warning,
        textRu:
            'Есть регулярные поступления/платежи, которые часто срываются. Horizon уменьшил их вес вместо проекции на 100%.',
        textEn:
            'Some recurring cash items are frequently missed. Horizon down-weights them instead of projecting 100%.',
      ));
    }
    if (runway != null && risk25Day == null) {
      prompts.add(ForecastActionPrompt(
        code: 'median-runway',
        severity: ForecastPromptSeverity.warning,
        textRu:
            'Медианный runway — около $runway дн. Проверь обязательства раньше этой даты.',
        textEn:
            'Median runway is about $runway days. Review commitments before that date.',
        day: runway,
      ));
    }
    return prompts;
  }

  static List<AccountLiquidityRisk> _accountLiquidityRisks({
    required List<AccountLiquiditySnapshot> accounts,
    required List<TransactionModel> transactions,
    required List<HorizonCashEvent> businessEvents,
    required DateTime today,
    required int days,
  }) {
    if (accounts.isEmpty) return const [];
    final result = <AccountLiquidityRisk>[];
    for (final account in accounts) {
      final history = transactions.where((t) {
        if (t.effectiveAccountId != account.accountId) return false;
        final d = DateTime(t.date.year, t.date.month, t.date.day);
        return !d.isAfter(today);
      }).toList();
      final daily = <DateTime, double>{};
      for (final tx in history) {
        final d = DateTime(tx.date.year, tx.date.month, tx.date.day);
        daily[d] = (daily[d] ?? 0) +
            (tx.type == TransactionType.income ? tx.amount : -tx.amount);
      }

      final dense = <double>[];
      if (daily.isNotEmpty) {
        final ordered = daily.keys.toList()..sort();
        final first = ordered.first;
        final span = today.difference(first).inDays + 1;
        for (var i = 0; i < span; i++) {
          dense.add(daily[first.add(Duration(days: i))] ?? 0.0);
        }
      }
      final mean =
          dense.isEmpty ? 0.0 : dense.reduce((a, b) => a + b) / dense.length;
      final vol = _StreamStats._stdDev(dense);
      int? riskDay;
      var p10AtRisk = account.balance;
      var finalP10 = account.balance;
      var cumulativeKnown = 0.0;
      for (var day = 1; day <= days; day++) {
        var known = 0.0;
        for (final tx in transactions) {
          if (tx.effectiveAccountId != account.accountId || tx.isRecurring) {
            continue;
          }
          final offset = DateTime(tx.date.year, tx.date.month, tx.date.day)
              .difference(today)
              .inDays;
          if (offset == day) {
            known += tx.type == TransactionType.income ? tx.amount : -tx.amount;
          }
        }
        for (final event in businessEvents) {
          if (event.accountId != account.accountId) continue;
          final offset =
              DateTime(event.date.year, event.date.month, event.date.day)
                  .difference(today)
                  .inDays;
          if (offset == day) known += event.amount * event.probability;
        }
        cumulativeKnown += known;
        finalP10 = account.balance +
            mean * day +
            cumulativeKnown -
            1.2816 * vol * sqrt(day.toDouble());
        if (riskDay == null && finalP10 < account.minimumBalance) {
          riskDay = day;
          p10AtRisk = finalP10;
        }
      }

      final shortfall =
          riskDay == null ? 0.0 : max(0.0, account.minimumBalance - p10AtRisk);
      var transferable = 0.0;
      int? earliestArrival;
      if (riskDay != null && account.allowNetting) {
        for (final source in accounts) {
          if (!source.allowNetting || source.accountId == account.accountId) {
            continue;
          }
          final crossCurrency =
              source.currency.toLowerCase() != account.currency.toLowerCase();
          final arrival =
              max(0, source.transferDelayDays) + (crossCurrency ? 1 : 0);
          if (arrival > riskDay) continue;
          var free = max(0.0, source.balance - source.minimumBalance);
          if (crossCurrency) {
            free *= 1 - source.fxHaircut.clamp(0.0, 0.25);
          }
          if (free <= 0) continue;
          transferable += free;
          earliestArrival =
              earliestArrival == null ? arrival : min(earliestArrival, arrival);
        }
      }
      result.add(AccountLiquidityRisk(
        accountId: account.accountId,
        name: account.name,
        currency: account.currency,
        currentBalance: account.balance,
        projectedP10: finalP10,
        riskDay: riskDay,
        canBeCoveredByNetting: riskDay != null &&
            account.allowNetting &&
            transferable >= shortfall,
        nettableLiquidity: transferable,
        earliestNettingDay: earliestArrival,
      ));
    }
    return result;
  }

  static double _percentile(List<double> sorted, double q) {
    if (sorted.isEmpty) return 0;
    if (sorted.length == 1) return sorted.first;
    final pos = q * (sorted.length - 1);
    final lo = pos.floor();
    final hi = pos.ceil();
    if (lo == hi) return sorted[lo];
    final f = pos - lo;
    return sorted[lo] + (sorted[hi] - sorted[lo]) * f;
  }

  static double _gaussian(Random rng) {
    final u1 = 1 - rng.nextDouble();
    final u2 = rng.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }
}
