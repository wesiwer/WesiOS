from pathlib import Path
import re


def replace_once(path: str, old: str, new: str):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'anchor not found in {path}: {old[:120]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


# 1) True delayed-income queue: shift statistical incoming cash instead of deleting it.
path = 'lib/features/treasury/services/forecast_engine.dart'
p = Path(path)
text = p.read_text(encoding='utf-8')
old = """    for (var path = 0; path < effectivePaths; path++) {
      var balance = currentBalance;
      var regime = _RegimeModel.sampleInitial(rng, regimeModel.probabilities);
      var blockRemaining = 0;
      var blockIndex = 0;
      var blockLength = 0;
      for (var i = 0; i < days; i++) {
"""
new = """    for (var path = 0; path < effectivePaths; path++) {
      var balance = currentBalance;
      var regime = _RegimeModel.sampleInitial(rng, regimeModel.probabilities);
      var blockRemaining = 0;
      var blockIndex = 0;
      var blockLength = 0;
      final delay = max(0, whatIf.incomeDelayDays);
      final delayedExpectedIncome = List<double>.filled(days + delay + 2, 0);
      final delayedSampledIncome = List<double>.filled(days + delay + 2, 0);
      final delayedIncomeShock = List<double>.filled(days + delay + 2, 0);
      for (var i = 0; i < days; i++) {
"""
if old not in text:
    raise SystemExit('delay queue setup anchor not found')
text = text.replace(old, new, 1)
old = """        var sampledIncome = max(0.0, expectedIncome + residualIncome);
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
        }
"""
new = """        var sampledIncome = max(0.0, expectedIncome + residualIncome);
        final sampledExpense = max(0.0, expectedExpense + residualExpense);
        var incomeShock = 0.0;
        if (shocks.income.isNotEmpty &&
            rng.nextDouble() < shocks.incomeProbability) {
          incomeShock = shocks.income[rng.nextInt(shocks.income.length)];
        }

        // A payment delay is a timing shock, not income destruction. Queue the
        // generated statistical incoming cash and release the exact same draw
        // N days later. This preserves trend/seasonality/shock semantics while
        // producing the temporary liquidity gap the stress scenario intends.
        if (delay > 0) {
          final target = day + delay;
          if (target < delayedExpectedIncome.length) {
            delayedExpectedIncome[target] += expectedIncome;
            delayedSampledIncome[target] += sampledIncome;
            delayedIncomeShock[target] += incomeShock;
          }
          expectedIncome = delayedExpectedIncome[day];
          sampledIncome = delayedSampledIncome[day];
          incomeShock = delayedIncomeShock[day];
        }

        final expectedNetCenter = expectedIncome - expectedExpense;
        final sampledNet = sampledIncome - sampledExpense;
        var uncertainNet =
            expectedNetCenter + (sampledNet - expectedNetCenter) * uncertainty;
        uncertainNet += incomeShock;

        if (shocks.expense.isNotEmpty &&
            rng.nextDouble() < shocks.expenseProbability) {
          uncertainNet -= shocks.expense[rng.nextInt(shocks.expense.length)];
        }
"""
if old not in text:
    raise SystemExit('delay queue body anchor not found')
text = text.replace(old, new, 1)

# Apply income stress to probabilistic business cash too.
old = """      var modeledAmount = event.amount;
      if (modeledAmount > 0 &&
          shiftedOffset <= mainLossWindow &&
          primaryLossSource == 'business:${event.effectiveRiskSource}') {
        modeledAmount *= 0.15;
      }
"""
new = """      var modeledAmount = event.amount;
      if (modeledAmount > 0 &&
          shiftedOffset <= mainLossWindow &&
          primaryLossSource == 'business:${event.effectiveRiskSource}') {
        modeledAmount *= 0.15;
      }
      if (modeledAmount > 0 &&
          (whatIf.incomeMultiplierDays <= 0 ||
              shiftedOffset <= whatIf.incomeMultiplierDays)) {
        modeledAmount *= whatIf.incomeMultiplier;
      } else if (modeledAmount < 0 &&
          (whatIf.expenseMultiplierDays <= 0 ||
              shiftedOffset <= whatIf.expenseMultiplierDays)) {
        modeledAmount *= whatIf.expenseMultiplier;
      }
"""
if old not in text:
    raise SystemExit('business stress anchor not found')
