from pathlib import Path
import re

ROOT = Path('.')


def replace_once(path, old, new, label):
    p = ROOT / path
    text = p.read_text(encoding='utf-8')
    if new in text:
        print(f'[skip] {label}')
        return
    if old not in text:
        raise SystemExit(f'anchor not found: {label} in {path}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')
    print(f'[ok] {label}')


def replace_regex(path, pattern, repl, label):
    p = ROOT / path
    text = p.read_text(encoding='utf-8')
    updated, count = re.subn(pattern, repl, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f'regex anchor not found: {label} in {path}')
    p.write_text(updated, encoding='utf-8')
    print(f'[ok] {label}')

# ---------------------------------------------------------------------------
# ForecastEngine: preserve old hard honesty threshold unless known future cash
# exists. Pure known recurring remains deterministic; weak one-off history does
# not suddenly become a fake forecast.
# ---------------------------------------------------------------------------
replace_once(
    'lib/features/treasury/services/forecast_engine.dart',
    """    if (history.isEmpty && recurringTxs.isEmpty && businessEvents.isEmpty && scheduledOneOff.isEmpty) {
      return ForecastResult.empty();
    }

    DateTime minDay = todayOnly;
    for (final tx in history) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (day.isBefore(minDay)) minDay = day;
    }
    final spanDays = todayOnly.difference(minDay).inDays + 1;
    final confidence = _confidence(spanDays, history.length);
""",
    """    DateTime minDay = todayOnly;
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
""",
    'honest low-data gate',
)

# Account liquidity snapshots carry the haircut into the pure risk engine.
replace_once(
    'lib/features/treasury/services/forecast_engine.dart',
    """  final double minimumBalance;
  final bool allowNetting;

  const AccountLiquiditySnapshot({
    required this.accountId,
    required this.name,
    required this.balance,
    this.currency = 'RUB',
    this.minimumBalance = 0,
    this.allowNetting = true,
  });
""",
    """  final double minimumBalance;
  final bool allowNetting;
  final double fxHaircut;

  const AccountLiquiditySnapshot({
    required this.accountId,
    required this.name,
    required this.balance,
    this.currency = 'RUB',
    this.minimumBalance = 0,
    this.allowNetting = true,
    this.fxHaircut = 0.03,
  });
""",
    'liquidity snapshot haircut',
)

# Recurring: keep an effective reliability map, apply finite What-If multipliers
# to known repeating cash, and preserve deterministic semantics until there is
# enough real observation history to learn misses.
replace_once(
    'lib/features/treasury/services/forecast_engine.dart',
    """    final recurringOccurrences = <int, List<({double net, double probability, String title, String? accountId})>>{};

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
      for (final entry in projected.entries) {
        final raw = entry.value;
        final probability = tx.type == TransactionType.expense
            ? max(0.95, reliability)
            : reliability;
        final shiftedOffset = tx.type == TransactionType.income
            ? entry.key + whatIf.incomeDelayDays
            : entry.key;
        if (shiftedOffset < 1 || shiftedOffset > days) continue;
        (recurringOccurrences[shiftedOffset] ??= []).add((
          net: raw,
          probability: probability,
          title: tx.title,
          accountId: tx.accountId,
        ));
        if (probability >= 0.9 || tx.type == TransactionType.expense) {
          committedByOffset[shiftedOffset - 1] += raw * probability;
          knownMagnitudeByOffset[shiftedOffset - 1] += raw.abs() * probability;
        }
      }
    }
""",
    """    final recurringOccurrences = <int, List<({double net, double probability, String title, String? accountId})>>{};
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
""",
    'effective recurring reliability + scenario scaling',
)

