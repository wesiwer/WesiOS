from pathlib import Path


def patch(path: str, old: str, new: str, label: str, marker: str | None = None):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if marker is not None and marker in text:
        print('skip', label)
        return
    if old not in text:
        raise SystemExit('missing anchor: ' + label)
    p.write_text(text.replace(old, new, 1), encoding='utf-8')
    print('patched', label)

# Current account balances exclude future-dated scheduled transactions.
patch(
    'lib/features/treasury/services/account_service.dart',
    '''  static Future<List<AccountSummary>> summaries(\n      List<TransactionModel> transactions) async {\n    final accounts = await getAll();\n    return accounts.map((a) {\n      final own =\n          transactions.where((t) => t.effectiveAccountId == a.id).toList();''',
    '''  static Future<List<AccountSummary>> summaries(\n    List<TransactionModel> transactions, {\n    DateTime? asOf,\n  }) async {\n    final accounts = await getAll();\n    final now = asOf ?? DateTime.now();\n    final cutoff = DateTime(now.year, now.month, now.day, now.hour, now.minute, now.second, now.millisecond, now.microsecond);\n    return accounts.map((a) {\n      final own = transactions\n          .where((t) =>\n              t.effectiveAccountId == a.id && !t.date.isAfter(cutoff))\n          .toList();''',
    'exclude future transactions from account current balance',
    marker='DateTime? asOf,\n  }) async {\n    final accounts = await getAll();',
)

# Treasury breakdown/anomalies are present-state metrics as well.
patch(
    'lib/features/treasury/services/treasury_service.dart',
    '''  Future<Map<String, double>> getBalanceBreakdown() async {\n    final all = await getAllTransactions();\n    double income = 0, expense = 0;\n    for (final tx in all) {''',
    '''  Future<Map<String, double>> getBalanceBreakdown() async {\n    final now = DateTime.now();\n    final all = (await getAllTransactions())\n        .where((tx) => !tx.date.isAfter(now))\n        .toList();\n    double income = 0, expense = 0;\n    for (final tx in all) {''',
    'exclude future cash from current balance breakdown',
    marker='final all = (await getAllTransactions())\n        .where((tx) => !tx.date.isAfter(now))',
)
patch(
    'lib/features/treasury/services/treasury_service.dart',
    '''  Future<List<TransactionModel>> detectAnomalies() async {\n    return AnomalyEngine.detect(await getAllTransactions());\n  }''',
    '''  Future<List<TransactionModel>> detectAnomalies() async {\n    final now = DateTime.now();\n    final actual = (await getAllTransactions())\n        .where((tx) => !tx.date.isAfter(now))\n        .toList();\n    return AnomalyEngine.detect(actual);\n  }''',
    'exclude future schedules from anomaly history',
    marker='final actual = (await getAllTransactions())',
)

# Historical balance reconstruction starts from the actual balance at
# currentDate. Future scheduled transactions after currentDate were never in
# that balance and therefore must not be subtracted when reconstructing past.
backtest = Path('lib/features/treasury/services/forecast_backtest.dart')
text = backtest.read_text(encoding='utf-8')
if 'DateTime? currentDate,' not in text[text.index('  static double balanceOn('):text.index('  static BacktestResult run(')]:
    old = '''  static double balanceOn(\n    DateTime day,\n    List<TransactionModel> transactions,\n    double currentBalance,\n  ) {\n    final cutoff = _dateOnly(day);\n    var future = 0.0;\n    for (final tx in transactions) {\n      if (_dateOnly(tx.date).isAfter(cutoff)) {\n        future += tx.type == TransactionType.income ? tx.amount : -tx.amount;\n      }\n    }\n    return currentBalance - future;\n  }'''
    new = '''  static double balanceOn(\n    DateTime day,\n    List<TransactionModel> transactions,\n    double currentBalance, {\n    DateTime? currentDate,\n  }) {\n    final cutoff = _dateOnly(day);\n    final currentCutoff = _dateOnly(currentDate ?? DateTime.now());\n    var afterCutoffAlreadyInCurrentBalance = 0.0;\n    for (final tx in transactions) {\n      final txDay = _dateOnly(tx.date);\n      if (txDay.isAfter(cutoff) && !txDay.isAfter(currentCutoff)) {\n        afterCutoffAlreadyInCurrentBalance +=\n            tx.type == TransactionType.income ? tx.amount : -tx.amount;\n      }\n    }\n    return currentBalance - afterCutoffAlreadyInCurrentBalance;\n  }'''
    if old not in text:
        raise SystemExit('missing balanceOn anchor')
    text = text.replace(old, new, 1)
    print('patched balanceOn current-date ceiling')

