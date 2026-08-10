import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../organizations/models/organization_access_grant.dart';
import '../../organizations/services/organization_access_service.dart';
import '../../organizations/services/organization_context.dart';
import '../../organizations/services/organization_service.dart';
import '../../organizations/services/transaction_audit_service.dart';
import '../../team/services/team_service.dart';
import '../models/transaction_model.dart';
import 'account_service.dart';
import 'anomaly_engine.dart';
import 'forecast_engine.dart';
import 'horizon_behavior_monitor.dart';
import 'horizon_business_context.dart';
import 'horizon_calibration.dart';
import 'horizon_explainability.dart';
import 'horizon_engine_competition.dart';
import 'horizon_learning_service.dart';
import 'horizon_prediction_registry.dart';
import 'horizon_scenarios.dart';
import 'recurring_engine.dart';

/// Wesi Treasury orchestration. Every public read is scoped by the current
/// organization context; raw reads are explicit and reserved for migration,
/// inter-org posting and administrative/audit services.
class TreasuryService {
  static const String _boxName = 'wesios_treasury';
  Box<TransactionModel>? _box;

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static bool _learningInFlight = false;
  static bool _competitionInFlight = false;
  static final Set<String> _predictionAuditKeys = <String>{};
  static final Set<String> _predictionAuditInFlight = <String>{};

  Future<Box<TransactionModel>> get _treasuryBox async {
    _box ??= await Hive.openBox<TransactionModel>(_boxName);
    return _box!;
  }

  // ========== CRUD ==========

  Future<void> addTransaction(TransactionModel tx) async {
    final orgId = tx.organizationId ?? OrganizationContext.currentOrganizationId;
    final org = await OrganizationService.byId(orgId);
    if (org == null || org.archived) {
      throw StateError('transaction organization is unavailable');
    }
    if (TeamService.current != null &&
        !await OrganizationAccessService.can(
          orgId,
          OrganizationPermissions.createTransactions,
        )) {
      throw StateError('create_transactions permission required');
    }

    if (tx.accountId != null) {
      final account = await AccountService.byId(tx.accountId!);
      if (account == null || account.effectiveOrganizationId != orgId) {
        throw StateError('transaction account belongs to another organization');
      }
    }

    final box = await _treasuryBox;
    final before = box.get(tx.id);
    if (before != null && TeamService.current != null) {
      if (!await OrganizationAccessService.can(
        before.effectiveOrganizationId,
        OrganizationPermissions.editTransactions,
      )) {
        throw StateError('edit_transactions permission required');
      }
    }

    final actor = TeamService.current?.id;
    final normalized = tx.copyWith(
      organizationId: orgId,
      createdBy: tx.createdBy ?? actor,
      createdByEmployeeId: tx.createdByEmployeeId ?? actor,
      updatedBy: before == null ? tx.updatedBy : (actor ?? tx.updatedBy),
      updatedAt: before == null ? tx.updatedAt : DateTime.now(),
    );
    await box.put(normalized.id, normalized);
    if (before != null) {
      await TransactionAuditService.record(
        transactionId: normalized.id,
        before: before,
        after: normalized,
        reason: 'update',
      );
    }
    revision.value++;
  }

  Future<void> updateTransaction(
    TransactionModel tx, {
    String? reason,
  }) async {
    final box = await _treasuryBox;
    final before = box.get(tx.id);
    if (before == null) throw StateError('transaction does not exist');
    if (TeamService.current != null &&
        !await OrganizationAccessService.can(
          before.effectiveOrganizationId,
          OrganizationPermissions.editTransactions,
        )) {
      throw StateError('edit_transactions permission required');
    }
    final actor = TeamService.current?.id;
    final orgId = tx.organizationId ?? before.effectiveOrganizationId;
    if (tx.accountId != null) {
      final account = await AccountService.byId(tx.accountId!);
      if (account == null || account.effectiveOrganizationId != orgId) {
        throw StateError('transaction account belongs to another organization');
      }
    }
    final next = tx.copyWith(
      organizationId: orgId,
      updatedBy: actor ?? tx.updatedBy,
      updatedAt: DateTime.now(),
    );
    await box.put(next.id, next);
    await TransactionAuditService.record(
      transactionId: next.id,
      before: before,
      after: next,
      reason: reason ?? 'update',
    );
    revision.value++;
  }

  Future<void> deleteTransaction(
    String id, {
    String? reason,
    bool allowInterOrg = false,
  }) async {
    final box = await _treasuryBox;
    final before = box.get(id);
    if (before == null) return;
    if (before.interOrgTransferId != null && !allowInterOrg) {
      throw StateError('inter-org transaction must be cancelled as a transfer');
    }
    if (TeamService.current != null &&
        !await OrganizationAccessService.can(
          before.effectiveOrganizationId,
          OrganizationPermissions.editTransactions,
        )) {
      throw StateError('edit_transactions permission required');
    }
    await TransactionAuditService.record(
      transactionId: id,
      before: before,
      after: null,
      reason: reason ?? 'delete',
    );
    await box.delete(id);
    revision.value++;
  }