replace_once(
    'lib/features/treasury/services/forecast_engine.dart',
    """      final shiftedOffset = event.amount > 0 ? offset + whatIf.incomeDelayDays : offset;
      if (shiftedOffset <= days) (externalByOffset[shiftedOffset] ??= []).add(event);
""",
    """      final shiftedOffset = event.amount > 0 ? offset + whatIf.incomeDelayDays : offset;
      if (shiftedOffset >= 1 && shiftedOffset <= days) {
        (externalByOffset[shiftedOffset] ??= []).add(event);
        committedByOffset[shiftedOffset - 1] += event.amount;
        knownMagnitudeByOffset[shiftedOffset - 1] += event.amount.abs();
      }
""",
    'scheduled one-off is committed cash',
)

# Identify and suppress only the largest uncertain income stream in the
# main-source-loss stress, instead of destroying every revenue source.
replace_once(
    'lib/features/treasury/services/forecast_engine.dart',
    """    for (final s in expenseStreams) {
      expenseBaseline += s.dailyBaseline;
      expenseRecent += s.dailyRecent;
      maxDriftCap += s.driftCap;
      streamContribution[s.key] = (streamContribution[s.key] ?? 0) - s.dailyBaseline;
    }

    for (var path = 0; path < effectivePaths; path++) {
""",
    """    for (final s in expenseStreams) {
      expenseBaseline += s.dailyBaseline;
      expenseRecent += s.dailyRecent;
      maxDriftCap += s.driftCap;
      streamContribution[s.key] = (streamContribution[s.key] ?? 0) - s.dailyBaseline;
    }
    final primaryIncomeKey = incomeStreams.isEmpty
        ? null
        : incomeStreams
            .reduce((a, b) => a.dailyBaseline >= b.dailyBaseline ? a : b)
            .key;

    for (var path = 0; path < effectivePaths; path++) {
""",
    'primary income stream detection',
)

replace_once(
    'lib/features/treasury/services/forecast_engine.dart',
    """          for (final s in incomeStreams) {
            expectedIncome += s.expectedForDay(day, weekday, activeTuning);
          }
""",
    """          for (final s in incomeStreams) {
            var component = s.expectedForDay(day, weekday, activeTuning);
            if (whatIf.mainIncomeLossDays >= day && s.key == primaryIncomeKey) {
              component *= 0.15;
            }
            expectedIncome += component;
          }
""",
    'main-source stress only hits largest stream',
)

replace_once(
    'lib/features/treasury/services/forecast_engine.dart',
    """        if (whatIf.mainIncomeLossDays >= day) expectedIncome *= 0.15;
        if (whatIf.incomeMultiplierDays <= 0 ||
""",
    """        if (whatIf.incomeMultiplierDays <= 0 ||
""",
    'remove global income destruction',
)

# Low-data stochastic widening applies to uncertain observed history, not to a
# schedule made exclusively of known recurring payments.
replace_once(
    'lib/features/treasury/services/forecast_engine.dart',
    """        } else {
          final observedVol = max(
            _StreamStats._stdDev(denseIncome),
            _StreamStats._stdDev(denseExpense),
          );
          // Little history must NEVER collapse to a fake deterministic line.
""",
    """        } else if (nonRecurring.isNotEmpty) {
          final observedVol = max(
            _StreamStats._stdDev(denseIncome),
            _StreamStats._stdDev(denseExpense),
          );
          // Little uncertain history must NEVER collapse to a fake deterministic line.
""",
    'pure recurring keeps exact trajectory',
)

# Reserve is stochastic reserve only. Near-term committed outflows are shown
# separately, so free cash subtracts each exactly once.
replace_once(
    'lib/features/treasury/services/forecast_engine.dart',
    """    final recommendedReserve = _percentile(requiredReserveSamples, 0.90);
    var committedOutflow30 = 0.0;
""",
    """    final rawDrawdownReserve = _percentile(requiredReserveSamples, 0.90);
    var committedOutflow30 = 0.0;
""",
    'reserve raw drawdown naming',
)
replace_once(
    'lib/features/treasury/services/forecast_engine.dart',
    """    final committedNearTerm = committedOutflow30;
    final safetyBuffer = currentBalance - recommendedReserve - committedNearTerm;
""",
    """    final committedNearTerm = committedOutflow30;
    final recommendedReserve =
        (rawDrawdownReserve - committedNearTerm).clamp(0.0, double.infinity).toDouble();
    final safetyBuffer = currentBalance - recommendedReserve - committedNearTerm;
""",
    'reserve excludes committed obligations',
)
replace_once(
    'lib/features/treasury/services/forecast_engine.dart',
    """      recommendedReserve: max(recommendedReserve, committedNearTerm),
""",
    """      recommendedReserve: recommendedReserve,
""",
    'do not fold commitments into reserve',
)