# Thread the current balance date through _runAt.
if 'required DateTime currentDate,' not in text[text.index('  static BacktestResult _runAt('):text.index('  static BacktestResult _summarize(')]:
    text = text.replace(
        '''    required DateTime asOf,\n    required int horizonDays,''',
        '''    required DateTime asOf,\n    required DateTime currentDate,\n    required int horizonDays,''',
        1,
    )
    # run() call
    text = text.replace(
        '''      asOf: asOf,\n      horizonDays: horizonDays,''',
        '''      asOf: asOf,\n      currentDate: today,\n      horizonDays: horizonDays,''',
        1,
    )
    # runMultiHorizon _runAt call(s)
    needle = '''          asOf: asOf,\n          horizonDays: horizon,'''
    if needle not in text:
        raise SystemExit('missing runMultiHorizon currentDate anchor')
    text = text.replace(
        needle,
        '''          asOf: asOf,\n          currentDate: today,\n          horizonDays: horizon,''',
    )
    print('threaded currentDate into backtest runs')

text = text.replace(
    'final balanceAtAsOf = balanceOn(asOf, transactions, currentBalance);',
    '''final balanceAtAsOf = balanceOn(\n      asOf,\n      transactions,\n      currentBalance,\n      currentDate: currentDate,\n    );''',
)
text = text.replace(
    '''actual: balanceOn(asOf.add(Duration(days: i + 1)), transactions, currentBalance),''',
    '''actual: balanceOn(\n          asOf.add(Duration(days: i + 1)),\n          transactions,\n          currentBalance,\n          currentDate: currentDate,\n        ),''',
)
backtest.write_text(text, encoding='utf-8')

# Engine competition uses the same current-balance ceiling.
competition = Path('lib/features/treasury/services/horizon_engine_competition.dart')
text = competition.read_text(encoding='utf-8')
text = text.replace(
    'ForecastBacktest.balanceOn(asOf, transactions, currentBalance);',
    '''ForecastBacktest.balanceOn(\n              asOf, transactions, currentBalance, currentDate: today);''',
)
text = text.replace(
    '''ForecastBacktest.balanceOn(\n                target,\n                transactions,\n                currentBalance,\n              ),''',
    '''ForecastBacktest.balanceOn(\n                target,\n                transactions,\n                currentBalance,\n                currentDate: today,\n              ),''',
)
competition.write_text(text, encoding='utf-8')
print('patched engine championship historical balance ceiling')

# Prediction registry evaluates matured issued forecasts against current actual
# ledger only; future scheduled rows cannot leak into realized balances.
registry = Path('lib/features/treasury/services/horizon_prediction_registry.dart')
text = registry.read_text(encoding='utf-8')
text = text.replace(
    '''        final actual = ForecastBacktest.balanceOn(\n          prediction.targetDate,\n          transactions,\n          currentBalance,\n        );''',
    '''        final actual = ForecastBacktest.balanceOn(\n          prediction.targetDate,\n          transactions,\n          currentBalance,\n          currentDate: today,\n        );''',
)
registry.write_text(text, encoding='utf-8')
print('patched prediction registry realized balance ceiling')
