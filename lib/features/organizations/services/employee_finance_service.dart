import 'dart:math';

import '../../../core/services/currency_service.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/crm_service.dart';
import '../../tasks/models/task_model.dart';
import '../../tasks/services/task_cash_impact.dart';
import '../../tasks/services/task_service.dart';
import '../../team/models/employee_model.dart';
import '../../team/services/team_service.dart';
import '../../treasury/models/transaction_model.dart';
import '../../treasury/services/forecast_engine.dart';
import '../../treasury/services/anomaly_engine.dart';
import '../../treasury/services/treasury_service.dart';
import 'organization_access_service.dart';
import 'organization_context.dart';
import 'organization_service.dart';

enum EmployeeFinanceView { self, organization, subtree }

class EmployeeFinanceMetrics {
  final String employeeId;
  final DateTime from;
  final DateTime to;
  final double contribution;
  final double expenses;
  final double net;
  final double recurringObligations;
  final int operations;
  final int overdueEvents;
  final int missedDealExpectations;
  final int anomalousExpenses;
  final List<TransactionModel> upcoming;

  const EmployeeFinanceMetrics({
    required this.employeeId,
    required this.from,
    required this.to,
    required this.contribution,
    required this.expenses,
    required this.net,
    required this.recurringObligations,
    required this.operations,
    required this.overdueEvents,
    required this.missedDealExpectations,
    required this.anomalousExpenses,
    required this.upcoming,
  });

  static EmployeeFinanceMetrics empty(
    String employeeId,
    DateTime from,
    DateTime to,
  ) =>
      EmployeeFinanceMetrics(
        employeeId: employeeId,
        from: from,
        to: to,
        contribution: 0,
        expenses: 0,
        net: 0,
        recurringObligations: 0,
        operations: 0,
        overdueEvents: 0,
        missedDealExpectations: 0,
        anomalousExpenses: 0,
        upcoming: const [],
      );
}

class OrganizationFinanceMetrics {
  final Set<String> organizationIds;
  final DateTime from;
  final DateTime to;
  final double income;
  final double expenses;
  final double net;
  final double recurringObligations;
  final int operations;

  const OrganizationFinanceMetrics({
    required this.organizationIds,
    required this.from,
    required this.to,
    required this.income,
    required this.expenses,
    required this.net,
    required this.recurringObligations,
    required this.operations,
  });

  static OrganizationFinanceMetrics empty(DateTime from, DateTime to) =>
      OrganizationFinanceMetrics(
        organizationIds: const <String>{},
        from: from,
        to: to,
        income: 0,
        expenses: 0,
        net: 0,
        recurringObligations: 0,
        operations: 0,
      );
}

class EmployeeFinanceComparison {
  final EmployeeFinanceMetrics current;
  final EmployeeFinanceMetrics previous;

  const EmployeeFinanceComparison({
    required this.current,
    required this.previous,
  });
}

class EmployeeFinanceRow {
  final EmployeeModel employee;
  final EmployeeFinanceMetrics metrics;
  const EmployeeFinanceRow(this.employee, this.metrics);
}

class EmployeeFinanceService {
  EmployeeFinanceService._();

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static Future<Set<String>> _requestedIds(
    String organizationId,
    EmployeeFinanceView view,
  ) async {
    if (view == EmployeeFinanceView.subtree) {
      return OrganizationService.subtreeIds(organizationId);
    }
    return <String>{organizationId};
  }

  static Future<Set<String>> _authorizedIds(
    String organizationId,
    EmployeeFinanceView view,
  ) async {
    final requested = await _requestedIds(organizationId, view);
    if (TeamService.current == null) return requested;
    final financeAllowed = await OrganizationAccessService.organizationIdsFor(
      'view_finance',
    );
    return requested.intersection(financeAllowed);
  }

