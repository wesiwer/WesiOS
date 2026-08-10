import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
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
import 'package:wesios/features/treasury/services/treasury_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-org-finance-access-');
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
    await Hive.openBox<dynamic>('wesios_crm');
  });

  setUp(() async {
    await Hive.box('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<OrganizationAccessGrant>(OrganizationAccessService.boxName).clear();
    await Hive.box<TransactionModel>('wesios_treasury').clear();
    await Hive.box<TaskModel>('wesios_tasks').clear();
    await Hive.box<dynamic>('wesios_crm').clear();
    await OrganizationService.ensureBaseline();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('self finance remains visible when organization aggregate is denied', () async {
    final employee = EmployeeModel(
      id: 'employee',
      login: 'employee',
      fullName: 'Employee',
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

    await Hive.box<TransactionModel>('wesios_treasury').put(
      'mine',
      TransactionModel(
        id: 'mine',
        title: 'My contribution',
        amount: 1200,
        type: TransactionType.income,
        date: DateTime.now(),
        organizationId: OrganizationModel.rootId,
        ownerEmployeeId: employee.id,
      ),
    );

    expect(await TreasuryService().getAllTransactions(), isEmpty,
        reason: 'plain view must not expose aggregate Treasury finance');

    final self = await EmployeeFinanceService.self();
    expect(self.contribution, 1200,
        reason: 'self finance must remain independent of view_finance');

    final aggregate = await EmployeeFinanceService.organizationFinance(
      organizationId: OrganizationModel.rootId,
    );
    expect(aggregate.organizationIds, isEmpty);
    expect(aggregate.income, 0);
  });

  test('view_finance enables aggregate org data but not coworker breakdown', () async {
    final employee = EmployeeModel(
      id: 'employee',
      login: 'employee',
      fullName: 'Employee',
      createdAt: DateTime(2026, 1, 1),
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(employee.id, employee);
    await Hive.box('wesios_settings').put('team_current_employee', employee.id);

    await OrganizationAccessService.grant(
      employeeId: employee.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [
        OrganizationPermissions.view,
        OrganizationPermissions.viewFinance,
      ],
      canViewSelfFinance: true,
      canViewTeamFinance: false,
      enforceActor: false,
    );
    await OrganizationContext.initialize();
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);

    await Hive.box<TransactionModel>('wesios_treasury').put(
      'root-income',
      TransactionModel(
        id: 'root-income',
        title: 'Root income',
        amount: 5000,
        type: TransactionType.income,
        date: DateTime.now(),
        organizationId: OrganizationModel.rootId,
      ),
    );

    expect((await TreasuryService().getAllTransactions()).single.amount, 5000);
    final aggregate = await EmployeeFinanceService.organizationFinance(
      organizationId: OrganizationModel.rootId,
    );
    expect(aggregate.income, 5000);
    expect(
      await EmployeeFinanceService.teamBreakdown(
        organizationId: OrganizationModel.rootId,
      ),
      isEmpty,
      reason: 'person-level rows still require canViewTeamFinance',
    );
  });
}