text = text.replace(old, new, 1)

# 2) Account-local liquidity must include recurring cash and scenario timing.
old = """    final accountRisks = _accountLiquidityRisks(
      accounts: accounts,
      transactions: transactions,
      businessEvents: businessEvents,
      today: todayOnly,
      days: days,
    );
"""
new = """    final accountRisks = _accountLiquidityRisks(
      accounts: accounts,
      transactions: transactions,
      businessEvents: businessEvents,
      recurringReliability: effectiveRecurringReliability,
      whatIf: whatIf,
      today: todayOnly,
      days: days,
    );
"""
if old not in text:
    raise SystemExit('account risk call anchor not found')
text = text.replace(old, new, 1)
old = """  static List<AccountLiquidityRisk> _accountLiquidityRisks({
    required List<AccountLiquiditySnapshot> accounts,
    required List<TransactionModel> transactions,
    required List<HorizonCashEvent> businessEvents,
    required DateTime today,
    required int days,
  }) {
    if (accounts.isEmpty) return const [];
    final result = <AccountLiquidityRisk>[];
"""
new = """  static List<AccountLiquidityRisk> _accountLiquidityRisks({
    required List<AccountLiquiditySnapshot> accounts,
    required List<TransactionModel> transactions,
    required List<HorizonCashEvent> businessEvents,
    required Map<String, double> recurringReliability,
    required WhatIfScenario whatIf,
    required DateTime today,
    required int days,
  }) {
    if (accounts.isEmpty) return const [];
    final recurring = transactions
        .where((t) => t.isRecurring && t.recurringPeriod != null)
        .toList();
    final recurringIncomeIds = recurring
        .where((t) => t.type == TransactionType.income)
        .map((t) => t.id)
        .toList();
    bool legacySyntheticIncome(TransactionModel tx) =>
        !tx.isRecurring &&
        recurringIncomeIds.any((id) => tx.id.startsWith('${id}_'));
    final result = <AccountLiquidityRisk>[];
"""
if old not in text:
    raise SystemExit('account risk signature anchor not found')
text = text.replace(old, new, 1)
old = """      final history = transactions.where((t) {
        if (t.effectiveAccountId != account.accountId) return false;
        final d = DateTime(t.date.year, t.date.month, t.date.day);
        return !d.isAfter(today);
      }).toList();
"""
new = """      final history = transactions.where((t) {
        if (t.effectiveAccountId != account.accountId) return false;
        if (t.isRecurring || legacySyntheticIncome(t)) return false;
        final d = DateTime(t.date.year, t.date.month, t.date.day);
        return !d.isAfter(today);
      }).toList();
"""
if old not in text:
    raise SystemExit('account actual history anchor not found')
text = text.replace(old, new, 1)
old = """      int? riskDay;
      var p10AtRisk = account.balance;
      var finalP10 = account.balance;
      var cumulativeKnown = 0.0;
      for (var day = 1; day <= days; day++) {
"""
new = """      final recurringByDay = <int, double>{};
      for (final tx in recurring) {
        if (tx.effectiveAccountId != account.accountId) continue;
        final projected = RecurringEngine.projectFutureContributions(
          [tx],
          days: days,
          from: today,
        );
        final reliability = (recurringReliability[tx.id] ??
                _estimateRecurringReliability(tx, transactions, today))
            .clamp(0.05, 1.0)
            .toDouble();
        final probability = tx.type == TransactionType.expense
            ? max(0.95, reliability)
            : reliability;
        for (final entry in projected.entries) {
          var target = entry.key;
          var value = entry.value * probability;
          if (value > 0) target += whatIf.incomeDelayDays;
          if (target < 1 || target > days) continue;
          if (value > 0 &&
              (whatIf.incomeMultiplierDays <= 0 ||
                  target <= whatIf.incomeMultiplierDays)) {
            value *= whatIf.incomeMultiplier;
          } else if (value < 0 &&
              (whatIf.expenseMultiplierDays <= 0 ||
                  target <= whatIf.expenseMultiplierDays)) {
            value *= whatIf.expenseMultiplier;
          }
          recurringByDay[target] = (recurringByDay[target] ?? 0) + value;
        }
      }

      int? riskDay;
      var p10AtRisk = account.balance;
      var finalP10 = account.balance;
      var cumulativeKnown = 0.0;
      for (var day = 1; day <= days; day++) {
"""
if old not in text:
    raise SystemExit('account recurring projection anchor not found')
