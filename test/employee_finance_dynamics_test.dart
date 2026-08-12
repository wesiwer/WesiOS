import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/crm/models/crm_models.dart';
import 'package:wesios/features/crm/services/crm_service.dart';
import 'package:wesios/features/organizations/models/organization_access_grant.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/employee_finance_service.dart';
import 'package:wesios/features/organizations/services/organization_access_service.dart';
import 'package:wesios/features/organizations/services/organization_context.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-employee-dynamics-');
    Hive.init(temp.path);
    Hive.registerAdapter(TransactionModelAdapter());
    Hive.registerAdapter(TransactionTypeAdapter());
    Hive.registerAdapter(RecurringPeriodAdapter());
    Hive.registerAdapter(TransactionSourceAdapter());
    Hive.registerAdapter(TaskStatusAdapter());
    Hive.registerAdapter(TaskPriorityAdapter());
    Hive.registerAdapter(SubTaskAdapter());
    Hive.registerAdapter(TaskModelAdapter());
    Hive.registerAdapter(TeamPermissionsAdapter());
    Hive.registerAdapter(EmployeeModelAdapter());
    Hive.registerAdapter(OrganizationStatusAdapter());
    Hive.registerAdapter(OrganizationModelAdapter());
    Hive.registerAdapter(OrganizationAccessGrantAdapter());

    await Hive.openBox('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<OrganizationAccessGrant>(OrganizationAccessService.boxName);
    await Hive.openBox<TransactionModel>('wesios_treasury');
    await Hive.openBox<TaskModel>('wesios_tasks');
    await Hive.openBox<dynamic>(CrmService.boxName);
  });

  setUp(() async {
    await Hive.box('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<OrganizationAccessGrant>(OrganizationAccessService.boxName).clear();
    await Hive.box<TransactionModel>('wesios_treasury').clear();
    await Hive.box<TaskModel>('wesios_tasks').clear();
    await Hive.box<dynamic>(CrmService.boxName).clear();
    await OrganizationService.ensureBaseline();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<EmployeeModel> signInEmployee() async {
    final employee = EmployeeModel(
      id: 'employee-a',
      login: 'employee-a',
      fullName: 'Employee A',
      createdAt: DateTime(2026, 1, 1),
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(employee.id, employee);
    await Hive.box('wesios_settings').put('team_current_employee', employee.id);
    await OrganizationAccessService.grant(
      employeeId: employee.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [OrganizationPermissions.view],
      canViewSelfFinance: true,
      canViewTeamFinance: false,
      enforceActor: false,
    );
    await OrganizationContext.initialize();
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);
    await OrganizationContext.setScope(OrganizationScope.only);
    return employee;
  }

  test('self comparison uses the immediately previous equal-length period', () async {
    final employee = await signInEmployee();
    final now = DateTime.now();
    await Hive.box<TransactionModel>('wesios_treasury').putAll({
      'current': TransactionModel(
        id: 'current',
        title: 'Current contribution',
        amount: 1000,
        type: TransactionType.income,
        date: now.subtract(const Duration(days: 2)),
        organizationId: OrganizationModel.rootId,
        ownerEmployeeId: employee.id,
      ),
      'previous': TransactionModel(
        id: 'previous',
        title: 'Previous contribution',
        amount: 500,
        type: TransactionType.income,
        date: now.subtract(const Duration(days: 10)),
        organizationId: OrganizationModel.rootId,
        ownerEmployeeId: employee.id,
      ),
    });

    final comparison = await EmployeeFinanceService.selfComparison(periodDays: 7);
    expect(comparison.current.contribution, 1000);
    expect(comparison.previous.contribution, 500);
  });

  test('self risks include overdue responsible CRM deal and anomalous expense', () async {
    final employee = await signInEmployee();
    final now = DateTime.now();
    final rows = <dynamic, TransactionModel>{};
    for (var i = 0; i < 5; i++) {
      rows['normal-$i'] = TransactionModel(
        id: 'normal-$i',
        title: 'Normal expense $i',
        amount: 10,
        type: TransactionType.expense,
        date: now.subtract(Duration(days: i)),
        organizationId: OrganizationModel.rootId,
        ownerEmployeeId: employee.id,
      );
    }
    rows['anomaly'] = TransactionModel(
      id: 'anomaly',
      title: 'Large personal expense',
      amount: 10000,
      type: TransactionType.expense,
      date: now.subtract(const Duration(days: 1)),
      organizationId: OrganizationModel.rootId,
      ownerEmployeeId: employee.id,
    );
    await Hive.box<TransactionModel>('wesios_treasury').putAll(rows);

    await CrmService.saveDeal(CrmDeal(
      id: 'late-deal',
      clientId: 'client-a',
      title: 'Late deal',
      amount: 50000,
      stage: DealStage.negotiation,
      probability: 80,
      createdAt: now.subtract(const Duration(days: 20)),
      updatedAt: now,
      expectedCloseAt: now.subtract(const Duration(days: 1)),
      organizationId: OrganizationModel.rootId,
      responsibleEmployeeId: employee.id,
    ));

    final metrics = await EmployeeFinanceService.self(periodDays: 30);
    expect(metrics.missedDealExpectations, 1);
    expect(metrics.anomalousExpenses, 1);
  });

  test('CRM service never silently reattributes explicit custom or empty responsibility', () async {
    await signInEmployee();
    final now = DateTime.now();

    await CrmService.saveClient(CrmClient(
      id: 'client-custom',
      name: 'Custom client',
      owner: 'External partner',
      ownerEmployeeId: null,
      organizationId: OrganizationModel.rootId,
      createdAt: now,
      updatedAt: now,
    ));
    expect((await CrmService.clients()).single.ownerEmployeeId, isNull);

    await CrmService.saveDeal(CrmDeal(
      id: 'deal-unassigned',
      clientId: 'client-custom',
      title: 'Unassigned deal',
      organizationId: OrganizationModel.rootId,
      responsibleEmployeeId: null,
      createdAt: now,
      updatedAt: now,
    ));
    expect((await CrmService.deals()).single.responsibleEmployeeId, isNull);
  });
}
