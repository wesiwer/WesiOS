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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-org-finance-negative-');
    Hive.init(temp.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(TransactionModelAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TransactionTypeAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(RecurringPeriodAdapter());
    if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(TaskStatusAdapter());
    if (!Hive.isAdapterRegistered(11)) Hive.registerAdapter(TaskPriorityAdapter());
    if (!Hive.isAdapterRegistered(12)) Hive.registerAdapter(SubTaskAdapter());
    if (!Hive.isAdapterRegistered(13)) Hive.registerAdapter(TaskModelAdapter());
    if (!Hive.isAdapterRegistered(20)) Hive.registerAdapter(TeamPermissionsAdapter());
    if (!Hive.isAdapterRegistered(21)) Hive.registerAdapter(EmployeeModelAdapter());
    if (!Hive.isAdapterRegistered(80)) Hive.registerAdapter(OrganizationStatusAdapter());
    if (!Hive.isAdapterRegistered(81)) Hive.registerAdapter(OrganizationModelAdapter());
    if (!Hive.isAdapterRegistered(82)) Hive.registerAdapter(OrganizationAccessGrantAdapter());
    if (!Hive.isAdapterRegistered(86)) Hive.registerAdapter(TransactionSourceAdapter());

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

  Future<EmployeeModel> addEmployee(String id) async {
    final value = EmployeeModel(
      id: id,
      login: id,
      fullName: id,
      createdAt: DateTime(2026, 1, 1),
      permissions: const TeamPermissions(),
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(id, value);
    return value;
  }

  Future<void> signIn(String id) =>
      Hive.box('wesios_settings').put('team_current_employee', id);

  test('team finance flag cannot expose rows without view_finance', () async {
    final manager = await addEmployee('manager');
    // Simulate a malformed legacy/remote grant bypassing the normal grant API.
    final now = DateTime.now();
    await Hive.box<OrganizationAccessGrant>(OrganizationAccessService.boxName).put(
      '${manager.id}::${OrganizationModel.rootId}',
      OrganizationAccessGrant(
        id: '${manager.id}::${OrganizationModel.rootId}',
        employeeId: manager.id,
        organizationId: OrganizationModel.rootId,
        includeSubtree: false,
        canViewTeamFinance: true,
        canViewSelfFinance: true,
        permissions: const [OrganizationPermissions.view],
        createdAt: now,
        updatedAt: now,
        createdBy: 'legacy',
      ),
    );
    await signIn(manager.id);
    await OrganizationContext.initialize();
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);

    expect(
      await EmployeeFinanceService.teamBreakdown(
        organizationId: OrganizationModel.rootId,
      ),
      isEmpty,
    );
  });

  test('canViewSelfFinance=false hides both self metrics and self forecast', () async {
    final employee = await addEmployee('employee');
    await OrganizationAccessService.grant(
      employeeId: employee.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [OrganizationPermissions.view],
      canViewSelfFinance: false,
      enforceActor: false,
    );
    await signIn(employee.id);
    await OrganizationContext.initialize();
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);

    await Hive.box<TransactionModel>('wesios_treasury').put(
      'mine',
      TransactionModel(
        id: 'mine',
        title: 'Private contribution',
        amount: 5000,
        type: TransactionType.income,
        date: DateTime.now(),
        organizationId: OrganizationModel.rootId,
        ownerEmployeeId: employee.id,
      ),
    );

    final metrics = await EmployeeFinanceService.self();
    final forecast = await EmployeeFinanceService.selfForecast();
    expect(metrics.contribution, 0);
    expect(metrics.expenses, 0);
    expect(metrics.operations, 0);
    expect(forecast.p50, isEmpty);
  });

  test('subtree team rows are filtered per organization, not only by selected parent', () async {
    final parent = await OrganizationService.create(
      name: 'IT',
      parentId: OrganizationModel.rootId,
      createdBy: 'setup',
    );
    final child = await OrganizationService.create(
      name: 'Studio A',
      parentId: parent.id,
      createdBy: 'setup',
    );
    final manager = await addEmployee('manager');
    final childEmployee = await addEmployee('child-employee');

    // Root subtree gives aggregate finance throughout the tree, but deliberately
    // does NOT grant personal team rows.
    await OrganizationAccessService.grant(
      employeeId: manager.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: true,
      permissions: const [
        OrganizationPermissions.view,
        OrganizationPermissions.viewFinance,
      ],
      canViewTeamFinance: false,
      enforceActor: false,
    );
    // Exact parent grant allows team rows only in the selected parent itself.
    await OrganizationAccessService.grant(
      employeeId: manager.id,
      organizationId: parent.id,
      includeSubtree: false,
      permissions: const [
        OrganizationPermissions.view,
        OrganizationPermissions.viewFinance,
      ],
      canViewTeamFinance: true,
      enforceActor: false,
    );
    await OrganizationAccessService.grant(
      employeeId: childEmployee.id,
      organizationId: child.id,
      includeSubtree: false,
      permissions: const [OrganizationPermissions.view],
      enforceActor: false,
    );

    await Hive.box<TransactionModel>('wesios_treasury').put(
      'child-private',
      TransactionModel(
        id: 'child-private',
        title: 'Child employee private contribution',
        amount: 9999,
        type: TransactionType.income,
        date: DateTime.now(),
        organizationId: child.id,
        ownerEmployeeId: childEmployee.id,
      ),
    );

    await signIn(manager.id);
    await OrganizationContext.initialize();
    await OrganizationContext.selectOrganization(parent.id);
    await OrganizationContext.setScope(OrganizationScope.subtree);

    final rows = await EmployeeFinanceService.teamBreakdown(
      organizationId: parent.id,
      view: EmployeeFinanceView.subtree,
    );
    expect(rows.map((r) => r.employee.id), isNot(contains(childEmployee.id)));
  });
}
