from pathlib import Path

engine = Path('lib/features/treasury/services/forecast_engine.dart')
text = engine.read_text(encoding='utf-8')


def replace(old: str, new: str, label: str, marker: str | None = None):
    global text
    if marker is not None and marker in text:
        print('skip', label)
        return
    if old not in text:
        raise SystemExit('missing anchor: ' + label)
    text = text.replace(old, new, 1)
    print('patched', label)

replace(
    '''  final String source;\n  final String? accountId;\n\n  const HorizonCashEvent({\n    required this.title,\n    required this.amount,\n    required this.date,\n    this.probability = 1,\n    this.committed = false,\n    this.source = 'external',\n    this.accountId,\n  });\n}''',
    '''  final String source;\n  final String? riskSource;\n  final String? accountId;\n\n  const HorizonCashEvent({\n    required this.title,\n    required this.amount,\n    required this.date,\n    this.probability = 1,\n    this.committed = false,\n    this.source = 'external',\n    this.riskSource,\n    this.accountId,\n  });\n\n  String get effectiveRiskSource => riskSource ?? source;\n}''',
    'cash event risk source',
    marker='String get effectiveRiskSource => riskSource ?? source;',
)

insert_anchor = '''    final regimeModel = _RegimeModel.detect(denseNet);\n\n    final committedByOffset = List<double>.filled(days, 0);'''
insert_new = '''    final regimeModel = _RegimeModel.detect(denseNet);\n\n    // Stress “loss of main source” must target the economically largest\n    // incoming source across statistical streams, recurring contracts and\n    // company business events — not merely the largest historical category.\n    final mainLossWindow = min(days, max(0, whatIf.mainIncomeLossDays));\n    final mainIncomeExposure = <String, double>{};\n    if (mainLossWindow > 0) {\n      for (final stream in incomeStreams) {\n        final exposure = stream.dailyBaseline * mainLossWindow;\n        if (exposure > 0) {\n          mainIncomeExposure['stream:${stream.key}'] = exposure;\n        }\n      }\n      for (final tx in recurringTxs) {\n        if (tx.type != TransactionType.income) continue;\n        final projected = RecurringEngine.projectFutureContributions(\n          [tx],\n          days: mainLossWindow,\n          from: todayOnly,\n        );\n        final reliability = (recurringReliability[tx.id] ??\n                _estimateRecurringReliability(tx, transactions, todayOnly))\n            .clamp(0.05, 1.0)\n            .toDouble();\n        final expected = projected.values\n            .where((value) => value > 0)\n            .fold<double>(0, (sum, value) => sum + value * reliability);\n        if (expected > 0) {\n          mainIncomeExposure['recurring:${tx.id}'] = expected;\n        }\n      }\n      for (final event in businessEvents) {\n        if (event.amount <= 0) continue;\n        final offset = DateTime(event.date.year, event.date.month, event.date.day)\n            .difference(todayOnly)\n            .inDays;\n        if (offset < 1 || offset > mainLossWindow) continue;\n        final key = 'business:${event.effectiveRiskSource}';\n        mainIncomeExposure[key] = (mainIncomeExposure[key] ?? 0) +\n            event.amount * event.probability;\n      }\n    }\n    final primaryLossSource = mainIncomeExposure.isEmpty\n        ? null\n        : mainIncomeExposure.entries\n            .reduce((a, b) => a.value >= b.value ? a : b)\n            .key;\n\n    final committedByOffset = List<double>.filled(days, 0);'''
replace(insert_anchor, insert_new, 'cross-layer main source selection', marker='final primaryLossSource = mainIncomeExposure.isEmpty')

replace(
    '''              String title,\n              String? accountId\n            })>>{};''',
    '''              String title,\n              String riskSource,\n              String? accountId\n            })>>{};''',
    'recurring risk source tuple',
    marker='String riskSource,\n              String? accountId',
)

replace(
    '''        var modeledNet = entry.value;\n        if (modeledNet > 0 &&\n            (whatIf.incomeMultiplierDays <= 0 ||''',
    '''        var modeledNet = entry.value;\n        if (modeledNet > 0 &&\n            shiftedOffset <= mainLossWindow &&\n            primaryLossSource == 'recurring:${tx.id}') {\n          modeledNet *= 0.15;\n        }\n        if (modeledNet > 0 &&\n            (whatIf.incomeMultiplierDays <= 0 ||''',
    'apply main source loss to recurring income',
    marker="primaryLossSource == 'recurring:${tx.id}'",
)

replace(
    '''          probability: probability,\n          title: tx.title,\n          accountId: tx.accountId,''',
    '''          probability: probability,\n          title: tx.title,\n          riskSource: 'recurring:${tx.id}',\n          accountId: tx.accountId,''',
    'store recurring risk source',
    marker="riskSource: 'recurring:${tx.id}'",
)

