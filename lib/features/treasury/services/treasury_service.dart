import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/transaction_model.dart';
import 'account_service.dart';
import 'anomaly_engine.dart';
import 'calendar_days.dart';
import 'forecast_engine.dart';
import 'forecast_runner.dart';
import 'horizon_behavior_monitor.dart';
import 'horizon_business_context.dart';
import 'horizon_calibration.dart';
import 'horizon_explainability.dart';
import 'horizon_engine_competition.dart';
import 'horizon_learning_service.dart';
import 'horizon_prediction_registry.dart';
import 'horizon_scenarios.dart';
import 'recurring_engine.dart';

/// Wesi Treasury Service — управление финансами, аномалиями, прогнозами.
///
/// ForecastEngine remains the pure mathematical core. This service is the
/// company-level orchestration layer: it joins Treasury with CRM, Tasks,
/// Audio Vault contracts, account liquidity, persisted calibration and the
/// default scenario/decision package.
class TreasuryService {
  static const String _boxName = 'wesios_treasury';
  Box<TransactionModel>? _box;

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static bool _learningInFlight = false;
  static bool _competitionInFlight = false;
  static bool _predictionAuditInFlight = false;
  static DateTime? _predictionAuditDay;

  Future<Box<TransactionModel>> get _treasuryBox async {
    _box ??= await Hive.openBox<TransactionModel>(_boxName);
    return _box!;
  }

  // ========== CRUD ==========

  Future<void> addTransaction(TransactionModel tx) async {
    final box = await _treasuryBox;
    await box.put(tx.id, tx);
    revision.value++;
  }

  Future<void> deleteTransaction(String id) async {
    final box = await _treasuryBox;
    await box.delete(id);
    revision.value++;
  }