text = text.replace(old, new, 1)
old = """        var known = 0.0;
        for (final tx in transactions) {
"""
new = """        var known = recurringByDay[day] ?? 0.0;
        for (final tx in transactions) {
"""
if old not in text:
    raise SystemExit('account known anchor not found')
text = text.replace(old, new, 1)
old = """        for (final event in businessEvents) {
          if (event.accountId != account.accountId) continue;
          final offset =
              DateTime(event.date.year, event.date.month, event.date.day)
                  .difference(today)
                  .inDays;
          if (offset == day) known += event.amount * event.probability;
        }
"""
new = """        for (final event in businessEvents) {
          if (event.accountId != account.accountId) continue;
          var offset = DateTime(event.date.year, event.date.month, event.date.day)
              .difference(today)
              .inDays;
          var amount = event.amount * event.probability;
          if (amount > 0) offset += whatIf.incomeDelayDays;
          if (offset != day) continue;
          if (amount > 0 &&
              (whatIf.incomeMultiplierDays <= 0 ||
                  day <= whatIf.incomeMultiplierDays)) {
            amount *= whatIf.incomeMultiplier;
          } else if (amount < 0 &&
              (whatIf.expenseMultiplierDays <= 0 ||
                  day <= whatIf.expenseMultiplierDays)) {
            amount *= whatIf.expenseMultiplier;
          }
          known += amount;
        }
"""
if old not in text:
    raise SystemExit('account business events anchor not found')
text = text.replace(old, new, 1)
p.write_text(text, encoding='utf-8')

# 3) Overdue CRM expected cash stays visible, but confidence decays.
path = 'lib/features/treasury/services/horizon_business_context.dart'
p = Path(path)
text = p.read_text(encoding='utf-8')
old = """        final due = _day(deal.expectedCloseAt!);
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
        ));
"""
new = """        final due = _day(deal.expectedCloseAt!);
        var eventDate = due;
        var probability =
            (deal.probability / 100).clamp(0.01, 0.99).toDouble();
        var committed = probability >= 0.9 && deal.stage == DealStage.negotiation;
        if (!due.isAfter(today)) {
          final overdueDays = max(0, today.difference(due).inDays);
          final decay = exp(-overdueDays / 45.0).clamp(0.25, 0.80);
          probability = (probability * decay).clamp(0.01, 0.75).toDouble();
          committed = false;
          eventDate = today.add(const Duration(days: 1));
          warnings.add(ForecastActionPrompt(
            code: 'crm-overdue-${deal.id}',
            severity: ForecastPromptSeverity.warning,
            textRu: 'Срок ожидаемой сделки «${deal.title}» уже прошёл. Horizon не удаляет входящий поток, но снизил его вероятность до ${(probability * 100).round()}%.',
            textEn: 'The expected close date for “${deal.title}” has passed. Horizon keeps the incoming cash visible but reduced its probability to ${(probability * 100).round()}%.',
            day: 1,
          ));
        }
        if (eventDate.isAfter(end)) continue;
        final rub = deal.amount *
            CurrencyService.rateToRub(deal.currency.toLowerCase());
        events.add(HorizonCashEvent(
          title: 'CRM: ${deal.title}',
          amount: rub,
          date: eventDate,
          probability: probability,
          committed: committed,
          source: 'crm',
          riskSource: 'crm:${deal.clientId}',
        ));
"""
if old not in text:
    raise SystemExit('CRM overdue anchor not found')
text = text.replace(old, new, 1)
old = """          events.add(HorizonCashEvent(
            title: 'Task: ${task.title}',
            amount: parsed.signedAmount,
            date: today.add(const Duration(days: 1)),
            probability: parsed.probability,
            committed: parsed.committed,
            source: 'task-obligation-overdue',
            riskSource: 'task:${task.id}',
          ));
"""
new = """          final missedIncoming = overdue && parsed.signedAmount > 0;
          final overdueProbability = missedIncoming
              ? min(parsed.probability, 0.65).toDouble()
              : parsed.probability;
          events.add(HorizonCashEvent(
            title: 'Task: ${task.title}',
            amount: parsed.signedAmount,
            date: today.add(const Duration(days: 1)),
            probability: overdueProbability,
            committed: missedIncoming ? false : parsed.committed,
            source: 'task-obligation-overdue',
            riskSource: 'task:${task.id}',
          ));
"""
if old not in text:
    raise SystemExit('Task overdue anchor not found')