  Future<List<TransactionModel>> getAllTransactionsRaw() async {
    final box = await _treasuryBox;
    return box.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<List<TransactionModel>> getAllTransactions() async {
    final ids = await OrganizationContext.effectiveOrganizationIds();
    final all = await getAllTransactionsRaw();
    return all.where((t) => ids.contains(t.effectiveOrganizationId)).toList();
  }

  Future<List<TransactionModel>> getTransactionsByType(TransactionType type) async {
    final all = await getAllTransactions();
    return all.where((t) => t.type == type).toList();
  }

  /// For subtree forecast/analytics, transfers whose both sides are inside the
  /// selected subtree are eliminated from consolidated cash flow. They remain
  /// visible in operation history and in each organization's local forecast.
  static List<TransactionModel> eliminateInternalTransfers(
    List<TransactionModel> transactions,
  ) {
    final byTransfer = <String, List<TransactionModel>>{};
    for (final tx in transactions) {
      final id = tx.interOrgTransferId;
      if (id == null) continue;
      byTransfer.putIfAbsent(id, () => <TransactionModel>[]).add(tx);
    }
    final internalIds = <String>{};
    for (final entry in byTransfer.entries) {
      final organizations = entry.value.map((e) => e.effectiveOrganizationId).toSet();
      if (organizations.length >= 2) internalIds.add(entry.key);
    }
    if (internalIds.isEmpty) return transactions;
    return transactions
        .where((tx) =>
            tx.interOrgTransferId == null ||
            !internalIds.contains(tx.interOrgTransferId))
        .toList();
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
        if (tx.isRecurring) continue;
        balance += tx.type == TransactionType.income ? tx.amount : -tx.amount;
      }
      return balance;
    }
  }

  Future<Map<String, double>> getBalanceBreakdown() async {
    final now = DateTime.now();
    final all = (await getAllTransactions())
        .where((tx) => !tx.date.isAfter(now) && !tx.isRecurring)
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
      var anchor = tx;
      var guard = 0;
      while (RecurringEngine.isDue(anchor, now) && guard < 366) {
        final due = RecurringEngine.advance(anchor.date, period);
        if (tx.type == TransactionType.expense) {
          await addTransaction(TransactionModel(
            id: '${tx.id}_${due.millisecondsSinceEpoch}',
            title: tx.title,
            amount: tx.amount,
            type: tx.type,
            date: due,
            category: tx.category,
            description: tx.description == null
                ? null
                : 'Recurring: ${tx.description}',
            isRecurring: false,
            accountId: tx.accountId,
            organizationId: tx.effectiveOrganizationId,
            projectId: tx.projectId,
            counterpartyId: tx.counterpartyId,
            source: TransactionSource.recurring,
            ownerEmployeeId: tx.ownerEmployeeId,
            createdBy: tx.createdBy,
            createdByEmployeeId: tx.createdByEmployeeId,
          ));
        }
        // Recurring income remains an expectation until a real receipt exists.
        anchor = anchor.copyWith(date: due, updatedAt: DateTime.now());
        guard++;
      }
      if (guard > 0) await addTransaction(anchor);
    }
  }

  // ========== WESI HORIZON ==========

  Future<ForecastResult> generateForecast({
    int days = 30,
    WhatIfScenario whatIf = WhatIfScenario.none,
    double annualDiscountRate = 0.0,
  }) async {
    final scoped = await getAllTransactions();
    final all = OrganizationContext.scope == OrganizationScope.subtree
        ? eliminateInternalTransfers(scoped)
        : scoped;
    final balance = await getCurrentBalance();

    final calibration = await HorizonLearningService.load();
    _kickLearning(all, balance);
    _kickPredictionAudit(all, balance, calibration);

    final context = await HorizonBusinessContextService.load(
      transactions: all,
      days: days,
    );

    ForecastResult core(WhatIfScenario scenario) => ForecastEngine.generate(
          transactions: all,
          currentBalance: balance,
          days: days,
          whatIf: scenario,
          annualDiscountRate: annualDiscountRate,
          calibration: calibration,
          businessEvents: context.events,
          accounts: context.accounts,
        );

    final base = core(WhatIfScenario.none);
    final active = whatIf.isEmpty ? base : core(whatIf);

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
    final key = '${OrganizationContext.currentOrganizationId}:${OrganizationContext.scope.name}:${today.toIso8601String()}';
    if (_predictionAuditInFlight.contains(key) || _predictionAuditKeys.contains(key)) return;
    _predictionAuditInFlight.add(key);

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
          organizationId: OrganizationContext.currentOrganizationId,
          organizationScope: OrganizationContext.scope.name,
        );
        _predictionAuditKeys.add(key);
      } catch (_) {
        // Audit collection is strictly fail-soft.
      }
    }().whenComplete(() => _predictionAuditInFlight.remove(key)));
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
    final existing = await getAllTransactions();
    if (existing.isNotEmpty) return;
    final now = DateTime.now();
    final random = Random();
    final categories = [
      'Software', 'Marketing', 'Office', 'Salaries', 'Freelance', 'Investments'
    ];
    for (int i = 60; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      if (random.nextDouble() > 0.3) {
        await addTransaction(TransactionModel(
          id: 'inc_${OrganizationContext.currentOrganizationId}_$i',
          title: 'Income #$i',
          amount: 1000 + random.nextInt(4000).toDouble(),
          type: TransactionType.income,
          date: date,
          category: categories[random.nextInt(categories.length)],
        ));
      }
      if (random.nextDouble() > 0.2) {
        await addTransaction(TransactionModel(
          id: 'exp_${OrganizationContext.currentOrganizationId}_$i',
          title: 'Expense #$i',
          amount: 100 + random.nextInt(900).toDouble(),
          type: TransactionType.expense,
          date: date,
          category: categories[random.nextInt(categories.length)],
        ));
      }
    }
  }
}
