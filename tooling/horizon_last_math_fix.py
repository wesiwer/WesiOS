from pathlib import Path

p = Path('lib/features/treasury/services/forecast_engine.dart')
text = p.read_text(encoding='utf-8')

# A shock episode may occupy most of the last 21 days. Those days are removed
# from the ordinary stream stats by design, but the one or two remaining empty
# days must not become "proof" that normal income disappeared. If shock
# filtering leaves too little recent evidence, fall back to the robust long-run
# frequency/amount and let the regime layer carry the short-term growth signal.
old = '''    var weightedAmount = 0.0;
    var amountWeight = 0.0;
    for (var i = dense.length - 1; i >= recentStart; i--) {
      if (!excludedDays.contains(i)) {
        totalOccurrenceWeight += recentWeight;
        if (dense[i] > 0) {
          weightedOccurrence += recentWeight;
          weightedAmount += dense[i] * recentWeight;
          amountWeight += recentWeight;
        }
      }
      recentWeight *= 0.88;
    }
    final recentFrequency = totalOccurrenceWeight == 0
        ? baselineFrequency
        : weightedOccurrence / totalOccurrenceWeight;
    final recentAmount =
        amountWeight == 0 ? baselineAmount : weightedAmount / amountWeight;
'''
new = '''    var weightedAmount = 0.0;
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
'''
if old not in text:
    raise SystemExit('recent evidence anchor not found')
text = text.replace(old, new, 1)

old = '''        var uncertainty = 1 + 0.32 * sqrt(day / 30.0);
        if (confidence == ForecastConfidence.low) {
          uncertainty *= activeTuning.lowDataUncertainty;
        } else if (confidence == ForecastConfidence.medium) {
          uncertainty *= 1.18;
        }
        residualIncome *= uncertainty;
        residualExpense *= uncertainty;

        var uncertainIncome = max(0, expectedIncome + residualIncome);
        var uncertainExpense = max(0, expectedExpense + residualExpense);

        if (shocks.income.isNotEmpty &&
            rng.nextDouble() < shocks.incomeProbability) {
          uncertainIncome += shocks.income[rng.nextInt(shocks.income.length)];
        }
        if (shocks.expense.isNotEmpty &&
            rng.nextDouble() < shocks.expenseProbability) {
          uncertainExpense +=
              shocks.expense[rng.nextInt(shocks.expense.length)];
        }

        if (whatIf.incomeDelayDays > 0 && day <= whatIf.incomeDelayDays) {
          uncertainIncome = 0;
        }
'''
new = '''        var uncertainty = 1 + 0.32 * sqrt(day / 30.0);
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
'''
if old not in text:
    raise SystemExit('uncertainty anchor not found')
text = text.replace(old, new, 1)

old = '''        final uncertainNet = uncertainIncome - uncertainExpense;
        balance += uncertainNet + knownNet + scenarioNet;
'''
new = '''        balance += uncertainNet + knownNet + scenarioNet;
'''
if old not in text:
    raise SystemExit('uncertainNet anchor not found')
text = text.replace(old, new, 1)

old = '      recommendedReserve: max(recommendedReserve, committedNearTerm),\n'
new = '      recommendedReserve: recommendedReserve,\n'
if old not in text:
    raise SystemExit('reserve return anchor not found')
text = text.replace(old, new, 1)

# Main-source stress must hit only the largest income stream. Remove an older
# global multiplier if it is still present from the first regime prototype.
text = text.replace(
    '        if (whatIf.mainIncomeLossDays >= day) expectedIncome *= 0.15;\n',
    '',
    1,
)

p.write_text(text, encoding='utf-8')

# The anti-millionaire test must compare against the ACTUAL observed lucky
# month, not `recentNetPerDay`: after shock filtering that diagnostic correctly
# represents ordinary cash, so using it as the lucky pace would punish the
# model for becoming more robust.
t = Path('test/horizon_top_tier_test.dart')
test_text = t.read_text(encoding='utf-8')
old_test = '''      // Explicit guard against absurd compounding/extrapolation from the lucky
      // month: a year cannot simply repeat the current recent daily pace.
      final naiveLuckyYear = 100000 + result.recentNetPerDay * 365;
      if (naiveLuckyYear > 100000) {
        expect(result.p50.last, lessThan(naiveLuckyYear * 0.80));
      }
'''
new_test = '''      // Explicit guard against absurd compounding/extrapolation from the lucky
      // month. Use the actually observed last-30-day net pace: `recentNetPerDay`
      // deliberately excludes shock days and now represents ordinary cash.
      final recentCutoff = now.subtract(const Duration(days: 30));
      final observedRecentNet = history
          .where((tx) => tx.date.isAfter(recentCutoff))
          .fold<double>(
            0,
            (sum, tx) =>
                sum + (tx.type == TransactionType.income ? tx.amount : -tx.amount),
          );
      final naiveLuckyYear = 100000 + (observedRecentNet / 30) * 365;
      expect(result.p50.last, lessThan(naiveLuckyYear * 0.80));
'''
if old_test not in test_text:
    raise SystemExit('anti-millionaire test anchor not found')
t.write_text(test_text.replace(old_test, new_test, 1), encoding='utf-8')

print('final Horizon math invariants and semantic guard patched')