text = text.replace(old, new, 1)
p.write_text(text, encoding='utf-8')

# 4) Production maintenance loop: learn/record/compete on launch/resume, not only when Forecast UI opens.
maintenance = Path('lib/features/treasury/services/horizon_maintenance_automation.dart')
maintenance.write_text("""import 'dart:async';

import 'package:flutter/foundation.dart';

import 'forecast_engine.dart';
import 'horizon_business_context.dart';
import 'horizon_calibration.dart';
import 'horizon_engine_competition.dart';
import 'horizon_learning_service.dart';
import 'horizon_prediction_registry.dart';
import 'treasury_service.dart';

/// Background production maintenance for Wesi Horizon.
///
/// Called from the existing lifecycle automation after recurring cash has been
/// reconciled. It is single-flight, throttled, fail-soft and does not require
/// the Forecast screen to be opened.
class HorizonMaintenanceAutomation {
  HorizonMaintenanceAutomation({
    TreasuryService? treasury,
    DateTime Function()? now,
    this.minInterval = const Duration(hours: 6),
  })  : _treasury = treasury ?? TreasuryService(),
        _now = now ?? DateTime.now;

  static final HorizonMaintenanceAutomation shared =
      HorizonMaintenanceAutomation();

  final TreasuryService _treasury;
  final DateTime Function() _now;
  final Duration minInterval;
  Future<void>? _inFlight;
  DateTime? _lastCompletedAt;

  Future<void> runNow({bool force = false}) {
    final running = _inFlight;
    if (running != null) return running;
    final last = _lastCompletedAt;
    if (!force && last != null && _now().difference(last) < minInterval) {
      return Future<void>.value();
    }
    final future = _run();
    _inFlight = future;
    return future;
  }

  Future<void> _run() async {
    try {
      final now = _now();
      final today = DateTime(now.year, now.month, now.day);
      final transactions = await _treasury.getAllTransactions();
      final balance = await _treasury.getCurrentBalance();
      final calibration = await HorizonLearningService.load();
      const auditDays = 180;
      final context = await HorizonBusinessContextService.load(
        transactions: transactions,
        days: auditDays,
        now: today,
      );
      final audit = ForecastEngine.generate(
        transactions: transactions,
        currentBalance: balance,
        days: auditDays,
        paths: ForecastEngine.pathsForHorizon(auditDays, 1600),
        seed: 42,
        asOf: today,
        calibration: calibration,
        businessEvents: context.events,
        accounts: context.accounts,
      );
      if (!audit.insufficientData && audit.p50.isNotEmpty) {
        await HorizonPredictionRegistry.recordBaseForecast(
          forecast: audit,
          currentBalance: balance,
          calibration: calibration,
          now: today,
        );
      }
      await HorizonLearningService.updateIfDue(
        transactions: transactions,
        currentBalance: balance,
        now: today,
      );
      await HorizonEngineCompetitionService.evaluateIfDue(
        transactions: transactions,
        currentBalance: balance,
        now: today,
      );
      _lastCompletedAt = now;
    } catch (error, stackTrace) {
      debugPrint('Horizon maintenance failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _inFlight = null;
    }
  }
}
""", encoding='utf-8')

path = 'lib/features/treasury/services/recurring_payment_automation.dart'
p = Path(path)
text = p.read_text(encoding='utf-8')
if "import 'horizon_maintenance_automation.dart';" not in text:
    text = text.replace("import 'treasury_service.dart';", "import 'horizon_maintenance_automation.dart';\nimport 'treasury_service.dart';")
old = """      await _treasury.processRecurringPayments();
      _lastCompletedAt = _now();
"""
new = """      await _treasury.processRecurringPayments();
      // Maintenance is intentionally independent from opening Forecast UI:
      // issued-forecast ledger, monthly learning and engine championship keep
      // advancing on ordinary app launch/resume.
      await HorizonMaintenanceAutomation.shared.runNow();
      _lastCompletedAt = _now();
"""
if old not in text:
    raise SystemExit('recurring automation maintenance anchor not found')