  static Future<Set<String>> _authorizedSelfIds() async {
    final requested = await OrganizationContext.effectiveOrganizationIds();
    if (TeamService.current == null) return requested;
    final result = <String>{};
    for (final id in requested) {
      if (await OrganizationAccessService.canViewSelfFinance(id)) {
        result.add(id);
      }
    }
    return result;
  }

  static EmployeeFinanceMetrics _calculate({
    required String employeeId,
    required List<TransactionModel> transactions,
    required List<CrmDeal> deals,
    required List<TaskModel> tasks,
    required DateTime from,
    required DateTime to,
  }) {
    final owned = transactions
        .where((t) => t.ownerEmployeeId == employeeId)
        .toList();
    var income = 0.0;
    var expense = 0.0;
    var recurring = 0.0;
    var overdue = 0;
    var missedDeals = 0;
    var anomalousExpenses = 0;
    final anomalyIds = AnomalyEngine.detect(transactions).map((e) => e.id).toSet();
    final now = DateTime.now();
    final upcoming = <TransactionModel>[];

    for (final tx in owned) {
      if (tx.isRecurring) {
        if (tx.type == TransactionType.expense) recurring += tx.amount;
        continue;
      }
      if (!tx.date.isBefore(from) && !tx.date.isAfter(to)) {
        if (tx.type == TransactionType.income) {
          income += tx.amount;
        } else {
          expense += tx.amount;
          if (anomalyIds.contains(tx.id)) anomalousExpenses++;
        }
      }
      if (tx.date.isAfter(now) &&
          tx.date.isBefore(now.add(const Duration(days: 31)))) {
        upcoming.add(tx);
      }
      if (tx.date.isBefore(now) &&
          tx.type == TransactionType.expense &&
          tx.source == TransactionSource.task) {
        overdue++;
      }
    }

    final transactionIds = transactions.map((t) => t.id).toSet();
    for (final deal in deals) {
      if (deal.responsibleEmployeeId != employeeId) continue;
      if (deal.isOpen &&
          deal.expectedCloseAt != null &&
          deal.expectedCloseAt!.isBefore(now)) {
        missedDeals++;
      }
      if (deal.stage != DealStage.won) continue;
      final closed = deal.closedAt ?? deal.updatedAt;
      if (closed.isBefore(from) || closed.isAfter(to)) continue;
      if (deal.transactionId.isNotEmpty &&
          transactionIds.contains(deal.transactionId)) {
        continue;
      }
      income += deal.amount *
          CurrencyService.rateToRub(deal.currency.toLowerCase());
    }

    for (final task in tasks) {
      if (task.effectiveResponsibleEmployeeId != employeeId ||
          task.status == TaskStatus.done ||
          task.dueDate == null) {
        continue;
      }
      final cash = TaskCashImpact.fromTags(task.tags);
      if (cash == null) continue;
      if (task.isOverdue) overdue++;
      if (cash.signedAmount < 0) recurring += cash.signedAmount.abs();
    }

    upcoming.sort((a, b) => a.date.compareTo(b.date));
    return EmployeeFinanceMetrics(
      employeeId: employeeId,
      from: from,
      to: to,
      contribution: income,
      expenses: expense,
      net: income - expense,
      recurringObligations: recurring,
      operations: owned
          .where((t) =>
              !t.isRecurring &&
              !t.date.isBefore(from) &&
              !t.date.isAfter(to))
          .length,
      overdueEvents: overdue,
      missedDealExpectations: missedDeals,
      anomalousExpenses: anomalousExpenses,
      upcoming: upcoming,
    );
  }

