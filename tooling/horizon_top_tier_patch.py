from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'anchor not found: {path}: {old[:100]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


engine = 'lib/features/treasury/services/forecast_engine.dart'
replace_once(
    engine,
    """  final double incomeMultiplier;\n  final double expenseMultiplier;\n\n  /// Delay all uncertain incoming cash by this many days. Used by the stress\n""",
    """  final double incomeMultiplier;\n  final double expenseMultiplier;\n\n  /// Zero means the multiplier applies for the full selected horizon. A\n  /// positive value limits it to the first N future days (stress library).\n  final int incomeMultiplierDays;\n  final int expenseMultiplierDays;\n\n  /// Delay all uncertain incoming cash by this many days. Used by the stress\n""",
)
replace_once(
    engine,
    """    this.incomeMultiplier = 1.0,\n    this.expenseMultiplier = 1.0,\n    this.incomeDelayDays = 0,\n""",
    """    this.incomeMultiplier = 1.0,\n    this.expenseMultiplier = 1.0,\n    this.incomeMultiplierDays = 0,\n    this.expenseMultiplierDays = 0,\n    this.incomeDelayDays = 0,\n""",
)
replace_once(
    engine,
    """      incomeMultiplier == 1.0 &&\n      expenseMultiplier == 1.0 &&\n      incomeDelayDays == 0 &&\n""",
    """      incomeMultiplier == 1.0 &&\n      expenseMultiplier == 1.0 &&\n      incomeMultiplierDays == 0 &&\n      expenseMultiplierDays == 0 &&\n      incomeDelayDays == 0 &&\n""",
)
replace_once(
    engine,
    """        incomeMultiplier: incomeMultiplier * other.incomeMultiplier,\n        expenseMultiplier: expenseMultiplier * other.expenseMultiplier,\n        incomeDelayDays: max(incomeDelayDays, other.incomeDelayDays),\n""",
    """        incomeMultiplier: incomeMultiplier * other.incomeMultiplier,\n        expenseMultiplier: expenseMultiplier * other.expenseMultiplier,\n        incomeMultiplierDays: max(incomeMultiplierDays, other.incomeMultiplierDays),\n        expenseMultiplierDays: max(expenseMultiplierDays, other.expenseMultiplierDays),\n        incomeDelayDays: max(incomeDelayDays, other.incomeDelayDays),\n""",
)
replace_once(
    engine,
    """        if (whatIf.mainIncomeLossDays >= day) expectedIncome *= 0.15;\n        expectedIncome *= whatIf.incomeMultiplier;\n        expectedExpense *= whatIf.expenseMultiplier;\n""",
    """        if (whatIf.mainIncomeLossDays >= day) expectedIncome *= 0.15;\n        if (whatIf.incomeMultiplierDays <= 0 ||\n            day <= whatIf.incomeMultiplierDays) {\n          expectedIncome *= whatIf.incomeMultiplier;\n        }\n        if (whatIf.expenseMultiplierDays <= 0 ||\n            day <= whatIf.expenseMultiplierDays) {\n          expectedExpense *= whatIf.expenseMultiplier;\n        }\n""",
)

multi = 'lib/features/treasury/services/multi_engine_forecast.dart'
replace_once(
    multi,
    """    required double currentBalance,\n    required int days,\n  }) async {\n""",
    """    required double currentBalance,\n    required int days,\n    DateTime? asOf,\n  }) async {\n""",
)
replace_once(
    multi,
    """    final payload = _buildPayload(transactions, currentBalance, days);\n""",
    """    final payload = _buildPayload(\n      transactions,\n      currentBalance,\n      days,\n      asOf: asOf,\n    );\n""",
)
replace_once(
    multi,
    """  static Map<String, dynamic>? _buildPayload(\n    List<TransactionModel> transactions,\n    double currentBalance,\n    int days,\n  ) {\n    if (transactions.isEmpty) return null;\n    final today = DateTime.now();\n""",
    """  static Map<String, dynamic>? _buildPayload(\n    List<TransactionModel> transactions,\n    double currentBalance,\n    int days, {\n    DateTime? asOf,\n  }) {\n    if (transactions.isEmpty) return null;\n    final today = asOf ?? DateTime.now();\n""",
)
replace_once(
    multi,
    """    for (final tx in transactions) {\n      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);\n      if (day.isBefore(minDay)) minDay = day;\n    }\n""",
    """    for (final tx in transactions) {\n      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);\n      if (day.isAfter(todayOnly)) continue;\n      if (day.isBefore(minDay)) minDay = day;\n    }\n""",
)
# Replace only the dense-series loop after allocation, not the min-day loop.
replace_once(
    multi,
    """    final dense = List<double>.filled(spanDays, 0);\n    for (final tx in transactions) {\n      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);\n      final idx = day.difference(minDay).inDays;\n""",
    """    final dense = List<double>.filled(spanDays, 0);\n    for (final tx in transactions) {\n      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);\n      if (day.isAfter(todayOnly)) continue;\n      final idx = day.difference(minDay).inDays;\n""",
)

print('Horizon compatibility patch applied')
