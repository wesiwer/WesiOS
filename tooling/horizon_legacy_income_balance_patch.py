from pathlib import Path

# Centralize the definition of actual balance cash. Future schedules and
# legacy auto-generated recurring income are retained in storage but excluded
# from current cash arithmetic.
account = Path('lib/features/treasury/services/account_service.dart')
text = account.read_text(encoding='utf-8')
if 'static List<TransactionModel> actualForBalance(' not in text:
    anchor = '''  static Future<List<AccountSummary>> summaries(
'''
    helper = '''  static List<TransactionModel> actualForBalance(
    List<TransactionModel> transactions, {
    DateTime? asOf,
  }) {
    final cutoff = asOf ?? DateTime.now();
    final recurringIncomeIds = transactions
        .where((tx) => tx.isRecurring && tx.type == TransactionType.income)
        .map((tx) => tx.id)
        .toList();
    bool legacyAutoIncome(TransactionModel tx) =>
        !tx.isRecurring &&
        recurringIncomeIds.any((id) => tx.id.startsWith('${id}_'));
    return transactions
        .where((tx) => !tx.date.isAfter(cutoff) && !legacyAutoIncome(tx))
        .toList();
  }

'''
    if anchor not in text:
        raise SystemExit('missing AccountService summaries anchor')
    text = text.replace(anchor, helper + anchor, 1)

old = '''    final accounts = await getAll();
    final now = asOf ?? DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day, now.hour, now.minute,
        now.second, now.millisecond, now.microsecond);
    return accounts.map((a) {
      final own = transactions
          .where(
              (t) => t.effectiveAccountId == a.id && !t.date.isAfter(cutoff))
          .toList();'''
new = '''    final accounts = await getAll();
    final actual = actualForBalance(transactions, asOf: asOf);
    return accounts.map((a) {
      final own =
          actual.where((t) => t.effectiveAccountId == a.id).toList();'''
if new not in text:
    if old not in text:
        raise SystemExit('missing AccountService current filter anchor')
    text = text.replace(old, new, 1)
account.write_text(text, encoding='utf-8')
print('patched AccountService actual balance helper')

# Treasury breakdown/anomalies use the same definition instead of duplicating
# a weaker date-only filter.
treasury = Path('lib/features/treasury/services/treasury_service.dart')
text = treasury.read_text(encoding='utf-8')
old = '''    final now = DateTime.now();
    final all = (await getAllTransactions())
        .where((tx) => !tx.date.isAfter(now))
        .toList();'''
new = '''    final all = AccountService.actualForBalance(
      await getAllTransactions(),
    );'''
# first occurrence = getBalanceBreakdown
if new not in text:
    if old not in text:
        raise SystemExit('missing Treasury balance breakdown date filter')
    text = text.replace(old, new, 1)
# second occurrence may have been same text for detectAnomalies
if old in text:
    text = text.replace(old, new, 1)
treasury.write_text(text, encoding='utf-8')
print('patched Treasury actual balance semantics')

# Historical reconstruction starts from a current balance that no longer
# contains legacy generated income. Do not subtract those artifacts, and treat
# the recurring parent as a schedule marker whose advanced date is not a
# trustworthy execution timestamp.
backtest = Path('lib/features/treasury/services/forecast_backtest.dart')
text = backtest.read_text(encoding='utf-8')
marker = 'bool legacyAutoIncome(TransactionModel tx) =>'
section_start = text.index('  static double balanceOn(')
section_end = text.index('  static BacktestResult run(', section_start)
section = text[section_start:section_end]
if marker not in section:
    old = '''    final cutoff = _dateOnly(day);
    final currentCutoff = _dateOnly(currentDate ?? DateTime.now());
    var afterCutoffAlreadyInCurrentBalance = 0.0;
    for (final tx in transactions) {
      final txDay = _dateOnly(tx.date);
      if (txDay.isAfter(cutoff) && !txDay.isAfter(currentCutoff)) {
        afterCutoffAlreadyInCurrentBalance +=
            tx.type == TransactionType.income ? tx.amount : -tx.amount;
      }
    }'''
    new = '''    final cutoff = _dateOnly(day);
    final currentCutoff = _dateOnly(currentDate ?? DateTime.now());
    final recurringIncomeIds = transactions
        .where((tx) => tx.isRecurring && tx.type == TransactionType.income)
        .map((tx) => tx.id)
        .toList();
    bool legacyAutoIncome(TransactionModel tx) =>
        !tx.isRecurring &&
        recurringIncomeIds.any((id) => tx.id.startsWith('${id}_'));
    var afterCutoffAlreadyInCurrentBalance = 0.0;
    for (final tx in transactions) {
      if (tx.isRecurring || legacyAutoIncome(tx)) continue;
      final txDay = _dateOnly(tx.date);
      if (txDay.isAfter(cutoff) && !txDay.isAfter(currentCutoff)) {
        afterCutoffAlreadyInCurrentBalance +=
            tx.type == TransactionType.income ? tx.amount : -tx.amount;
      }
    }'''
    if old not in text:
        raise SystemExit('missing ForecastBacktest balance reconstruction anchor')
    text = text.replace(old, new, 1)
backtest.write_text(text, encoding='utf-8')
print('patched backtest legacy recurring artifacts')
