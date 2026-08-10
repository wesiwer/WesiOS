import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/services/currency_service.dart';
import '../../organizations/models/organization_access_grant.dart';
import '../../organizations/services/organization_access_service.dart';
import '../../organizations/services/organization_context.dart';
import '../../organizations/services/organization_service.dart';
import '../../organizations/services/transaction_audit_service.dart';
import '../../team/services/team_service.dart';
import '../models/account_model.dart';
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

/// Wesi Treasury orchestration. `TransactionModel.amount` is the canonical
/// Wesi reporting amount (RUB in org-v1). Original/local/base amounts are
/// frozen as metadata so mixed-currency rows are never summed as raw doubles.
class TreasuryService {
  static const String _boxName = 'wesios_treasury';
  Box<TransactionModel>? _box;

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static final Set<String> _learningInFlight = <String>{};
  static final Set<String> _competitionInFlight = <String>{};
  static final Set<String> _predictionAuditKeys = <String>{};
  static final Set<String> _predictionAuditInFlight = <String>{};

  Future<Box<TransactionModel>> get _treasuryBox async {
    _box ??= await Hive.openBox<TransactionModel>(_boxName);
    return _box!;
  }

  Future<void> _require(String orgId, String permission) async {
    if (TeamService.current != null &&
        !await OrganizationAccessService.can(orgId, permission)) {
      throw StateError('$permission permission required');
    }
  }

  Future<({OrganizationModel org, AccountModel account})> _resolveOwnership(
    String orgId,
    String? accountId,
  ) async {
    final org = await OrganizationService.byId(orgId);
    if (org == null || org.archived) {
      throw StateError('transaction organization is unavailable');
    }
    final account = accountId == null
        ? await AccountService.ensureMain(organizationId: orgId)
        : await AccountService.byId(accountId);
    if (account == null ||
        account.archived ||
        account.effectiveOrganizationId != orgId) {
      throw StateError('transaction account belongs to another organization');
    }
    return (org: org, account: account);
  }

  TransactionModel _normalizeMoney(
    TransactionModel tx,
    OrganizationModel org,
    AccountModel account,
  ) {
    final originalCurrency = tx.originalCurrency.trim().isEmpty
        ? 'RUB'
        : tx.originalCurrency.toUpperCase();
    final originalRate = CurrencyService.rateToRub(originalCurrency.toLowerCase());
    final originalAmount = tx.originalAmount ??
        (originalCurrency == 'RUB' || originalRate == 0
            ? tx.amount
            : tx.amount / originalRate);
    final baseRate = CurrencyService.rateToRub(org.baseCurrency.toLowerCase());
    final baseAmount = tx.organizationBaseAmount ??
        (baseRate == 0 ? tx.amount : tx.amount / baseRate);
    final rate = originalAmount == 0
        ? (originalCurrency == 'RUB' ? 1.0 : originalRate)
        : tx.amount / originalAmount;
    return tx.copyWith(
      accountId: account.id,
      organizationId: org.id,
      originalAmount: originalAmount,
      originalCurrency: originalCurrency,
      organizationBaseAmount: baseAmount,
      organizationBaseCurrency: org.baseCurrency,
      fxRateToReporting: rate.isFinite ? rate : 1.0,
      fxRateAt: tx.fxRateAt ?? tx.date,
      fxSource: tx.fxSource == 'legacy' && originalCurrency != 'RUB'
          ? 'CurrencyService'
          : tx.fxSource,
    );
  }

  // ========== CRUD ==========

