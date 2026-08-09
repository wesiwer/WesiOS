from pathlib import Path

path = Path('lib/features/treasury/services/forecast_engine.dart')
text = path.read_text(encoding='utf-8')
marker = 'final actualEvidenceCount = nonRecurring.length;'
if marker in text:
    print('confidence evidence patch already applied')
    raise SystemExit(0)

old = '''    final hasKnownForwardCash = recurringTxs.isNotEmpty ||
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
'''
new = '''    final hasKnownForwardCash = recurringTxs.isNotEmpty ||
        businessEvents.isNotEmpty ||
        scheduledOneOff.isNotEmpty;

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

    // Confidence must be earned by actual non-recurring observations. Schedule
    // parents and legacy auto-materialized recurring income are known/expected
    // cash structures, not statistical evidence about realized daily behavior.
    final actualEvidenceCount = nonRecurring.length;
    if (!hasKnownForwardCash &&
        (actualEvidenceCount < 3 || spanDays < minHistorySpanDays)) {
      return ForecastResult.empty();
    }
    final confidence = _confidence(spanDays, actualEvidenceCount);
    final hasStatisticalHistory =
        spanDays >= minHistorySpanDays && actualEvidenceCount >= 3;
    final seasonalityApplied = hasStatisticalHistory &&
        spanDays >= _seasonalityMinSpanDays &&
        actualEvidenceCount >= 12;
'''
if old not in text:
    raise SystemExit('confidence evidence anchor not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('patched confidence to actual evidence only')
