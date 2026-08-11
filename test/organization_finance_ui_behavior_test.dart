import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/crm/services/crm_service.dart';
import 'package:wesios/features/organizations/models/organization_access_grant.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/my_finance_screen.dart';
import 'package:wesios/features/organizations/services/organization_access_service.dart';
import 'package:wesios/features/organizations/services/organization_context.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';

Future<void> pumpUiFrames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-finance-ui-behavior-');
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

    await Hive.openBox<dynamic>('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<OrganizationAccessGrant>(OrganizationAccessService.boxName);
    await Hive.openBox<TransactionModel>('wesios_treasury');
    await Hive.openBox<TaskModel>('wesios_tasks');
    await Hive.openBox<dynamic>(CrmService.boxName);
  });

  setUp(() async {
    await Hive.box<dynamic>('wesios_settings').clear();
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

  Future<EmployeeModel> addEmployee(String id, String name) async {
    final employee = EmployeeModel(
      id: id,
      login: id,
      fullName: name,
      position: id == 'manager' ? 'Manager' : 'Developer',
      createdAt: DateTime(2026, 1, 1),
      permissions: const TeamPermissions(),
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(id, employee);
    return employee;
  }

  testWidgets(
      'team finance row is hidden without flag, appears after grant, and opens employee card',
      (tester) async {
    final manager = await addEmployee('manager', 'Manager');
    final worker = await addEmployee('worker', 'Worker');

    await OrganizationAccessService.grant(
      employeeId: manager.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [
        OrganizationPermissions.view,
        OrganizationPermissions.viewFinance,
      ],
      canViewSelfFinance: true,
      canViewTeamFinance: false,
      createdBy: 'test',
      enforceActor: false,
    );
    await OrganizationAccessService.grant(
      employeeId: worker.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [OrganizationPermissions.view],
      canViewSelfFinance: true,
      canViewTeamFinance: false,
      createdBy: 'test',
      enforceActor: false,
    );
    await Hive.box<dynamic>('wesios_settings')
        .put('team_current_employee', manager.id);
    await OrganizationContext.initialize();
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);
    await OrganizationContext.setScope(OrganizationScope.only);

    await Hive.box<TransactionModel>('wesios_treasury').put(
      'worker-income',
      TransactionModel(
        id: 'worker-income',
        title: 'Worker contribution',
        amount: 5000,
        type: TransactionType.income,
        date: DateTime.now(),
        organizationId: OrganizationModel.rootId,
        ownerEmployeeId: worker.id,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: MyFinanceScreen()),
    );
    await pumpUiFrames(tester);

    expect(find.text('Организация'), findsOneWidget);
    await tester.tap(find.text('Организация'));
    await pumpUiFrames(tester);
    expect(find.text('Персональная разбивка скрыта'), findsOneWidget);
    expect(find.text('Worker'), findsNothing);

    await OrganizationAccessService.grant(
      employeeId: manager.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [
        OrganizationPermissions.view,
        OrganizationPermissions.viewFinance,
      ],
      canViewSelfFinance: true,
      canViewTeamFinance: true,
      createdBy: 'test',
      enforceActor: false,
    );
    await pumpUiFrames(tester);

    expect(find.text('Worker'), findsOneWidget);
    final workerTile = find.widgetWithText(ListTile, 'Worker');
    expect(workerTile, findsOneWidget);
    await tester.ensureVisible(workerTile);
    await tester.tap(workerTile);
    await pumpUiFrames(tester);

    expect(find.text('Worker'), findsWidgets);
    expect(find.text('Вклад'), findsOneWidget);
    expect(find.text('Расходы'), findsOneWidget);
    expect(find.text('Net'), findsOneWidget);
    expect(find.text('Операций'), findsOneWidget);
    expect(find.text('Закрыть'), findsOneWidget);

    await tester.tap(find.text('Закрыть'));
    await pumpUiFrames(tester);

    await OrganizationAccessService.grant(
      employeeId: manager.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [
        OrganizationPermissions.view,
        OrganizationPermissions.viewFinance,
      ],
      canViewSelfFinance: true,
      canViewTeamFinance: false,
      createdBy: 'test',
      enforceActor: false,
    );
    await pumpUiFrames(tester);
    expect(find.text('Worker'), findsNothing);
    expect(find.text('Персональная разбивка скрыта'), findsOneWidget);
  });
}