old_business = '''    for (final event in businessEvents) {\n      final offset = DateTime(event.date.year, event.date.month, event.date.day)\n          .difference(todayOnly)\n          .inDays;\n      if (offset < 1 || offset > days) continue;\n      final shiftedOffset =\n          event.amount > 0 ? offset + whatIf.incomeDelayDays : offset;\n      if (shiftedOffset < 1 || shiftedOffset > days) continue;\n      (externalByOffset[shiftedOffset] ??= []).add(event);\n      if (event.committed) {\n        committedByOffset[shiftedOffset - 1] +=\n            event.amount * event.probability;\n        knownMagnitudeByOffset[shiftedOffset - 1] +=\n            event.amount.abs() * event.probability;\n      } else {\n        uncertainMagnitudeByOffset[shiftedOffset - 1] +=\n            event.amount.abs() * event.probability;\n      }\n    }'''
new_business = '''    for (final event in businessEvents) {\n      final offset = DateTime(event.date.year, event.date.month, event.date.day)\n          .difference(todayOnly)\n          .inDays;\n      if (offset < 1 || offset > days) continue;\n      final shiftedOffset =\n          event.amount > 0 ? offset + whatIf.incomeDelayDays : offset;\n      if (shiftedOffset < 1 || shiftedOffset > days) continue;\n\n      var modeledAmount = event.amount;\n      if (modeledAmount > 0 &&\n          shiftedOffset <= mainLossWindow &&\n          primaryLossSource == 'business:${event.effectiveRiskSource}') {\n        modeledAmount *= 0.15;\n      }\n      final modeledEvent = HorizonCashEvent(\n        title: event.title,\n        amount: modeledAmount,\n        date: event.date,\n        probability: event.probability,\n        committed: event.committed,\n        source: event.source,\n        riskSource: event.riskSource,\n        accountId: event.accountId,\n      );\n      (externalByOffset[shiftedOffset] ??= []).add(modeledEvent);\n      if (modeledEvent.committed) {\n        committedByOffset[shiftedOffset - 1] +=\n            modeledEvent.amount * modeledEvent.probability;\n        knownMagnitudeByOffset[shiftedOffset - 1] +=\n            modeledEvent.amount.abs() * modeledEvent.probability;\n      } else {\n        uncertainMagnitudeByOffset[shiftedOffset - 1] +=\n            modeledEvent.amount.abs() * modeledEvent.probability;\n      }\n    }'''
replace(old_business, new_business, 'apply main source loss to business cash', marker="primaryLossSource == 'business:${event.effectiveRiskSource}'")

replace(
    '''    final primaryIncomeKey = incomeStreams.isEmpty\n        ? null\n        : incomeStreams\n            .reduce((a, b) => a.dailyBaseline >= b.dailyBaseline ? a : b)\n            .key;\n\n    for (var path = 0; path < effectivePaths; path++) {''',
    '''    for (var path = 0; path < effectivePaths; path++) {''',
    'remove historical-only primary source',
    marker='// main source selection is cross-layer',
)
# The marker above is not naturally inserted, so if the old block was removed
# in a prior run we simply continue. Add a harmless comment before loop.
if 'final primaryIncomeKey = incomeStreams.isEmpty' not in text and '// main source selection is cross-layer' not in text:
    text = text.replace('    for (var path = 0; path < effectivePaths; path++) {', '    // main source selection is cross-layer (stream / recurring / business).\n    for (var path = 0; path < effectivePaths; path++) {', 1)

replace(
    '''            if (whatIf.mainIncomeLossDays >= day && s.key == primaryIncomeKey) {\n              component *= 0.15;\n            }''',
    '''            if (day <= mainLossWindow &&\n                primaryLossSource == 'stream:${s.key}') {\n              component *= 0.15;\n            }''',
    'apply main source loss to statistical stream',
    marker="primaryLossSource == 'stream:${s.key}'",
)

engine.write_text(text, encoding='utf-8')

# Give business events stable risk-source identity while preserving the public
# explanation source strings expected by existing UI/tests.
context = Path('lib/features/treasury/services/horizon_business_context.dart')
ctx = context.read_text(encoding='utf-8')
replacements = [
    ("          source: 'crm',\n        ));", "          source: 'crm',\n          riskSource: 'crm:${deal.clientId}',\n        ));"),
    ("            source: 'audio-renewal',\n          ));", "            source: 'audio-renewal',\n            riskSource: 'audio:${beat.id}',\n          ));"),
    ("            source: 'audio-royalty',\n          ));", "            source: 'audio-royalty',\n            riskSource: 'audio:${beat.id}',\n          ));"),
    ("            source: 'task-obligation-overdue',\n          ));", "            source: 'task-obligation-overdue',\n            riskSource: 'task:${task.id}',\n          ));"),
    ("          source: 'task-obligation',\n        ));", "          source: 'task-obligation',\n          riskSource: 'task:${task.id}',\n        ));"),
]
for old, new in replacements:
    if new in ctx:
        continue
    if old not in ctx:
        raise SystemExit('missing business-context riskSource anchor: ' + old.splitlines()[0])
    ctx = ctx.replace(old, new, 1)
context.write_text(ctx, encoding='utf-8')
print('patched business-context risk source identities')
