from pathlib import Path


def replace_once(path: str, old: str, new: str, label: str):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if new in text:
        print('skip', label)
        return
    if old not in text:
        raise SystemExit(f'missing anchor: {label}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')
    print('patched', label)

# Backtest width calibration also considers whether a very wide interval is
# still inaccurate, exactly as the product contract requires.
replace_once(
    'lib/features/treasury/services/forecast_backtest.dart',
    'intervalScale: intervalScaleFromCoverage(coverage),',
    'intervalScale: intervalScaleFromCoverage(coverage, mape: mape),',
    'MAPE-aware interval calibration',
)

# Multi-account liquidity: location, currency haircut AND transfer latency.
p = Path('lib/features/treasury/services/forecast_engine.dart')
text = p.read_text(encoding='utf-8')
old_models = '''class AccountLiquiditySnapshot {
  final String accountId;
  final String name;
  final String currency;
  final double balance;
  final double minimumBalance;
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
}

class AccountLiquidityRisk {
  final String accountId;
  final String name;
  final String currency;
  final double currentBalance;
  final double projectedP10;
  final int? riskDay;
  final bool canBeCoveredByNetting;

  const AccountLiquidityRisk({
    required this.accountId,
    required this.name,
    required this.currency,
    required this.currentBalance,
    required this.projectedP10,
    required this.riskDay,
    required this.canBeCoveredByNetting,
  });
}
'''
new_models = '''class AccountLiquiditySnapshot {
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
'''
if new_models not in text:
    if old_models not in text:
        raise SystemExit('missing account model anchor')
    text = text.replace(old_models, new_models, 1)

start = text.index('  static List<AccountLiquidityRisk> _accountLiquidityRisks({')
end = text.index('  static double _percentile(', start)
new_risk = r'''  static List<AccountLiquidityRisk> _accountLiquidityRisks({
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

      final shortfall = riskDay == null
          ? 0.0
          : max(0.0, account.minimumBalance - p10AtRisk);
      var transferable = 0.0;
      int? earliestArrival;
      if (riskDay != null && account.allowNetting) {
        for (final source in accounts) {
          if (!source.allowNetting || source.accountId == account.accountId) {
            continue;
          }
          final crossCurrency =
              source.currency.toLowerCase() != account.currency.toLowerCase();
          final arrival = max(0, source.transferDelayDays) +
              (crossCurrency ? 1 : 0);
          if (arrival > riskDay) continue;
          var free = max(0.0, source.balance - source.minimumBalance);
          if (crossCurrency) {
            free *= 1 - source.fxHaircut.clamp(0.0, 0.25);
          }
          if (free <= 0) continue;
          transferable += free;
          earliestArrival = earliestArrival == null
              ? arrival
              : min(earliestArrival, arrival);
        }
      }
      result.add(AccountLiquidityRisk(
        accountId: account.accountId,
        name: account.name,
        currency: account.currency,
        currentBalance: account.balance,
        projectedP10: finalP10,
        riskDay: riskDay,
        canBeCoveredByNetting:
            riskDay != null && account.allowNetting && transferable >= shortfall,
        nettableLiquidity: transferable,
        earliestNettingDay: earliestArrival,
      ));
    }
    return result;
  }

'''
text = text[:start] + new_risk + text[end:]
p.write_text(text, encoding='utf-8')
print('patched account liquidity core')

# Product orchestration: structural behavior warnings + additive causal
# explanations, and remove dynamic typing from the production audit path.
p = Path('lib/features/treasury/services/treasury_service.dart')
text = p.read_text(encoding='utf-8')
if "import 'horizon_behavior_monitor.dart';" not in text:
    text = text.replace(
        "import 'horizon_business_context.dart';\n",
        "import 'horizon_behavior_monitor.dart';\nimport 'horizon_business_context.dart';\nimport 'horizon_calibration.dart';\nimport 'horizon_explainability.dart';\n",
        1,
    )
text = text.replace(
    '''    final prompts = <ForecastActionPrompt>[
      ...active.actionPrompts,
      ...context.warnings,
    ];''',
    '''    final prompts = <ForecastActionPrompt>[
      ...active.actionPrompts,
      ...context.warnings,
      ...HorizonBehaviorMonitor.analyze(transactions: all),
    ];''',
    1,
)
old_return = '''    // External engines may take seconds and are optional/Windows-only.
    _kickCompetition(all, balance);

    return withDecisions;
'''
new_return = '''    final explained = withDecisions.copyWith(
      explanations: HorizonExplainabilityService.build(
        forecast: withDecisions,
        transactions: all,
        businessEvents: context.events,
      ),
    );

    // External engines may take seconds and are optional/Windows-only.
    _kickCompetition(all, balance);

    return explained;
'''
if new_return not in text:
    if old_return not in text:
        raise SystemExit('missing Treasury return anchor')
    text = text.replace(old_return, new_return, 1)
text = text.replace(
    '''    dynamic calibration,
  ) {''',
    '''    HorizonCalibrationProfile calibration,
  ) {''',
    1,
)
p.write_text(text, encoding='utf-8')
print('patched Treasury orchestration')
