import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/organizations/models/organization_access_grant.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/organization_access_service.dart';
import 'package:wesios/features/organizations/services/organization_context.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';
import 'package:wesios/features/team/team_stats_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-team-stats-org-ui-');
    Hive.init(temp.path);
    if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(TaskStatusAdapter());
    if (!Hive.isAdapterRegistered(11)) Hive.registerAdapter(TaskPriorityAdapter());
    if (!Hive.isAdapterRegistered(12)) Hive.registerAdapter(SubTaskAdapter());
    if (!Hive.isAdapterRegistered(13)) Hive.registerAdapter(TaskModelAdapter());
    if (!Hive.isAdapterRegistered(20)) Hive.registerAdapter(TeamPermissionsAdapter());
    if (!Hive.isAdapterRegistered(21)) Hive.registerAdapter(EmployeeModelAdapter());
    if (!Hive.isAdapterRegistered(80)) Hive.registerAdapter(OrganizationStatusAdapter());
    if (!Hive.isAdapterRegistered(81)) Hive.registerAdapter(OrganizationModelAdapter());
    if (!Hive.isAdapterRegistered(82)) Hive.registerAdapter(OrganizationAccessGrantAdapter());

    await Hive.openBox<dynamic>('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<OrganizationAccessGrant>(OrganizationAccessService.boxName);
    await Hive.openBox<TaskModel>('wesios_tasks');
  });

  setUp(() async {
    await Hive.box<dynamic>('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<OrganizationAccessGrant>(OrganizationAccessService.boxName).clear();
    await Hive.box<TaskModel>('wesios_tasks').clear();
    await OrganizationService.ensureBaseline();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<EmployeeModel> addEmployee(
    String id,
    String name, {
    bool seeOthers = false,
  }) async {
    final employee = EmployeeModel(
      id: id,
      login: id,
      fullName: name,
      createdAt: DateTime(2026, 1, 1),
      permissions: TeamPermissions(
        moduleList: const [TeamModules.tasks],
        canSeeOthersStats: seeOthers,
      ),
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(id, employee);
    return employee;
  }

  testWidgets('legacy canSeeOthersStats stays inside only/subtree org context',
      (tester) async {
    final child = await OrganizationService.create(
      name: 'Studio A',
      parentId: OrganizationModel.rootId,
      createdBy: 'test',
    );
    final manager = await addEmployee('manager', 'Manager', seeOthers: true);
    final rootWorker = await addEmployee('root-worker', 'Root Worker');
    final childWorker = await addEmployee('child-worker', 'Child Worker');

    await OrganizationAccessService.grant(
      employeeId: manager.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: true,
      permissions: const [OrganizationPermissions.view],
      enforceActor: false,
    );
    await OrganizationAccessService.grant(
      employeeId: rootWorker.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [OrganizationPermissions.view],
      enforceActor: false,
    );
    await OrganizationAccessService.grant(
      employeeId: childWorker.id,
      organizationId: child.id,
      includeSubtree: false,
      permissions: const [OrganizationPermissions.view],
      enforceActor: false,
    );

    await Hive.box<TaskModel>('wesios_tasks').put(
      'root-task',
      TaskModel(
        id: 'root-task',
        title: 'Root Task',
        createdAt: DateTime(2026, 8, 1),
        assignee: rootWorker.id,
        responsibleEmployeeId: rootWorker.id,
        organizationId: OrganizationModel.rootId,
      ),
    );
    await Hive.box<TaskModel>('wesios_tasks').put(
      'child-task',
      TaskModel(
        id: 'child-task',
        title: 'Child Task',
        createdAt: DateTime(2026, 8, 1),
        assignee: childWorker.id,
        responsibleEmployeeId: childWorker.id,
        organizationId: child.id,
      ),
    );

    await Hive.box<dynamic>('wesios_settings')
        .put('team_current_employee', manager.id);
    await OrganizationContext.initialize();
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);
    await OrganizationContext.setScope(OrganizationScope.only);

    await tester.pumpWidget(const MaterialApp(home: TeamStatsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Manager'), findsOneWidget);
    expect(find.text('Root Worker'), findsOneWidget);
    expect(find.text('Child Worker'), findsNothing,
        reason: 'legacy canSeeOthersStats must not escape root-only context');

    await OrganizationContext.setScope(OrganizationScope.subtree);
    await tester.pumpAndSettle();
    expect(find.text('Child Worker'), findsOneWidget,
        reason: 'the same manager may see child stats only after subtree context is active');
  });
}
