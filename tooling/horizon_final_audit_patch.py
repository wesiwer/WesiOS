from pathlib import Path

context = Path('lib/features/treasury/services/horizon_business_context.dart')
text = context.read_text(encoding='utf-8')

# Overdue open CRM cash does not vanish. A missed expected close is weaker
# evidence than an on-time future close, so it becomes near-term uncertain cash
# with probability haircut and an explicit warning.
marker = 'final crmOverdue = !due.isAfter(today);'
if marker not in text:
    old = '''        final due = _day(deal.expectedCloseAt!);
        if (!due.isAfter(today) || due.isAfter(end)) continue;
        final probability =
            (deal.probability / 100).clamp(0.01, 0.99).toDouble();
        final rub = deal.amount *
            CurrencyService.rateToRub(deal.currency.toLowerCase());
        events.add(HorizonCashEvent(
          title: 'CRM: ${deal.title}',
          amount: rub,
          date: due,
          probability: probability,
          committed: probability >= 0.9 && deal.stage == DealStage.negotiation,
          source: 'crm',
          riskSource: 'crm:${deal.clientId}',
        ));'''
    new = '''        final due = _day(deal.expectedCloseAt!);
        if (due.isAfter(end)) continue;
        final crmOverdue = !due.isAfter(today);
        var probability =
            (deal.probability / 100).clamp(0.01, 0.99).toDouble();
        var committed = probability >= 0.9 && deal.stage == DealStage.negotiation;
        var modeledDue = due;
        if (crmOverdue) {
          probability = (probability * 0.65).clamp(0.05, 0.85).toDouble();
          committed = false;
          modeledDue = today.add(const Duration(days: 1));
          warnings.add(ForecastActionPrompt(
            code: 'overdue-crm-${deal.id}',
            severity: ForecastPromptSeverity.warning,
            textRu:
                'Сделка «${deal.title}» просрочила ожидаемую дату закрытия. Horizon не удаляет входящий поток, но снижает его вероятность и переносит в ближайший неопределённый горизонт.',
            textEn:
                'Deal “${deal.title}” missed its expected close date. Horizon keeps the incoming cash, but lowers its probability and moves it to the nearest uncertain horizon.',
            amount: deal.amount,
            day: 1,
          ));
        }
        final rub = deal.amount *
            CurrencyService.rateToRub(deal.currency.toLowerCase());
        events.add(HorizonCashEvent(
          title: 'CRM: ${deal.title}',
          amount: rub,
          date: modeledDue,
          probability: probability,
          committed: committed,
          source: 'crm',
          riskSource: 'crm:${deal.clientId}',
        ));'''
    if old not in text:
        raise SystemExit('missing overdue CRM anchor')
    text = text.replace(old, new, 1)
    print('patched overdue CRM cash')
else:
    print('skip overdue CRM cash')

# An expected income that already missed its task due date is no longer fully
# known. Expenses remain committed: the company still owes them even when late.
marker = 'final missedIncoming = overdue && parsed.signedAmount > 0;'
if marker not in text:
    old = '''          events.add(HorizonCashEvent(
            title: 'Task: ${task.title}',
            amount: parsed.signedAmount,
            date: today.add(const Duration(days: 1)),
            probability: parsed.probability,
            committed: parsed.committed,
            source: 'task-obligation-overdue',
            riskSource: 'task:${task.id}',
          ));'''
    new = '''          final missedIncoming = overdue && parsed.signedAmount > 0;
          final modeledProbability = missedIncoming
              ? min(parsed.probability, 0.65).toDouble()
              : parsed.probability;
          events.add(HorizonCashEvent(
            title: 'Task: ${task.title}',
            amount: parsed.signedAmount,
            date: today.add(const Duration(days: 1)),
            probability: modeledProbability,
            committed: missedIncoming ? false : parsed.committed,
            source: 'task-obligation-overdue',
            riskSource: 'task:${task.id}',
          ));'''
    if old not in text:
        raise SystemExit('missing overdue Task anchor')
    text = text.replace(old, new, 1)
    print('patched overdue Task incoming reliability')
else:
    print('skip overdue Task incoming reliability')

context.write_text(text, encoding='utf-8')

# Low-data fallback volatility also uses actual uncertain history rather than
# schedule parents / legacy synthetic recurring income.
engine = Path('lib/features/treasury/services/forecast_engine.dart')
text = engine.read_text(encoding='utf-8')
old = '''    final fallbackDailyVolatility = _fallbackDailyVolatility(
      history: history,
      events: [...businessEvents, ...externalByOffset.values.expand((e) => e)],
      currentBalance: currentBalance,
    );'''
new = '''    final fallbackDailyVolatility = _fallbackDailyVolatility(
      history: nonRecurring,
      events: [...businessEvents, ...externalByOffset.values.expand((e) => e)],
      currentBalance: currentBalance,
    );'''
if new not in text:
    if old not in text:
        raise SystemExit('missing fallback volatility anchor')
    text = text.replace(old, new, 1)
    print('patched fallback volatility actual evidence')
engine.write_text(text, encoding='utf-8')