  static Future<EmployeeFinanceComparison> selfComparison({
    int periodDays = 30,
  }) async {
    final employee = TeamService.current;
    final now = DateTime.now();
    final currentFrom = now.subtract(Duration(days: periodDays - 1));
    final previousTo = currentFrom.subtract(const Duration(microseconds: 1));
    final previousFrom = previousTo.subtract(Duration(days: periodDays - 1));
    if (employee == null) {
      return EmployeeFinanceComparison(
        current: EmployeeFinanceMetrics.empty('', currentFrom, now),
        previous: EmployeeFinanceMetrics.empty('', previousFrom, previousTo),
      );
    }
    final ids = await _authorizedSelfIds();
    if (ids.isEmpty) {
      return EmployeeFinanceComparison(
        current: EmployeeFinanceMetrics.empty(employee.id, currentFrom, now),
        previous: EmployeeFinanceMetrics.empty(employee.id, previousFrom, previousTo),
      );
    }
    final all = (await TreasuryService().getAllTransactionsRaw())
        .where((t) => ids.contains(t.effectiveOrganizationId))
        .toList();
    final deals = await CrmService.dealsForOrganizations(ids);
    final tasks = await TaskService().getForOrganizations(ids);
    return EmployeeFinanceComparison(
      current: _calculate(
        employeeId: employee.id,
        transactions: all,
        deals: deals,
        tasks: tasks,
        from: currentFrom,
        to: now,
      ),
      previous: _calculate(
        employeeId: employee.id,
        transactions: all,
        deals: deals,
        tasks: tasks,
        from: previousFrom,
        to: previousTo,
      ),
    );
  }

  static Future<EmployeeFinanceMetrics> self({int periodDays = 30}) async =>
      (await selfComparison(periodDays: periodDays)).current;

  /// Aggregate finance for the selected organization or authorized subtree.
  /// This does not expose any employee attribution and therefore remains
  /// separate from [teamBreakdown].
  static Future<OrganizationFinanceMetrics> organizationFinance({
    required String organizationId,
    EmployeeFinanceView view = EmployeeFinanceView.organization,
    int periodDays = 30,
  }) async {
    final now = DateTime.now();
    final from = now.subtract(Duration(days: periodDays - 1));
    if (!await OrganizationAccessService.canViewOrganizationFinance(
      organizationId,
    )) {
      return OrganizationFinanceMetrics.empty(from, now);
    }
    if (view == EmployeeFinanceView.subtree &&
        !await OrganizationAccessService.canUseSubtreeFinance(organizationId)) {
      return OrganizationFinanceMetrics.empty(from, now);
    }
    final ids = await _authorizedIds(organizationId, view);
    if (ids.isEmpty) return OrganizationFinanceMetrics.empty(from, now);
    var transactions = (await TreasuryService().getAllTransactionsRaw())
        .where((t) => ids.contains(t.effectiveOrganizationId))
        .toList();
    if (view == EmployeeFinanceView.subtree) {
      transactions = TreasuryService.eliminateInternalTransfers(transactions);
    }

    var income = 0.0;
    var expenses = 0.0;
    var recurring = 0.0;
    var operations = 0;
    for (final tx in transactions) {
      if (tx.isRecurring) {
        if (tx.type == TransactionType.expense) recurring += tx.amount;
        continue;
      }
      if (tx.date.isBefore(from) || tx.date.isAfter(now)) continue;
      operations++;
      if (tx.type == TransactionType.income) {
        income += tx.amount;
      } else {
        expenses += tx.amount;
      }
    }
    return OrganizationFinanceMetrics(
      organizationIds: ids,
      from: from,
      to: now,
      income: income,
      expenses: expenses,
      net: income - expenses,
      recurringObligations: recurring,
      operations: operations,
    );
  }