  Future<List<TransactionModel>> getAllTransactions() async {
    final box = await _treasuryBox;
    return box.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<List<TransactionModel>> getTransactionsByType(
      TransactionType type) async {
    final all = await getAllTransactions();
    return all.where((t) => t.type == type).toList();
  }

  // ========== BALANCE ==========

  Future<double> getCurrentBalance() async {
    final all = await getAllTransactions();
    try {
      final summaries = await AccountService.summaries(all);
      return summaries.fold<double>(0, (sum, item) => sum + item.balance);
    } catch (_) {
      double balance = 0;
      for (final tx in all) {
        balance += tx.type == TransactionType.income ? tx.amount : -tx.amount;
      }
      return balance;
    }
  }

  Future<Map<String, double>> getBalanceBreakdown() async {
    final now = DateTime.now();
    final all = (await getAllTransactions())
        .where((tx) => !tx.date.isAfter(now))
        .toList();
    double income = 0, expense = 0;
    for (final tx in all) {
      if (tx.type == TransactionType.income) {
        income += tx.amount;
      } else {
        expense += tx.amount;
      }
    }
    return {'income': income, 'expense': expense, 'net': income - expense};
  }

  // ========== ANOMALY DETECTION ==========

  Future<List<TransactionModel>> detectAnomalies() async {
    final now = DateTime.now();
    final actual = (await getAllTransactions())
        .where((tx) => !tx.date.isAfter(now))
        .toList();
    return AnomalyEngine.detect(actual);
  }

  // ========== RECURRING PAYMENTS ==========

  Future<List<TransactionModel>> getRecurringPayments() async {
    final all = await getAllTransactions();
    return all.where((t) => t.isRecurring).toList();
  }

  Future<void> processRecurringPayments() async {
    final recurring = await getRecurringPayments();
    final now = DateTime.now();

    for (final tx in recurring) {
      final period = tx.recurringPeriod;
      if (period == null) continue;

      // Каждое наступление считается от исходной даты, а не от предыдущего
      // платежа. Шагами месячная дата съезжает и не возвращается: аренда
      // 31 января проводится 28 февраля, следующая — 28 марта, и дальше
      // навсегда 28-е, хотя человек платит 31-го.
      final anchorDate = tx.recurringAnchorDate;
      var lastDue = tx.date;
      var index = RecurringEngine.firstIndexAfter(anchorDate, period, tx.date);
      var guard = 0;
      // Обрабатываем все просроченные периоды за один вызов — иначе платёж
      // «застрянет» на первом же пропущенном разе.
      while (guard < 366) {
        final due = RecurringEngine.occurrence(anchorDate, period, index);
        if (due.isAfter(now)) break;
        if (tx.type == TransactionType.expense) {
          await addTransaction(TransactionModel(
            id: '${tx.id}_${due.millisecondsSinceEpoch}',
            title: tx.title,
            amount: tx.amount,
            type: tx.type,
            date: due,
            category: tx.category,
            description:
                tx.description == null ? null : 'Recurring: ${tx.description}',
            isRecurring: false,
            accountId: tx.accountId,
          ));
        }
        // Поступление НЕ проводится автоматически как полученные деньги.
        // Реальный приход вносится отдельно и служит доказательством того,
        // что платёж действительно исполнен.
        lastDue = due;
        index++;
        guard++;
      }
      if (guard > 0) {
        // Дата записи отмечает последний проведённый платёж, а якорь
        // сохраняется явно — иначе он потеряется вместе со сдвигом даты.
        await addTransaction(
          tx.copyWith(date: lastDue, recurringAnchor: anchorDate),
        );
      }
    }
  }

  // ========== WESI HORIZON ==========

  /// Баланс на конец дня [day] — то есть без операций, датированных позже.
  ///
  /// [getCurrentBalance] складывает вообще всё, включая операции, которые
  /// человек внёс наперёд: аванс, назначенный на следующую неделю, поднимал
  /// сегодняшний баланс, а в свою дату уже ничего не происходило. Прогноз
  /// от такого старта завышен ровно на сумму будущих операций.
  static double balanceOnDay(
    DateTime day,
    List<TransactionModel> transactions,
    double totalBalance,
  ) {
    final cutoff = dateOnly(day);
    var later = 0.0;
    for (final tx in transactions) {
      if (dateOnly(tx.date).isAfter(cutoff)) {
        later += tx.type == TransactionType.income ? tx.amount : -tx.amount;
      }
    }
    return totalBalance - later;
  }

  Future<ForecastResult> generateForecast({
    int days = 30,
    WhatIfScenario whatIf = WhatIfScenario.none,
    double annualDiscountRate = 0.0,
  }) async {
    final all = await getAllTransactions();
    // Старт прогноза — баланс на конец сегодняшнего дня. `getCurrentBalance`
    // складывает вообще всё, включая операции, датированные будущим: аванс,
    // назначенный на следующую неделю, поднимал сегодняшний баланс, а в свою
    // дату уже ничего не происходило — прогноз стартовал завышенным.
    final balance =
        balanceOnDay(DateTime.now(), all, await getCurrentBalance());

    // Rendering uses the last verified profile immediately. Monthly learning,
    // engine competition and the production forecast ledger are background
    // jobs and never hold the forecast screen hostage.
    final calibration = await HorizonLearningService.load();
    _kickLearning(all, balance);
    _kickPredictionAudit(all, balance, calibration);

    final context = await HorizonBusinessContextService.load(
      transactions: all,
      days: days,
    );

    // Расчёт уходит с потока интерфейса: Monte-Carlo — это `пути × дни`
    // шагов плюс сортировка на каждый день, и раньше всё это выполнялось
    // прямо в UI-потоке (метод `async`, но работа синхронная — `await`
    // перед синхронным кодом никуда его не переносит).
    Future<ForecastResult> core(WhatIfScenario scenario) =>
        runForecastOffThread(ForecastRequest(
          transactions: all,
          currentBalance: balance,
          days: days,
          whatIf: scenario,
          annualDiscountRate: annualDiscountRate,
          calibration: calibration,
          businessEvents: context.events,
          accounts: context.accounts,
        ));

    // Default scenario package must always be anchored to the unmodified base,
    // not silently inherit an ad-hoc What-If currently open in the UI.
    final base = await core(WhatIfScenario.none);
    final active = whatIf.isEmpty ? base : await core(whatIf);

    final scenarios = await HorizonScenarioService.buildDefaultPackage(
      base: base,
      transactions: all,
      currentBalance: balance,
      days: days,
      calibration: calibration,
      businessEvents: context.events,
      accounts: context.accounts,
    );

    final prompts = <ForecastActionPrompt>[
      ...active.actionPrompts,
      ...context.warnings,
      ...HorizonBehaviorMonitor.analyze(transactions: all),
    ];
    final withDecisions = active.copyWith(
      scenarioSummaries: scenarios,
      actionPrompts: prompts,
      whatIfRiskDelta: whatIf.isEmpty
          ? null
          : HorizonScenarioService.riskDelta(base: base, scenario: active),
      clearWhatIfRiskDelta: whatIf.isEmpty,
    );

    final explained = withDecisions.copyWith(
      explanations: HorizonExplainabilityService.build(
        forecast: withDecisions,
        transactions: all,
        businessEvents: context.events,
      ),
    );

    // External engines may take seconds and are optional/Windows-only.
    _kickCompetition(all, balance);

    return explained;
  }

  static void _kickLearning(
    List<TransactionModel> transactions,
    double currentBalance,
  ) {
    if (_learningInFlight) return;
    _learningInFlight = true;
    unawaited(HorizonLearningService.updateIfDue(
      transactions: transactions,
      currentBalance: currentBalance,
    ).whenComplete(() => _learningInFlight = false));
  }

  static void _kickPredictionAudit(
    List<TransactionModel> transactions,
    double currentBalance,
    HorizonCalibrationProfile calibration,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final alreadyRan = _predictionAuditDay != null &&
        _predictionAuditDay!.year == today.year &&
        _predictionAuditDay!.month == today.month &&
        _predictionAuditDay!.day == today.day;
    if (_predictionAuditInFlight || alreadyRan) return;
    _predictionAuditInFlight = true;
    _predictionAuditDay = today;

    unawaited(() async {
      try {
        const auditDays = 180;
        final context = await HorizonBusinessContextService.load(
          transactions: transactions,
          days: auditDays,
          now: today,
        );
        final audit = ForecastEngine.generate(
          transactions: transactions,
          currentBalance: currentBalance,
          days: auditDays,
          paths: ForecastEngine.pathsForHorizon(auditDays, 1600),
          seed: 42,
          asOf: today,
          calibration: calibration,
          businessEvents: context.events,
          accounts: context.accounts,
        );
        await HorizonPredictionRegistry.recordBaseForecast(
          forecast: audit,
          currentBalance: currentBalance,
          calibration: calibration,
          now: today,
        );
      } catch (_) {
        // Audit collection is strictly fail-soft.
      }
    }()
        .whenComplete(() => _predictionAuditInFlight = false));
  }

  static void _kickCompetition(
    List<TransactionModel> transactions,
    double currentBalance,
  ) {
    if (_competitionInFlight) return;
    _competitionInFlight = true;
    unawaited(HorizonEngineCompetitionService.evaluateIfDue(
      transactions: transactions,
      currentBalance: currentBalance,
    ).whenComplete(() => _competitionInFlight = false));
  }

  // ========== DEMO DATA (never auto-called by forecast screen) ==========

  Future<void> generateDemoData() async {
    final box = await _treasuryBox;
    if (box.isNotEmpty) return;

    final now = DateTime.now();
    final random = Random();
    final categories = [
      'Software',
      'Marketing',
      'Office',
      'Salaries',
      'Freelance',
      'Investments'
    ];

    for (int i = 60; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      if (random.nextDouble() > 0.3) {
        await addTransaction(TransactionModel(
          id: 'inc_$i',
          title: 'Income #$i',
          amount: 1000 + random.nextInt(4000).toDouble(),
          type: TransactionType.income,
          date: date,
          category: categories[random.nextInt(categories.length)],
        ));
      }
      if (random.nextDouble() > 0.2) {
        await addTransaction(TransactionModel(
          id: 'exp_$i',
          title: 'Expense #$i',
          amount: 100 + random.nextInt(900).toDouble(),
          type: TransactionType.expense,
          date: date,
          category: categories[random.nextInt(categories.length)],
        ));
      }
    }

    await addTransaction(TransactionModel(
      id: 'anomaly_1',
      title: 'Emergency Server Repair',
      amount: 15000,
      type: TransactionType.expense,
      date: now.subtract(const Duration(days: 5)),
      category: 'Infrastructure',
      isAnomaly: true,
      zScore: 3.2,
    ));

    await addTransaction(TransactionModel(
      id: 'recurring_salary',
      title: 'Monthly Salary',
      amount: 5000,
      type: TransactionType.expense,
      date: now.subtract(const Duration(days: 15)),
      category: 'Salaries',
      isRecurring: true,
      recurringPeriod: RecurringPeriod.monthly,
    ));
  }
}
