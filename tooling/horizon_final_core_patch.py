from pathlib import Path

path = Path('lib/features/treasury/services/forecast_engine.dart')
text = path.read_text(encoding='utf-8')

# 1) Explicit horizon policy instead of one undifferentiated exponential.
old = '''  double expectedForDay(int day, int weekday, HorizonTuning tuning) {
    final recentWeight = exp(-day / tuning.meanReversionDays);
    final base = dailyBaseline + (dailyRecent - dailyBaseline) * recentWeight;
    final slopeCap = max(dailyBaseline.abs() * 0.02, volatility * 0.025);
    final cappedSlope = recentSlope.clamp(-slopeCap, slopeCap);
    final drift = cappedSlope * day * exp(-day / tuning.trendDecayDays);
    final seasonalityWeight =
        day <= 14 ? 1.0 : exp(-(day - 14) / tuning.seasonalityDecayDays);
    return max(0, base + drift + weekdayFactor[weekday] * seasonalityWeight);
  }
'''
new = '''  double expectedForDay(int day, int weekday, HorizonTuning tuning) {
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
      final at60 =
          0.85 * exp(-46 / (tuning.meanReversionDays * 0.90));
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
'''
if old not in text:
    raise SystemExit('expectedForDay anchor not found')
text = text.replace(old, new, 1)

# 2) Data-adaptive regime detector and transition matrix with a conservative
# Dirichlet prior. Current-regime probabilities stay soft; historical weekly
# regime transitions learn persistence/recovery from the actual cash series.
start = text.index('class _RegimeModel {')
end = text.index('class _ShockPool {', start)
regime = r'''class _RegimeModel {
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

'''
text = text[:start] + regime + text[end:]
text = text.replace(
    'regime = _RegimeModel.transition(rng, regime);',
    'regime = regimeModel.transition(rng, regime);',
)

# 3) Semantically stable cash streams. User categories remain useful, but
# domain cash (music/services/payroll/tax/marketing/infra/personal) no longer
# fragments merely because the wording of a category changes slightly.
stream_start = text.index('  static List<String> _topStreamKeys(')
stream_end = text.index('  static Map<int, double> _projectWhatIf(', stream_start)
stream_block = r'''  static String _semanticStream(TransactionModel tx) {
    final rawCategory = (tx.category ?? '').trim().toLowerCase();
    final text = '${tx.category ?? ''} ${tx.title} ${tx.description ?? ''}'
        .toLowerCase();
    bool any(List<String> words) => words.any(text.contains);
    if (any(const [
      'beat', 'бит', 'music', 'музык', 'royalty', 'роял', 'lease', 'аренд'
    ])) return 'music';
    if (any(const [
      'service', 'услуг', 'freelance', 'фриланс', 'consult', 'сведен',
      'mix', 'master', 'таргет', 'design', 'дизайн'
    ])) return 'services';
    if (any(const ['salary', 'payroll', 'зарплат', 'оклад'])) return 'payroll';
    if (any(const ['tax', 'налог', 'ндс', 'взнос'])) return 'taxes';
    if (any(const ['marketing', 'реклам', 'promotion', 'продвиж'])) {
      return 'marketing';
    }
    if (any(const [
      'server', 'сервер', 'hosting', 'хостинг', 'software', 'софт',
      'infrastructure', 'инфраструктур'
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

'''
text = text[:stream_start] + stream_block + text[stream_end:]

# 4) Due-date reconciliation for recurring reliability. Generated child rows
# are not evidence of received income; real income must appear close to an
# expected occurrence. Expenses remain conservative obligations.
rel_start = text.index('  static double _estimateRecurringReliability(')
rel_end = text.index('  static List<double> _netWeekdayFactor(', rel_start)
rel = r'''  static double _estimateRecurringReliability(
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

    var occurrence = recurring.date;
    var guard = 0;
    while (occurrence.isBefore(start) && guard++ < 10000) {
      occurrence = RecurringEngine.advance(occurrence, period);
    }
    final expectedDates = <DateTime>[];
    while (!occurrence.isAfter(today) && guard++ < 10000) {
      if (!occurrence.isBefore(start)) {
        expectedDates.add(DateTime(occurrence.year, occurrence.month, occurrence.day));
      }
      occurrence = RecurringEngine.advance(occurrence, period);
    }
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
      final sameTitle = tx.title.trim().toLowerCase() ==
          recurring.title.trim().toLowerCase();
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

'''
text = text[:rel_start] + rel + text[rel_end:]

# Let orchestration enrich explanations without rebuilding ForecastResult.
text = text.replace(
    '    List<ForecastActionPrompt>? actionPrompts,\n  }) =>',
    '    List<ForecastActionPrompt>? actionPrompts,\n    List<ForecastExplanation>? explanations,\n  }) =>',
    1,
)
text = text.replace(
    '        explanations: explanations,\n        actionPrompts: actionPrompts ?? this.actionPrompts,',
    '        explanations: explanations ?? this.explanations,\n        actionPrompts: actionPrompts ?? this.actionPrompts,',
    1,
)

path.write_text(text, encoding='utf-8')
print('patched forecast_engine.dart')
