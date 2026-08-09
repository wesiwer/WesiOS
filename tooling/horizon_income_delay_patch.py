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

# Main-source selection must see the same delayed arrival window as the actual
# stress simulation. A source whose cash is shifted beyond the loss window
# cannot be selected as the source supposedly lost inside that window.
replace(
    '''        final expected = projected.values
            .where((value) => value > 0)
            .fold<double>(0, (sum, value) => sum + value * reliability);
        if (expected > 0) {
          mainIncomeExposure['recurring:${tx.id}'] = expected;
        }''',
    '''        var expected = 0.0;
        for (final entry in projected.entries) {
          final shifted = entry.key + whatIf.incomeDelayDays;
          if (shifted < 1 || shifted > mainLossWindow || entry.value <= 0) {
            continue;
          }
          expected += entry.value * reliability;
        }
        if (expected > 0) {
          mainIncomeExposure['recurring:${tx.id}'] = expected;
        }''',
    'delay-aware recurring main-source exposure',
    marker='final shifted = entry.key + whatIf.incomeDelayDays;\n          if (shifted < 1 || shifted > mainLossWindow',
)
replace(
    '''        final offset = DateTime(event.date.year, event.date.month, event.date.day)
            .difference(todayOnly)
            .inDays;
        if (offset < 1 || offset > mainLossWindow) continue;
        final key = 'business:${event.effectiveRiskSource}';''',
    '''        final offset = DateTime(event.date.year, event.date.month, event.date.day)
            .difference(todayOnly)
            .inDays;
        final shifted = offset + whatIf.incomeDelayDays;
        if (shifted < 1 || shifted > mainLossWindow) continue;
        final key = 'business:${event.effectiveRiskSource}';''',
    'delay-aware business main-source exposure',
    marker='final shifted = offset + whatIf.incomeDelayDays;\n        if (shifted < 1 || shifted > mainLossWindow)',
)

# Per-path queues preserve the actual timing of delayed uncertain income and
# rare positive shocks instead of deleting the first N days and replacing them
# with unrelated later income.
replace(
    '''    for (var path = 0; path < effectivePaths; path++) {
      var balance = currentBalance;
      var regime = _RegimeModel.sampleInitial(rng, regimeModel.probabilities);''',
    '''    for (var path = 0; path < effectivePaths; path++) {
      var balance = currentBalance;
      final delay = max(0, whatIf.incomeDelayDays);
      final delayedSampledIncome =
          delay == 0 ? null : List<double>.filled(days + delay + 1, 0);
      final delayedExpectedIncome =
          delay == 0 ? null : List<double>.filled(days + delay + 1, 0);
      final delayedIncomeShock =
          delay == 0 ? null : List<double>.filled(days + delay + 1, 0);
      var regime = _RegimeModel.sampleInitial(rng, regimeModel.probabilities);''',
    'per-path delayed income queues',
    marker='final delayedSampledIncome =',
)

old_sample = '''        var sampledIncome = max(0.0, expectedIncome + residualIncome);
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
        }'''
new_sample = '''        var sampledIncome = max(0.0, expectedIncome + residualIncome);
        final sampledExpense = max(0.0, expectedExpense + residualExpense);

        if (delay > 0) {
          final arrivalIndex = i + delay;
          if (arrivalIndex < delayedSampledIncome!.length) {
            delayedSampledIncome[arrivalIndex] += sampledIncome;
            delayedExpectedIncome![arrivalIndex] += expectedIncome;
          }
          sampledIncome = delayedSampledIncome[i];
          expectedIncome = delayedExpectedIncome![i];
        }

        final expectedNetCenter = expectedIncome - expectedExpense;
        final sampledNet = sampledIncome - sampledExpense;
        var uncertainNet =
            expectedNetCenter + (sampledNet - expectedNetCenter) * uncertainty;

        var generatedIncomeShock = 0.0;
        if (shocks.income.isNotEmpty &&
            rng.nextDouble() < shocks.incomeProbability) {
          generatedIncomeShock = shocks.income[rng.nextInt(shocks.income.length)];
          if (whatIf.incomeMultiplierDays <= 0 ||
              day <= whatIf.incomeMultiplierDays) {
            generatedIncomeShock *= whatIf.incomeMultiplier;
          }
        }
        if (delay > 0) {
          final arrivalIndex = i + delay;
          if (arrivalIndex < delayedIncomeShock!.length) {
            delayedIncomeShock[arrivalIndex] += generatedIncomeShock;
          }
          uncertainNet += delayedIncomeShock[i];
        } else {
          uncertainNet += generatedIncomeShock;
        }
        if (shocks.expense.isNotEmpty &&
            rng.nextDouble() < shocks.expenseProbability) {
          var expenseShock = shocks.expense[rng.nextInt(shocks.expense.length)];
          if (whatIf.expenseMultiplierDays <= 0 ||
              day <= whatIf.expenseMultiplierDays) {
            expenseShock *= whatIf.expenseMultiplier;
          }
          uncertainNet -= expenseShock;
        }'''
replace(old_sample, new_sample, 'true statistical income delay queue', marker='generatedIncomeShock')

path.write_text(text, encoding='utf-8')
print('patched true incoming delay semantics')
