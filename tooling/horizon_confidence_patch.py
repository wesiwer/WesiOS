from pathlib import Path

path = Path('lib/features/treasury/services/forecast_engine.dart')
text = path.read_text(encoding='utf-8')
marker = 'final actualEvidenceCount = nonRecurring.length;'
if marker in text and 'DateTime minDay = todayOnly;\n    for (final tx in nonRecurring)' in text:
    print('confidence/evidence-span patch already applied')
    raise SystemExit(0)

old = '''    DateTime minDay = todayOnly;
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

    // Both statistical sample count and statistical time span must be earned
    // by actual non-recurring cash observations. Recurring schedule parents
    // and legacy generated income rows belong to the known/expected layer and
    // must never dilute occurrence frequency or manufacture confidence.
    DateTime minDay = todayOnly;
    for (final tx in nonRecurring) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (day.isBefore(minDay)) minDay = day;
    }
    final spanDays = nonRecurring.isEmpty
        ? 1
        : todayOnly.difference(minDay).inDays + 1;
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
    raise SystemExit('confidence/evidence-span anchor not found')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('patched confidence and history span to actual evidence only')
