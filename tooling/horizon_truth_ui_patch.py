from pathlib import Path


def replace(path, old, new, label):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if new in text:
        print('skip', label)
        return
    if old not in text:
        raise SystemExit('missing anchor: ' + label)
    p.write_text(text.replace(old, new, 1), encoding='utf-8')
    print('patched', label)

engine = 'lib/features/treasury/services/forecast_engine.dart'
panel = 'lib/features/treasury/widgets/horizon_decision_panel.dart'
treasury = 'lib/features/treasury/services/treasury_service.dart'
behavior = 'lib/features/treasury/services/horizon_behavior_monitor.dart'

replace(
    engine,
    '''  final double calibrationCoverage;\n  final CashRegime regime;''',
    '''  final double calibrationCoverage;\n  final int calibrationSamples;\n  final String calibrationSource;\n  final CashRegime regime;''',
    'ForecastResult calibration evidence fields',
)
replace(
    engine,
    '''    this.calibrationCoverage = 0,\n    this.regime = CashRegime.stable,''',
    '''    this.calibrationCoverage = 0,\n    this.calibrationSamples = 0,\n    this.calibrationSource = 'identity',\n    this.regime = CashRegime.stable,''',
    'ForecastResult calibration evidence defaults',
)
replace(
    engine,
    '''        calibrationCoverage: calibrationCoverage,\n        regime: regime,''',
    '''        calibrationCoverage: calibrationCoverage,\n        calibrationSamples: calibrationSamples,\n        calibrationSource: calibrationSource,\n        regime: regime,''',
    'ForecastResult copyWith evidence preservation',
)
replace(
    engine,
    '''      calibrationCoverage: endBucket.coverage,\n      regime: regimeModel.current,''',
    '''      calibrationCoverage: endBucket.coverage,\n      calibrationSamples: endBucket.samples,\n      calibrationSource: calibration.source,\n      regime: regimeModel.current,''',
    'ForecastEngine returns evidence metadata',
)

# Auto-materialized recurring income is a schedule artifact, not evidence that
# money actually arrived. Keep the parent recurring contract, but exclude its
# generated income children from statistical baseline/shock learning.
replace(
    engine,
    '''    final recurringIds = recurringTxs.map((e) => e.id).toSet();\n    final nonRecurring =\n        history.where((e) => !recurringIds.contains(e.id)).toList();''',
    '''    final recurringIds = recurringTxs.map((e) => e.id).toSet();\n    final recurringIncomeIds = recurringTxs\n        .where((e) => e.type == TransactionType.income)\n        .map((e) => e.id)\n        .toList();\n    bool autoMaterializedIncome(TransactionModel tx) =>\n        !tx.isRecurring &&\n        recurringIncomeIds.any((id) => tx.id.startsWith('${id}_'));\n    final nonRecurring = history\n        .where((e) =>\n            !recurringIds.contains(e.id) && !autoMaterializedIncome(e))\n        .toList();''',
    'exclude auto-materialized recurring income from statistical history',
)