replace_once(
    'lib/features/treasury/services/forecast_engine.dart',
    """      recurringReliability: recurringReliability,
    );

    final accountRisks = _accountLiquidityRisks(
      accounts: accounts,
      transactions: history,
""",
    """      recurringReliability: effectiveRecurringReliability,
    );

    final accountRisks = _accountLiquidityRisks(
      accounts: accounts,
      transactions: transactions,
""",
    'effective reliability prompts + full account schedule',
)

replace_regex(
    'lib/features/treasury/services/forecast_engine.dart',
    r"  static double _estimateRecurringReliability\(\n    TransactionModel recurring,\n    List<TransactionModel> all,\n    DateTime today,\n  \) \{.*?\n  \}\n\n  static List<double> _netWeekdayFactor",
    """  static double _estimateRecurringReliability(
    TransactionModel recurring,
    List<TransactionModel> all,
    DateTime today,
  ) {
    final period = recurring.recurringPeriod;
    if (period == null) return 1;

    var earliest = today;
    for (final tx in all) {
      final d = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (!d.isAfter(today) && d.isBefore(earliest)) earliest = d;
    }
    final observedSpan = today.difference(earliest).inDays + 1;
    final minimumObservation = switch (period) {
      RecurringPeriod.daily => 7,
      RecurringPeriod.weekly => 21,
      RecurringPeriod.monthly => 90,
      RecurringPeriod.yearly => 365,
    };
    if (observedSpan < minimumObservation) return 1.0;

    final children = all.where((tx) {
      if (tx.id.startsWith('${recurring.id}_')) {
        // Auto-materialized income proves only that WesiOS generated a row,
        // not that money actually arrived. Expenses remain committed cash.
        return recurring.type == TransactionType.expense;
      }
      if (tx.isRecurring) return false;
      return tx.title == recurring.title &&
          tx.type == recurring.type &&
          (tx.amount - recurring.amount).abs() <=
              max(1, recurring.amount * 0.01);
    }).toList();

    final lookback = switch (period) {
      RecurringPeriod.daily => 30,
      RecurringPeriod.weekly => 84,
      RecurringPeriod.monthly => 365,
      RecurringPeriod.yearly => 365 * 3,
    };
    final observedWindow = min(lookback, observedSpan);
    final recentChildren = children
        .where((e) =>
            e.date.isAfter(today.subtract(Duration(days: observedWindow))))
        .length;
    final expected = switch (period) {
      RecurringPeriod.daily => observedWindow,
      RecurringPeriod.weekly => max(1, (observedWindow / 7).floor()),
      RecurringPeriod.monthly => max(1, (observedWindow / 30.44).floor()),
      RecurringPeriod.yearly => max(1, (observedWindow / 365).floor()),
    };
    return ((recentChildren + 3.0) / (expected + 4.0))
        .clamp(0.15, 1.0)
        .toDouble();
  }

  static List<double> _netWeekdayFactor""",
    'recurring reliability uses real evidence',
)

