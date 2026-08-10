import '../../team/models/employee_model.dart';
import '../../team/services/team_service.dart';
import '../../treasury/models/transaction_model.dart';
import '../../treasury/services/forecast_engine.dart';
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
    required this.upcoming,
  });

  static EmployeeFinanceMetrics empty(String employeeId, DateTime from, DateTime to) =>
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
        upcoming: const [],
      );
}

class EmployeeFinanceRow {
  final EmployeeModel employee;
  final EmployeeFinanceMetrics metrics;
  const EmployeeFinanceRow(this.employee, this.metrics);
}

class EmployeeFinanceService {
  EmployeeFinanceService._();

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
    final allowed = await OrganizationAccessService.visibleOrganizationIds();
    return requested.intersection(allowed);
  }

  static EmployeeFinanceMetrics _calculate(
    String employeeId,
    List<TransactionModel> transactions,
    DateTime from,
    DateTime to,
  ) {
    final owned = transactions.where((t) => t.ownerEmployeeId == employeeId).toList();
    var income = 0.0;
    var expense = 0.0;
    var recurring = 0.0;
    var overdue = 0;
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
    upcoming.sort((a, b) => a.date.compareTo(b.date));
    return EmployeeFinanceMetrics(
      employeeId: employeeId,
      from: from,
      to: to,
      contribution: income,
      expenses: expense,
      net: income - expense,
      recurringObligations: recurring,
      operations: owned.where((t) => !t.isRecurring && !t.date.isBefore(from) && !t.date.isAfter(to)).length,
      overdueEvents: overdue,
      upcoming: upcoming,
    );
  }

  static Future<EmployeeFinanceMetrics> self({
    int periodDays = 30,
  }) async {
    final employee = TeamService.current;
    final now = DateTime.now();
    final from = now.subtract(Duration(days: periodDays - 1));
    if (employee == null) return EmployeeFinanceMetrics.empty('', from, now);
    final orgId = OrganizationContext.currentOrganizationId;
    if (!await OrganizationAccessService.canViewSelfFinance(orgId)) {
      return EmployeeFinanceMetrics.empty(employee.id, from, now);
    }
    final ids = await OrganizationContext.effectiveOrganizationIds();
    final all = await TreasuryService().getAllTransactionsRaw();
    return _calculate(
      employee.id,
      all.where((t) => ids.contains(t.effectiveOrganizationId)).toList(),
      from,
      now,
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
    final ids = await _authorizedIds(organizationId, view);
    if (ids.isEmpty) return const [];
    final now = DateTime.now();
    final from = now.subtract(Duration(days: periodDays - 1));
    final all = (await TreasuryService().getAllTransactionsRaw())
        .where((t) => ids.contains(t.effectiveOrganizationId))
        .toList();

    final rows = <EmployeeFinanceRow>[];
    for (final employee in TeamService.all) {
      if (!employee.isOwner) {
        final employeeOrgs =
            await OrganizationAccessService.visibleOrganizationIds(employeeId: employee.id);
        if (employeeOrgs.intersection(ids).isEmpty) continue;
      }
      rows.add(EmployeeFinanceRow(
        employee,
        _calculate(employee.id, all, from, now),
      ));
    }
    rows.sort((a, b) => b.metrics.net.compareTo(a.metrics.net));
    return rows;
  }

  static Future<ForecastResult> selfForecast({int days = 30}) async {
    final employee = TeamService.current;
    if (employee == null) return ForecastResult.empty();
    final ids = await OrganizationContext.effectiveOrganizationIds();
    final tx = (await TreasuryService().getAllTransactionsRaw())
        .where((t) =>
            ids.contains(t.effectiveOrganizationId) &&
            t.ownerEmployeeId == employee.id)
        .toList();
    return ForecastEngine.generate(
      transactions: tx,
      currentBalance: 0,
      days: days,
      seed: 42,
    );
  }
}