# A recurring parent can be advanced to its latest processed occurrence by
# TreasuryService. Reconstruct past expected due dates backwards from the
# latest occurrence <= today instead of assuming recurring.date is the
# original historical anchor.
replace(
    engine,
    '''    final start = today.subtract(Duration(days: lookback));\n\n    var occurrence = recurring.date;\n    var guard = 0;\n    while (occurrence.isBefore(start) && guard++ < 10000) {\n      occurrence = RecurringEngine.advance(occurrence, period);\n    }\n    final expectedDates = <DateTime>[];\n    while (!occurrence.isAfter(today) && guard++ < 10000) {\n      if (!occurrence.isBefore(start)) {\n        expectedDates\n            .add(DateTime(occurrence.year, occurrence.month, occurrence.day));\n      }\n      occurrence = RecurringEngine.advance(occurrence, period);\n    }\n    if (expectedDates.length < 2) return 1.0;''',
    '''    final start = today.subtract(Duration(days: lookback));\n    final anchor =\n        DateTime(recurring.date.year, recurring.date.month, recurring.date.day);\n    if (anchor.isAfter(today)) return 1.0;\n\n    // Bring an old original anchor forward to the latest expected occurrence\n    // not after today. If TreasuryService has already advanced the parent,\n    // this loop is naturally a no-op or only a few iterations.\n    var latest = anchor;\n    var guard = 0;\n    while (guard++ < 10000) {\n      final next = RecurringEngine.advance(latest, period);\n      if (next.isAfter(today)) break;\n      latest = next;\n    }\n\n    DateTime previousOccurrence(DateTime date) {\n      switch (period) {\n        case RecurringPeriod.daily:\n          return date.subtract(const Duration(days: 1));\n        case RecurringPeriod.weekly:\n          return date.subtract(const Duration(days: 7));\n        case RecurringPeriod.monthly:\n          var year = date.year;\n          var month = date.month - 1;\n          if (month < 1) {\n            year--;\n            month = 12;\n          }\n          final lastDay = DateTime(year, month + 1, 0).day;\n          return DateTime(year, month, min(date.day, lastDay));\n        case RecurringPeriod.yearly:\n          final year = date.year - 1;\n          final lastDay = DateTime(year, date.month + 1, 0).day;\n          return DateTime(year, date.month, min(date.day, lastDay));\n      }\n    }\n\n    final expectedDates = <DateTime>[];\n    var occurrence = latest;\n    guard = 0;\n    while (!occurrence.isBefore(start) && guard++ < 10000) {\n      expectedDates.add(occurrence);\n      occurrence = previousOccurrence(occurrence);\n    }\n    expectedDates.sort();\n    if (expectedDates.length < 2) return 1.0;''',
    'reconstruct recurring execution schedule backwards from advanced anchor',
)

# Treasury recurring income is a receivable expectation until real cash is
# entered. Never materialize it automatically as actual balance. Expenses keep
# the conservative auto-materialization behavior, while both directions move
# the schedule anchor forward so the next due date stays correct.
replace(
    treasury,
    '''      while (RecurringEngine.isDue(anchor, now) && guard < 366) {\n        final due = RecurringEngine.advance(anchor.date, period);\n        await addTransaction(TransactionModel(\n          id: '${tx.id}_${due.millisecondsSinceEpoch}',\n          title: tx.title,\n          amount: tx.amount,\n          type: tx.type,\n          date: due,\n          category: tx.category,\n          description:\n              tx.description == null ? null : 'Recurring: ${tx.description}',\n          isRecurring: false,\n          accountId: tx.accountId,\n        ));\n        anchor = anchor.copyWith(date: due);\n        guard++;\n      }''',
    '''      while (RecurringEngine.isDue(anchor, now) && guard < 366) {\n        final due = RecurringEngine.advance(anchor.date, period);\n        if (tx.type == TransactionType.expense) {\n          await addTransaction(TransactionModel(\n            id: '${tx.id}_${due.millisecondsSinceEpoch}',\n            title: tx.title,\n            amount: tx.amount,\n            type: tx.type,\n            date: due,\n            category: tx.category,\n            description:\n                tx.description == null ? null : 'Recurring: ${tx.description}',\n            isRecurring: false,\n            accountId: tx.accountId,\n          ));\n        }\n        // Income is NOT auto-posted as actual cash. A real received payment\n        // must be entered/imported separately and becomes execution evidence.\n        anchor = anchor.copyWith(date: due);\n        guard++;\n      }''',
    'stop auto-posting recurring income as actual Treasury cash',
)