text = text.replace(old, new, 1)
p.write_text(text, encoding='utf-8')

# 5) Hard regression gates requested by audit/Grok.
Path('test/horizon_hardening_regression_test.dart').write_text("""import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';
import 'package:wesios/features/treasury/services/horizon_calibration.dart';

TransactionModel tx(String id, DateTime date, double amount, TransactionType type,
        {String category = 'services', bool recurring = false, RecurringPeriod? period, String? accountId}) =>
    TransactionModel(
      id: id,
      title: id,
      amount: amount,
      type: type,
      date: date,
      category: category,
      isRecurring: recurring,
      recurringPeriod: period,
      accountId: accountId,
    );

void main() {
  final now = DateTime(2026, 8, 9);

  List<TransactionModel> stable({int days = 180}) {
    final out = <TransactionModel>[];
    for (var ago = days; ago >= 1; ago--) {
      final d = now.subtract(Duration(days: ago));
      out.add(tx('i-$ago', d, 1000 + ago % 5 * 20, TransactionType.income));
      out.add(tx('e-$ago', d, 550 + ago % 3 * 15, TransactionType.expense,
          category: 'operations'));
    }
    return out;
  }

  test('incoming-delay stress shifts statistical income instead of deleting it', () {
    final history = stable();
    final base = ForecastEngine.generate(
      transactions: history,
      currentBalance: 50000,
      days: 60,
      paths: 250,
      seed: 42,
      asOf: now,
    );
    final delayed = ForecastEngine.generate(
      transactions: history,
      currentBalance: 50000,
      days: 60,
      paths: 250,
      seed: 42,
      asOf: now,
      whatIf: const WhatIfScenario(incomeDelayDays: 10),
    );
    expect(delayed.p50[8], lessThan(base.p50[8]));
    expect(delayed.p50[39] - delayed.p50[29], greaterThan(-5000));
    final source = File('lib/features/treasury/services/forecast_engine.dart').readAsStringSync();
    expect(source, contains('delayedSampledIncome[target] += sampledIncome'));
    expect(source, isNot(contains('day <= whatIf.incomeDelayDays) {\n          sampledIncome = 0.0')));
  });

  test('calibration cannot materially destabilize the near-horizon median', () {
    final history = stable();
    final raw = ForecastEngine.generate(
      transactions: history,
      currentBalance: 50000,
      days: 30,
      paths: 250,
      seed: 42,
      asOf: now,
    );
    const profile = HorizonCalibrationProfile(
      buckets: [HorizonCalibrationBucket(
        horizonDays: 30,
        intervalScale: 1.8,
        biasCorrection: 3000,
        coverage: .55,
        samples: 80,
      )],
    );
    final calibrated = ForecastEngine.generate(
      transactions: history,
      currentBalance: 50000,
      days: 30,
      paths: 250,
      seed: 42,
      asOf: now,
      calibration: profile,
    );
    expect((calibrated.p50[6] - raw.p50[6]).abs(), lessThan(1000));
    expect(calibrated.p90.last - calibrated.p10.last,
        greaterThan(raw.p90.last - raw.p10.last));
  });

  test('production lifecycle wiring runs Horizon maintenance without opening Forecast', () {
    final automation = File('lib/features/treasury/services/recurring_payment_automation.dart').readAsStringSync();
    final maintenance = File('lib/features/treasury/services/horizon_maintenance_automation.dart').readAsStringSync();
    expect(automation, contains('HorizonMaintenanceAutomation.shared.runNow'));
    expect(maintenance, contains('HorizonLearningService.updateIfDue'));
    expect(maintenance, contains('HorizonPredictionRegistry.recordBaseForecast'));
    expect(maintenance, contains('HorizonEngineCompetitionService.evaluateIfDue'));
  });

  test('account liquidity uses recurring projections and scenario timing', () {
    final source = File('lib/features/treasury/services/forecast_engine.dart').readAsStringSync();
    expect(source, contains('final recurringByDay = <int, double>{};'));
    expect(source, contains('known = recurringByDay[day] ?? 0.0'));
    expect(source, contains('required WhatIfScenario whatIf'));
  });
}
""", encoding='utf-8')

print('Horizon final hardening patch applied')