  Future<void> addTransaction(TransactionModel tx) async {
    final orgId = tx.organizationId ?? OrganizationContext.currentOrganizationId;
    final ownership = await _resolveOwnership(orgId, tx.accountId);
    await _require(orgId, OrganizationPermissions.createTransactions);
    if (tx.isRecurring) {
      await _require(orgId, OrganizationPermissions.manageRecurring);
    }

    final box = await _treasuryBox;
    final before = box.get(tx.id);
    if (before != null) {
      await _require(
        before.effectiveOrganizationId,
        OrganizationPermissions.editTransactions,
      );
      if (before.isRecurring || tx.isRecurring) {
        await _require(
          before.effectiveOrganizationId,
          OrganizationPermissions.manageRecurring,
        );
        await _require(orgId, OrganizationPermissions.manageRecurring);
      }
      if (before.effectiveOrganizationId != orgId) {
        await _require(orgId, OrganizationPermissions.editTransactions);
      }
    }

    final actor = TeamService.current?.id;
    final normalized = _normalizeMoney(tx, ownership.org, ownership.account)
        .copyWith(
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
    await _require(
      before.effectiveOrganizationId,
      OrganizationPermissions.editTransactions,
    );

    final orgId = tx.organizationId ?? before.effectiveOrganizationId;
    final ownership = await _resolveOwnership(orgId, tx.accountId);
    if (orgId != before.effectiveOrganizationId) {
      // Re-ownership is a two-sided authorization boundary: the actor must be
      // allowed to edit both where the money came from and where it is going.
      await _require(orgId, OrganizationPermissions.editTransactions);
    }
    if (before.isRecurring || tx.isRecurring) {
      await _require(
        before.effectiveOrganizationId,
        OrganizationPermissions.manageRecurring,
      );
      await _require(orgId, OrganizationPermissions.manageRecurring);
    }

    final actor = TeamService.current?.id;
    final next = _normalizeMoney(tx, ownership.org, ownership.account).copyWith(
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
    await _require(
      before.effectiveOrganizationId,
      OrganizationPermissions.editTransactions,
    );
    if (before.isRecurring) {
      await _require(
        before.effectiveOrganizationId,
        OrganizationPermissions.manageRecurring,
      );
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

  /// Constrained repair primitive used only by InterOrgTransfer recovery.
  Future<void> restoreInterOrgLeg(TransactionModel tx) async {
    final transferId = tx.interOrgTransferId;
    if (tx.source != TransactionSource.interorg || transferId == null) {
      throw StateError('only linked inter-org legs can be recovered');
    }
    final box = await _treasuryBox;
    final existing = box.get(tx.id);
    if (existing != null) {
      if (existing.interOrgTransferId != transferId) {
        throw StateError('transaction id collision during inter-org recovery');
      }
      return;
    }
    final orgId = tx.effectiveOrganizationId;
    final ownership = await _resolveOwnership(orgId, tx.accountId);
    final normalized = _normalizeMoney(tx, ownership.org, ownership.account);
    await box.put(normalized.id, normalized);
    await TransactionAuditService.record(
      transactionId: normalized.id,
      before: null,
      after: normalized,
      reason: 'inter-org recovery restore',
      changedBy: 'interorg-recovery',
    );
    revision.value++;
  }

  /// Constrained counterpart to [restoreInterOrgLeg].
  Future<void> deleteInterOrgLegForRecovery(
    String id,
    String transferId,
  ) async {
    final box = await _treasuryBox;
    final existing = box.get(id);
    if (existing == null) return;
    if (existing.source != TransactionSource.interorg ||
        existing.interOrgTransferId != transferId) {
      throw StateError('refusing to delete unrelated transaction during recovery');
    }
    await TransactionAuditService.record(
      transactionId: id,
      before: existing,
      after: null,
      reason: 'inter-org recovery delete',
      changedBy: 'interorg-recovery',
    );
    await box.delete(id);
    revision.value++;
  }

  Future<List<TransactionModel>> getAllTransactionsRaw() async {
    final box = await _treasuryBox;
    return box.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<List<TransactionModel>> getAllTransactions() async {
    var ids = await OrganizationContext.effectiveOrganizationIds();
    if (TeamService.current != null) {
      final financeIds = await OrganizationAccessService.organizationIdsFor(
        OrganizationPermissions.viewFinance,
      );
      ids = ids.intersection(financeIds);
    }
    final all = await getAllTransactionsRaw();
    return all.where((t) => ids.contains(t.effectiveOrganizationId)).toList();
  }

  Future<List<TransactionModel>> getTransactionsByType(TransactionType type) async {
    final all = await getAllTransactions();
    return all.where((t) => t.type == type).toList();
  }

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
      final organizations =
          entry.value.map((e) => e.effectiveOrganizationId).toSet();
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
    var all = (await getAllTransactions())
        .where((tx) => !tx.date.isAfter(now) && !tx.isRecurring)
        .toList();
    if (OrganizationContext.scope == OrganizationScope.subtree) {
      all = eliminateInternalTransfers(all);
    }
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

  Future<Set<String>> _recurringMaintenanceIds() async {
    final current = TeamService.current;
    if (current == null || current.isOwner) {
      final root = await OrganizationService.root();
      return OrganizationService.subtreeIds(root.id);
    }
    return OrganizationAccessService.organizationIdsFor(
      OrganizationPermissions.manageRecurring,
      employeeId: current.id,
    );
  }

  Future<void> _putRecurringSystem(TransactionModel tx) async {
    final orgId = tx.effectiveOrganizationId;
    final ownership = await _resolveOwnership(orgId, tx.accountId);
    final box = await _treasuryBox;
    final before = box.get(tx.id);
    final normalized = _normalizeMoney(tx, ownership.org, ownership.account)
        .copyWith(updatedAt: DateTime.now(), updatedBy: 'recurring-system');
    await box.put(normalized.id, normalized);
    if (before != null) {
      await TransactionAuditService.record(
        transactionId: normalized.id,
        before: before,
        after: normalized,
        reason: 'recurring anchor advance',
        changedBy: 'recurring-system',
      );
    }
    revision.value++;
  }

  Future<void> processRecurringPayments() async {
    final allowedIds = await _recurringMaintenanceIds();
    final recurring = (await getAllTransactionsRaw())
        .where((t) => t.isRecurring && allowedIds.contains(t.effectiveOrganizationId))
        .toList();
    final now = DateTime.now();
    for (final tx in recurring) {
      final period = tx.recurringPeriod;
      if (period == null) continue;
      var anchor = tx;
      var guard = 0;
      while (RecurringEngine.isDue(anchor, now) && guard < 366) {
        final due = RecurringEngine.advance(anchor.date, period);
        if (tx.type == TransactionType.expense) {
          final actual = TransactionModel(
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
            originalAmount: tx.originalAmount,
            originalCurrency: tx.originalCurrency,
            organizationBaseAmount: tx.organizationBaseAmount,
            organizationBaseCurrency: tx.organizationBaseCurrency,
            fxRateToReporting: tx.fxRateToReporting,
            fxRateAt: due,
            fxSource: tx.fxSource,
          );
          if ((await _treasuryBox).get(actual.id) == null) {
            await _putRecurringSystem(actual);
          }
        }
        anchor = anchor.copyWith(date: due, updatedAt: DateTime.now());
        guard++;
      }
      if (guard > 0) await _putRecurringSystem(anchor);
    }
  }

  // ========== WESI HORIZON ==========

  Future<ForecastResult> generateForecast({
    int days = 30,
    WhatIfScenario whatIf = WhatIfScenario.none,
    double annualDiscountRate = 0.0,
  }) async {
    final requested = await OrganizationContext.effectiveOrganizationIds();
    var forecastIds = requested;
    if (TeamService.current != null) {
      final allowed = await OrganizationAccessService.organizationIdsFor(
        OrganizationPermissions.viewForecast,
      );
      forecastIds = requested.intersection(allowed);
    }
    if (forecastIds.isEmpty) {
      throw StateError('view_forecast permission required');
    }

    final rawScoped = (await getAllTransactionsRaw())
        .where((t) => forecastIds.contains(t.effectiveOrganizationId))
        .toList();
    final all = OrganizationContext.scope == OrganizationScope.subtree
        ? eliminateInternalTransfers(rawScoped)
        : rawScoped;
    final balance = await AccountService.reportingBalanceForOrganizations(
      forecastIds,
      rawScoped,
    );
    final orgId = OrganizationContext.currentOrganizationId;
    final scope = OrganizationContext.scope.name;
    final calibration = await HorizonLearningService.load(
      organizationId: orgId,
      organizationScope: scope,
    );
    _kickLearning(all, balance, orgId, scope);
    _kickPredictionAudit(all, balance, calibration, orgId, scope, forecastIds);

    final context = await HorizonBusinessContextService.load(
      transactions: all,
      days: days,
      organizationIds: forecastIds,
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

    _kickCompetition(all, balance, orgId, scope);
    return explained;
  }

  static void _kickLearning(
    List<TransactionModel> transactions,
    double currentBalance,
    String organizationId,
    String organizationScope,
  ) {
    final key = '$organizationId:$organizationScope';
    if (!_learningInFlight.add(key)) return;
    unawaited(HorizonLearningService.updateIfDue(
      transactions: transactions,
      currentBalance: currentBalance,
      organizationId: organizationId,
      organizationScope: organizationScope,
    ).whenComplete(() => _learningInFlight.remove(key)));
  }

  static void _kickPredictionAudit(
    List<TransactionModel> transactions,
    double currentBalance,
    HorizonCalibrationProfile calibration,
    String organizationId,
    String organizationScope,
    Set<String> organizationIds,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final key = '$organizationId:$organizationScope:${today.toIso8601String()}';
    if (_predictionAuditInFlight.contains(key) ||
        _predictionAuditKeys.contains(key)) return;
    _predictionAuditInFlight.add(key);

    unawaited(() async {
      try {
        const auditDays = 180;
        final context = await HorizonBusinessContextService.load(
          transactions: transactions,
          days: auditDays,
          now: today,
          organizationIds: organizationIds,
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
          organizationId: organizationId,
          organizationScope: organizationScope,
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
    String organizationId,
    String organizationScope,
  ) {
    final key = '$organizationId:$organizationScope';
    if (!_competitionInFlight.add(key)) return;
    unawaited(HorizonEngineCompetitionService.evaluateIfDue(
      transactions: transactions,
      currentBalance: currentBalance,
      organizationId: organizationId,
      organizationScope: organizationScope,
    ).whenComplete(() => _competitionInFlight.remove(key)));
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