# Behavioral warnings must observe actual cash, not recurring schedule marker
# rows or legacy auto-materialized recurring income children.
replace(
    behavior,
    '''    final history = transactions.where((tx) => !_day(tx.date).isAfter(today)).toList();\n    if (history.length < 12) return const [];''',
    '''    final rawHistory =\n        transactions.where((tx) => !_day(tx.date).isAfter(today)).toList();\n    final recurringIncomeIds = rawHistory\n        .where((tx) => tx.isRecurring && tx.type == TransactionType.income)\n        .map((tx) => tx.id)\n        .toList();\n    bool legacyAutoIncome(TransactionModel tx) =>\n        !tx.isRecurring &&\n        recurringIncomeIds.any((id) => tx.id.startsWith('${id}_'));\n    final history = rawHistory\n        .where((tx) => !tx.isRecurring && !legacyAutoIncome(tx))\n        .toList();\n    if (history.length < 12) return const [];''',
    'behavior monitor uses actual cash only',
)

replace(
    panel,
    '''              Expanded(\n                child: _progress(\n                  _ru ? 'Калибровка P10–P90' : 'P10–P90 coverage',\n                  forecast.calibrationCoverage,\n                  target: .8,\n                ),\n              ),''',
    '''              Expanded(\n                child: _calibrationProgress(),\n              ),''',
    'Decision panel measured calibration widget',
)

progress_anchor = '''  Widget _progress(String label, double value, {double? target}) {\n'''
calibration_method = '''  Widget _calibrationProgress() {\n    final samples = forecast.calibrationSamples;\n    if (samples <= 0) {\n      return Column(\n        crossAxisAlignment: CrossAxisAlignment.start,\n        children: [\n          Row(\n            children: [\n              Expanded(\n                child: Text(\n                  _ru ? 'Калибровка P10–P90' : 'P10–P90 calibration',\n                  style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5),\n                ),\n              ),\n              Text(\n                _ru ? 'нет оценки · цель 80%' : 'not measured · target 80%',\n                style: TextStyle(\n                  color: Colors.amber,\n                  fontSize: 10.5,\n                  fontWeight: FontWeight.w700,\n                ),\n              ),\n            ],\n          ),\n          const SizedBox(height: 4),\n          ClipRRect(\n            borderRadius: BorderRadius.circular(4),\n            child: LinearProgressIndicator(\n              value: 0,\n              minHeight: 5,\n              backgroundColor: AppTheme.surfaceLight,\n              color: Colors.amber.withOpacity(.55),\n            ),\n          ),\n          const SizedBox(height: 3),\n          Text(\n            _ru\n                ? 'Цель — не измеренный факт. Нужны созревшие backtest/live наблюдения.'\n                : 'The target is not measured evidence. Mature backtest/live observations are required.',\n            maxLines: 2,\n            overflow: TextOverflow.ellipsis,\n            style: TextStyle(color: AppTheme.textMuted, fontSize: 9.5),\n          ),\n        ],\n      );\n    }\n\n    final source = forecast.calibrationSource.startsWith('monthly-learning:backtest+issued')\n        ? (_ru ? 'live + backtest' : 'live + backtest')\n        : forecast.calibrationSource.startsWith('monthly-learning')\n            ? 'backtest'\n            : forecast.calibrationSource;\n    return Column(\n      crossAxisAlignment: CrossAxisAlignment.start,\n      children: [\n        _progress(\n          _ru ? 'P10–P90 coverage · n=$samples' : 'P10–P90 coverage · n=$samples',\n          forecast.calibrationCoverage,\n          target: .8,\n        ),\n        const SizedBox(height: 3),\n        Text(\n          _ru ? 'Источник: $source' : 'Source: $source',\n          maxLines: 1,\n          overflow: TextOverflow.ellipsis,\n          style: TextStyle(color: AppTheme.textMuted, fontSize: 9.5),\n        ),\n      ],\n    );\n  }\n\n'''
p = Path(panel)
text = p.read_text(encoding='utf-8')
if '_calibrationProgress() {' not in text:
    if progress_anchor not in text:
        raise SystemExit('missing anchor: calibration method insertion')
    text = text.replace(progress_anchor, calibration_method + progress_anchor, 1)
    p.write_text(text, encoding='utf-8')
    print('patched calibration truth UI method')
else:
    print('skip calibration truth UI method')
