from pathlib import Path

path = Path('lib/features/treasury/services/forecast_engine.dart')
text = path.read_text(encoding='utf-8')


def replace(old: str, new: str, label: str, marker: str | None = None):
    global text
    if marker is not None and marker in text:
        print('skip', label)
        return
    if old not in text:
        raise SystemExit('missing anchor: ' + label)
    text = text.replace(old, new, 1)
    print('patched', label)

# Scenario percentage shocks apply to uncertain business cash as well. Known
# committed invoices/obligations stay known; stress is not allowed to erase a
# signed commitment merely because generic income is down 30%.
replace(
    '''      var modeledAmount = event.amount;\n      if (modeledAmount > 0 &&\n          shiftedOffset <= mainLossWindow &&''',
    '''      var modeledAmount = event.amount;\n      if (!event.committed &&\n          modeledAmount > 0 &&\n          (whatIf.incomeMultiplierDays <= 0 ||\n              shiftedOffset <= whatIf.incomeMultiplierDays)) {\n        modeledAmount *= whatIf.incomeMultiplier;\n      } else if (!event.committed &&\n          modeledAmount < 0 &&\n          (whatIf.expenseMultiplierDays <= 0 ||\n              shiftedOffset <= whatIf.expenseMultiplierDays)) {\n        modeledAmount *= whatIf.expenseMultiplier;\n      }\n      if (modeledAmount > 0 &&\n          shiftedOffset <= mainLossWindow &&''',
    'apply percentage stress to uncertain business events',
    marker='!event.committed &&\n          modeledAmount > 0 &&',
)

replace(
    '''    final accountRisks = _accountLiquidityRisks(\n      accounts: accounts,\n      transactions: transactions,\n      businessEvents: businessEvents,\n      today: todayOnly,\n      days: days,\n    );''',
    '''    final accountRisks = _accountLiquidityRisks(\n      accounts: accounts,\n      transactions: transactions,\n      businessEvents: businessEvents,\n      recurringReliability: effectiveRecurringReliability,\n      whatIf: whatIf,\n      primaryLossSource: primaryLossSource,\n      today: todayOnly,\n      days: days,\n    );''',
    'pass modeled scenario context to account liquidity',
    marker='recurringReliability: effectiveRecurringReliability,\n      whatIf: whatIf,\n      primaryLossSource: primaryLossSource',
)

start = text.index('  static List<AccountLiquidityRisk> _accountLiquidityRisks({')
end = text.index('  static double _percentile(', start)
new_function = r'''  static List<AccountLiquidityRisk> _accountLiquidityRisks({
    required List<AccountLiquiditySnapshot> accounts,
    required List<TransactionModel> transactions,
    required List<HorizonCashEvent> businessEvents,
    required Map<String, double> recurringReliability,
    required WhatIfScenario whatIf,
    required String? primaryLossSource,
    required DateTime today,
    required int days,
  }) {
    if (accounts.isEmpty) return const [];

    final recurringIncomeIds = transactions
        .where((tx) => tx.isRecurring && tx.type == TransactionType.income)
        .map((tx) => tx.id)
        .toList();
    bool legacyAutoIncome(TransactionModel tx) =>
        !tx.isRecurring &&
        recurringIncomeIds.any((id) => tx.id.startsWith('${id}_'));

    final result = <AccountLiquidityRisk>[];
    for (final account in accounts) {
      // Historical drift/volatility is actual cash only. Recurring parents are
      // schedule definitions; legacy generated income is not execution proof.
      final history = transactions.where((t) {
        if (t.effectiveAccountId != account.accountId || t.isRecurring) {
          return false;
        }
        if (legacyAutoIncome(t)) return false;
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

      // Project account-bound recurring cash with the same execution
      // reliability, delay, multiplier and main-source stress semantics as the
      // company forecast.
      final recurringByDay = <int, double>{};
      for (final tx in transactions) {
        if (!tx.isRecurring ||
            tx.recurringPeriod == null ||
            tx.effectiveAccountId != account.accountId) continue;
        final projected = RecurringEngine.projectFutureContributions(
          [tx],
          days: days,
          from: today,
        );
        final reliability = (recurringReliability[tx.id] ??
                (tx.type == TransactionType.expense ? 1.0 : 0.5))
            .clamp(0.05, 1.0)
            .toDouble();
        final probability = tx.type == TransactionType.expense
            ? max(0.95, reliability)
            : reliability;
        for (final entry in projected.entries) {
          final shifted = tx.type == TransactionType.income
              ? entry.key + whatIf.incomeDelayDays
              : entry.key;
          if (shifted < 1 || shifted > days) continue;
          var modeled = entry.value;
          if (modeled > 0 &&
              shifted <= whatIf.mainIncomeLossDays &&
              primaryLossSource == 'recurring:${tx.id}') {
            modeled *= 0.15;
          }
          if (modeled > 0 &&
              (whatIf.incomeMultiplierDays <= 0 ||
                  shifted <= whatIf.incomeMultiplierDays)) {
            modeled *= whatIf.incomeMultiplier;
          } else if (modeled < 0 &&
              (whatIf.expenseMultiplierDays <= 0 ||
                  shifted <= whatIf.expenseMultiplierDays)) {
            modeled *= whatIf.expenseMultiplier;
          }
          recurringByDay[shifted] =
              (recurringByDay[shifted] ?? 0) + modeled * probability;
        }
      }

      int? riskDay;
      var p10AtRisk = account.balance;
      var finalP10 = account.balance;
      var cumulativeKnown = 0.0;
      for (var day = 1; day <= days; day++) {
        var known = recurringByDay[day] ?? 0.0;

        // Future one-off ledger entries are known at their scheduled date.
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

        // Company events with an explicit account location follow the same
        // scenario transformation as the global event layer.
        for (final event in businessEvents) {
          if (event.accountId != account.accountId) continue;
          final originalOffset =
              DateTime(event.date.year, event.date.month, event.date.day)
                  .difference(today)
                  .inDays;
          if (originalOffset < 1) continue;
          final shifted = event.amount > 0
              ? originalOffset + whatIf.incomeDelayDays
              : originalOffset;
          if (shifted != day) continue;
          var amount = event.amount;
          if (!event.committed &&
              amount > 0 &&
              (whatIf.incomeMultiplierDays <= 0 ||
                  shifted <= whatIf.incomeMultiplierDays)) {
            amount *= whatIf.incomeMultiplier;
          } else if (!event.committed &&
              amount < 0 &&
              (whatIf.expenseMultiplierDays <= 0 ||
                  shifted <= whatIf.expenseMultiplierDays)) {
            amount *= whatIf.expenseMultiplier;
          }
          if (amount > 0 &&
              shifted <= whatIf.mainIncomeLossDays &&
              primaryLossSource == 'business:${event.effectiveRiskSource}') {
            amount *= 0.15;
          }
          known += amount * event.probability;
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
text = text[:start] + new_function + text[end:]
path.write_text(text, encoding='utf-8')
print('patched account liquidity recurring/scenario semantics')