  static Future<List<EmployeeFinanceRow>> teamBreakdown({
    required String organizationId,
    EmployeeFinanceView view = EmployeeFinanceView.organization,
    int periodDays = 30,
  }) async {
    if (TeamService.current != null &&
        !await OrganizationAccessService.canViewTeamFinance(organizationId)) {
      return const [];
    }
    if (view == EmployeeFinanceView.subtree &&
        !await OrganizationAccessService.canUseSubtreeFinance(organizationId)) {
      return const [];
    }
    final ids = await _authorizedIds(organizationId, view);
    if (ids.isEmpty) return const [];
    final now = DateTime.now();
    final from = now.subtract(Duration(days: periodDays - 1));
    final all = (await TreasuryService().getAllTransactionsRaw())
        .where((t) => ids.contains(t.effectiveOrganizationId))
        .toList();
    final deals = await CrmService.dealsForOrganizations(ids);
    final tasks = await TaskService().getForOrganizations(ids);

    final rows = <EmployeeFinanceRow>[];
    for (final employee in TeamService.all) {
      if (!employee.isOwner) {
        final employeeOrgs = await OrganizationAccessService.visibleOrganizationIds(
          employeeId: employee.id,
        );
        if (employeeOrgs.intersection(ids).isEmpty) continue;
      }
      rows.add(EmployeeFinanceRow(
        employee,
        _calculate(
          employeeId: employee.id,
          transactions: all,
          deals: deals,
          tasks: tasks,
          from: from,
          to: now,
        ),
      ));
    }
    rows.sort((a, b) => b.metrics.net.compareTo(a.metrics.net));
    return rows;
  }

  static Future<ForecastResult> selfForecast({int days = 30}) async {
    final employee = TeamService.current;
    if (employee == null) return ForecastResult.empty();
    final ids = await _authorizedSelfIds();
    if (ids.isEmpty) return ForecastResult.empty();
    final allTransactions = await TreasuryService().getAllTransactionsRaw();
    final tx = allTransactions
        .where((t) =>
            ids.contains(t.effectiveOrganizationId) &&
            t.ownerEmployeeId == employee.id)
        .toList();
    final today = _day(DateTime.now());
    final end = today.add(Duration(days: days));
    final events = <HorizonCashEvent>[];

    for (final deal in await CrmService.dealsForOrganizations(ids)) {
      if (deal.responsibleEmployeeId != employee.id ||
          !deal.isOpen ||
          deal.amount <= 0 ||
          deal.expectedCloseAt == null) {
        continue;
      }
      final due = _day(deal.expectedCloseAt!);
      if (due.isAfter(end)) continue;
      final effectiveDate = due.isAfter(today)
          ? due
          : today.add(const Duration(days: 1));
      final probability =
          (deal.probability / 100.0).clamp(0.01, 0.99).toDouble();
      events.add(HorizonCashEvent(
        title: 'CRM: ${deal.title}',
        amount: deal.amount *
            CurrencyService.rateToRub(deal.currency.toLowerCase()),
        date: effectiveDate,
        probability: due.isAfter(today)
            ? probability
            : min(probability, 0.65).toDouble(),
        committed: due.isAfter(today) &&
            deal.stage == DealStage.negotiation &&
            probability >= 0.9,
        source: 'employee-crm',
        riskSource: 'employee:${employee.id}:crm:${deal.id}',
      ));
    }

    for (final task in await TaskService().getForOrganizations(ids)) {
      if (task.effectiveResponsibleEmployeeId != employee.id ||
          task.status == TaskStatus.done ||
          task.dueDate == null) {
        continue;
      }
      final cash = TaskCashImpact.fromTags(task.tags);
      if (cash == null) continue;
      final due = _day(task.dueDate!);
      if (due.isAfter(end)) continue;
      events.add(HorizonCashEvent(
        title: 'Task: ${task.title}',
        amount: cash.signedAmount,
        date: due.isAfter(today) ? due : today.add(const Duration(days: 1)),
        probability: due.isAfter(today)
            ? cash.probability
            : min(cash.probability, 0.65).toDouble(),
        committed: due.isAfter(today) && cash.committed,
        source: 'employee-task',
        riskSource: 'employee:${employee.id}:task:${task.id}',
      ));
    }

    return ForecastEngine.generate(
      transactions: tx,
      currentBalance: 0,
      days: days,
      seed: 42,
      businessEvents: events,
    );
  }
}