# Account-local risk includes exact future Treasury operations and nets only
# OTHER locations, with FX haircut.
replace_regex(
    'lib/features/treasury/services/forecast_engine.dart',
    r"  static List<AccountLiquidityRisk> _accountLiquidityRisks\(\{.*?\n  \}\n\n  static double _percentile",
    """  static List<AccountLiquidityRisk> _accountLiquidityRisks({
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
      final mean = dense.isEmpty
          ? 0.0
          : dense.reduce((a, b) => a + b) / dense.length;
      final vol = _StreamStats._stdDev(dense);
      int? riskDay;
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
          final offset = DateTime(event.date.year, event.date.month, event.date.day)
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
        }
      }
      final shortfall = max(0.0, account.minimumBalance - finalP10);
      var transferable = 0.0;
      for (final source in accounts) {
        if (!source.allowNetting || source.accountId == account.accountId) {
          continue;
        }
        var free = max(0.0, source.balance - source.minimumBalance);
        if (source.currency.toLowerCase() != account.currency.toLowerCase()) {
          free *= 1 - source.fxHaircut.clamp(0.0, 0.25);
        }
        transferable += free;
      }
      result.add(AccountLiquidityRisk(
        accountId: account.accountId,
        name: account.name,
        currency: account.currency,
        currentBalance: account.balance,
        projectedP10: finalP10,
        riskDay: riskDay,
        canBeCoveredByNetting:
            account.allowNetting && transferable >= shortfall,
      ));
    }
    return result;
  }

  static double _percentile""",
    'location-aware liquidity risk',
)

# Sidecar metadata -> pure snapshot.
replace_once(
    'lib/features/treasury/services/account_liquidity_service.dart',
    """          allowNetting: (meta[summary.account.id] ??
                  AccountLiquidityMeta(accountId: summary.account.id))
              .allowNetting,
        ),
""",
    """          allowNetting: (meta[summary.account.id] ??
                  AccountLiquidityMeta(accountId: summary.account.id))
              .allowNetting,
          fxHaircut: (meta[summary.account.id] ??
                  AccountLiquidityMeta(accountId: summary.account.id))
              .fxHaircut,
        ),
""",
    'snapshot forwards FX haircut',
)

# Existing leases should immediately contribute conservative contract memory,
# even before the user fine-tunes renewal/royalty assumptions.
replace_once(
    'lib/features/treasury/services/horizon_business_context.dart',
    """        final contract = memory[lease.id];
        if (contract == null) continue;

        final renewalDate = _day(lease.endsAt);
        final renewalAmount = contract.renewalAmountRub > 0
""",
    """        final leaseAmountRub = lease.amount *
            CurrencyService.rateToRub(lease.currency.toLowerCase());
        final contract = memory[lease.id] ??
            HorizonContractMemory(
              beatId: beat.id,
              leaseId: lease.id,
              renewalProbability: 0.35,
              renewalAmountRub: leaseAmountRub,
              royaltyProbability: 0.50,
              updatedAt: today,
            );

        final renewalDate = _day(lease.endsAt);
        final renewalAmount = contract.renewalAmountRub > 0
""",
    'contract fallback for existing leases',
)

