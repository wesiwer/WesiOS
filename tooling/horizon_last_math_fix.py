from pathlib import Path

p = Path('lib/features/treasury/services/forecast_engine.dart')
text = p.read_text(encoding='utf-8')

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
        // then applying max(0) creates a Jensen/truncation bias: the negative
        // tail is chopped off while the positive tail survives, so merely
        // admitting more uncertainty makes distant P50 richer. That is the
        // exact opposite of an honest long-range forecast.
        //
        // First draw physically valid non-negative income/expense at their
        // empirical scale; then scale only the centered net deviation. This
        // keeps P50 anchored to mean-reverting cash economics while P10/P90
        // still widen with horizon.
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
print('final Horizon math invariants patched')
