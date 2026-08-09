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

engine = 'lib/features/treasury/services/forecast_engine.dart'
treasury = 'lib/features/treasury/services/treasury_service.dart'
behavior = 'lib/features/treasury/services/horizon_behavior_monitor.dart'
backtest = 'lib/features/treasury/services/forecast_backtest.dart'
competition = 'lib/features/treasury/services/horizon_engine_competition.dart'

# Treasury recurring income is an expectation until real cash is entered.
patch(
    treasury,
    '''      while (RecurringEngine.isDue(anchor, now) && guard < 366) {\n        final due = RecurringEngine.advance(anchor.date, period);\n        await addTransaction(TransactionModel(\n          id: '${tx.id}_${due.millisecondsSinceEpoch}',\n          title: tx.title,\n          amount: tx.amount,\n          type: tx.type,\n          date: due,\n          category: tx.category,\n          description:\n              tx.description == null ? null : 'Recurring: ${tx.description}',\n          isRecurring: false,\n          accountId: tx.accountId,\n        ));\n        anchor = anchor.copyWith(date: due);\n        guard++;\n      }''',
    '''      while (RecurringEngine.isDue(anchor, now) && guard < 366) {\n        final due = RecurringEngine.advance(anchor.date, period);\n        if (tx.type == TransactionType.expense) {\n          await addTransaction(TransactionModel(\n            id: '${tx.id}_${due.millisecondsSinceEpoch}',\n            title: tx.title,\n            amount: tx.amount,\n            type: tx.type,\n            date: due,\n            category: tx.category,\n            description:\n                tx.description == null ? null : 'Recurring: ${tx.description}',\n            isRecurring: false,\n            accountId: tx.accountId,\n          ));\n        }\n        // Income is NOT auto-posted as actual cash. A real received payment\n        // must be entered/imported separately and becomes execution evidence.\n        anchor = anchor.copyWith(date: due);\n        guard++;\n      }''',
    'recurring income execution-only',
    marker='Income is NOT auto-posted as actual cash',
)

# Behavioral warnings observe actual cash only, excluding schedule parents and
# legacy automatically generated recurring-income children.
patch(
    behavior,
    '''    final history =\n        transactions.where((tx) => !_day(tx.date).isAfter(today)).toList();\n    if (history.length < 12) return const [];''',
    '''    final rawHistory =\n        transactions.where((tx) => !_day(tx.date).isAfter(today)).toList();\n    final recurringIncomeIds = rawHistory\n        .where((tx) => tx.isRecurring && tx.type == TransactionType.income)\n        .map((tx) => tx.id)\n        .toList();\n    bool legacyAutoIncome(TransactionModel tx) =>\n        !tx.isRecurring &&\n        recurringIncomeIds.any((id) => tx.id.startsWith('${id}_'));\n    final history = rawHistory\n        .where((tx) => !tx.isRecurring && !legacyAutoIncome(tx))\n        .toList();\n    if (history.length < 12) return const [];''',
    'behavior uses actual cash only',
    marker='legacyAutoIncome',
)

# knownCashShare denominator must include probabilistic recurring/business cash
# as unknown exposure. Otherwise an uncertain CRM deal can disappear from both
# numerator and denominator and falsely inflate the “known” percentage.
patch(
    engine,
    '''    final committedByOffset = List<double>.filled(days, 0);\n    final knownMagnitudeByOffset = List<double>.filled(days, 0);''',
    '''    final committedByOffset = List<double>.filled(days, 0);\n    final knownMagnitudeByOffset = List<double>.filled(days, 0);\n    final uncertainMagnitudeByOffset = List<double>.filled(days, 0);''',
    'unknown magnitude accumulator',
    marker='uncertainMagnitudeByOffset',
)
patch(
    engine,
    '''        if (probability >= 0.9 || tx.type == TransactionType.expense) {\n          committedByOffset[shiftedOffset - 1] += modeledNet * probability;\n          knownMagnitudeByOffset[shiftedOffset - 1] +=\n              modeledNet.abs() * probability;\n        }''',
    '''        if (probability >= 0.9 || tx.type == TransactionType.expense) {\n          committedByOffset[shiftedOffset - 1] += modeledNet * probability;\n          knownMagnitudeByOffset[shiftedOffset - 1] +=\n              modeledNet.abs() * probability;\n        } else {\n          uncertainMagnitudeByOffset[shiftedOffset - 1] +=\n              modeledNet.abs() * probability;\n        }''',
    'uncertain recurring magnitude',
    marker='modeledNet.abs() * probability;\n        } else {\n          uncertainMagnitudeByOffset',
)
patch(
    engine,
    '''      if (event.committed) {\n        committedByOffset[shiftedOffset - 1] +=\n            event.amount * event.probability;\n        knownMagnitudeByOffset[shiftedOffset - 1] +=\n            event.amount.abs() * event.probability;\n      }''',
    '''      if (event.committed) {\n        committedByOffset[shiftedOffset - 1] +=\n            event.amount * event.probability;\n        knownMagnitudeByOffset[shiftedOffset - 1] +=\n            event.amount.abs() * event.probability;\n      } else {\n        uncertainMagnitudeByOffset[shiftedOffset - 1] +=\n            event.amount.abs() * event.probability;\n      }''',
    'uncertain business-event magnitude',
    marker='event.amount.abs() * event.probability;\n      } else {\n        uncertainMagnitudeByOffset',
)
patch(
    engine,
    '''      knownTotal += knownMagnitudeByOffset[i];\n      uncertainTotal += expectedUncertainNet[i].abs();''',
    '''      knownTotal += knownMagnitudeByOffset[i];\n      uncertainTotal +=\n          expectedUncertainNet[i].abs() + uncertainMagnitudeByOffset[i];''',
    'known cash share denominator',
    marker='expectedUncertainNet[i].abs() + uncertainMagnitudeByOffset[i]',
)

# Multi-horizon metrics must measure the FAR portion of the named horizon, not
# let easy day-1 predictions dominate the 90/180-day score. Keep a tail window
# for sample stability; live prediction registry remains exact terminal points.
patch(
    backtest,
    '''        allPoints.addAll(result.points);\n        origins++;''',
    '''        final tailSize = max(3, (horizon * 0.20).round());\n        final startIndex = max(0, result.points.length - tailSize);\n        allPoints.addAll(result.points.sublist(startIndex));\n        origins++;''',
    'horizon-tail calibration metrics',
    marker='final tailSize = max(3, (horizon * 0.20).round())',
)

# Engine competition follows the same horizon-tail exam. 180-day champion is
# therefore judged on late-horizon quality, not mostly on the first month.
patch(
    competition,
    '''          for (var i = 0; i < horizon; i++) {\n            final target = asOf.add(Duration(days: i + 1));''',
    '''          final evaluationStart = max(0, (horizon * 0.75).floor());\n          for (var i = evaluationStart; i < horizon; i++) {\n            final target = asOf.add(Duration(days: i + 1));''',
    'horizon-tail engine championship',
    marker='final evaluationStart = max(0, (horizon * 0.75).floor())',
)