# Treasury orchestration: balance includes account opening balances; heavy
# monthly learning/engine championship never blocks the first live decision.
replace_once(
    'lib/features/treasury/services/treasury_service.dart',
    """import 'anomaly_engine.dart';
import 'forecast_engine.dart';
""",
    """import 'account_service.dart';
import 'anomaly_engine.dart';
import 'forecast_engine.dart';
""",
    'account service import',
)
replace_once(
    'lib/features/treasury/services/treasury_service.dart',
    """  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<Box<TransactionModel>> get _treasuryBox async {
""",
    """  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static bool _learningInFlight = false;
  static bool _competitionInFlight = false;

  Future<Box<TransactionModel>> get _treasuryBox async {
""",
    'single-flight flags',
)
replace_once(
    'lib/features/treasury/services/treasury_service.dart',
    """  Future<double> getCurrentBalance() async {
    final all = await getAllTransactions();
    double balance = 0;
    for (final tx in all) {
      balance += tx.type == TransactionType.income ? tx.amount : -tx.amount;
    }
    return balance;
  }
""",
    """  Future<double> getCurrentBalance() async {
    final all = await getAllTransactions();
    try {
      final summaries = await AccountService.summaries(all);
      return summaries.fold<double>(0, (sum, item) => sum + item.balance);
    } catch (_) {
      double balance = 0;
      for (final tx in all) {
        balance += tx.type == TransactionType.income ? tx.amount : -tx.amount;
      }
      return balance;
    }
  }
""",
    'company balance includes opening balances',
)
replace_once(
    'lib/features/treasury/services/treasury_service.dart',
    """    // Monthly bounded learning is allowed to update only interpretable
    // parameters + calibration. If it fails, the previous/identity profile is
    // retained and forecasting stays available.
    final learned = await HorizonLearningService.updateIfDue(
      transactions: all,
      currentBalance: balance,
    );
    final calibration = learned?.profile ?? await HorizonLearningService.load();
""",
    """    // Rendering uses the last verified profile immediately. Monthly
    // calibration is kicked after that and never blocks this forecast call.
    final calibration = await HorizonLearningService.load();
    _kickLearning(all, balance);
""",
    'learning no longer blocks forecast',
)
replace_once(
    'lib/features/treasury/services/treasury_service.dart',
    """    // External engines may take seconds and are optional/Windows-only. Their
    // monthly championship is deliberately background work; current Horizon
    // must not wait for Python just to render a risk decision.
    unawaited(HorizonEngineCompetitionService.evaluateIfDue(
      transactions: all,
      currentBalance: balance,
    ));

    return withDecisions;
  }

  // ========== DEMO DATA (never auto-called by forecast screen) ==========
""",
    """    // External engines may take seconds and are optional/Windows-only.
    _kickCompetition(all, balance);

    return withDecisions;
  }

  static void _kickLearning(
    List<TransactionModel> transactions,
    double currentBalance,
  ) {
    if (_learningInFlight) return;
    _learningInFlight = true;
    unawaited(HorizonLearningService.updateIfDue(
      transactions: transactions,
      currentBalance: currentBalance,
    ).whenComplete(() => _learningInFlight = false));
  }

  static void _kickCompetition(
    List<TransactionModel> transactions,
    double currentBalance,
  ) {
    if (_competitionInFlight) return;
    _competitionInFlight = true;
    unawaited(HorizonEngineCompetitionService.evaluateIfDue(
      transactions: transactions,
      currentBalance: currentBalance,
    ).whenComplete(() => _competitionInFlight = false));
  }

  // ========== DEMO DATA (never auto-called by forecast screen) ==========
""",
    'single-flight background learning and championship',
)

# New tests must test the new promise, not contradict the established hard
# insufficient-data contract.
replace_once(
    'test/horizon_top_tier_test.dart',
    """      expect(result.confidence, isNot(ForecastConfidence.insufficient));
      expect(result.recentNetPerDay, greaterThan(result.longRunBaselinePerDay));
      expect(result.driftCapPerDay, greaterThanOrEqualTo(0));
""",
    """      expect(result.confidence, isNot(ForecastConfidence.insufficient));
      expect(result.driftCapPerDay, greaterThanOrEqualTo(0));
      expect(result.p50.last, lessThan(100000 + 6500 * 365 * 0.35));
""",
    'anti-millionaire test checks outcome, not shock classification',
)
replace_once(
    'test/horizon_top_tier_test.dart',
    """        transactions: [
          tx(
            id: 'only-known-move',
            date: now.subtract(const Duration(days: 2)),
            amount: 10000,
            type: TransactionType.income,
          ),
        ],
""",
    """        transactions: [
          tx(
            id: 'weak-history-a',
            date: now.subtract(const Duration(days: 7)),
            amount: 10000,
            type: TransactionType.income,
          ),
          tx(
            id: 'weak-history-b',
            date: now.subtract(const Duration(days: 3)),
            amount: 2500,
            type: TransactionType.expense,
          ),
          tx(
            id: 'weak-history-c',
            date: now.subtract(const Duration(days: 1)),
            amount: 1800,
            type: TransactionType.income,
          ),
        ],
""",
    'low-data test uses weak but forecastable history',
)

print('Horizon correctness patch complete')
