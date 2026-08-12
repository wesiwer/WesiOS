import 'dart:io';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-team-stats-org-');
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

  Future<Set<String>> visiblePeopleIds() async {
    final scope = await OrganizationContext.effectiveOrganizationIds();
    final result = <String>{};
    for (final employee in TeamService.all) {
      final ids = await OrganizationAccessService.visibleOrganizationIds(
        employeeId: employee.id,
      );
      if (ids.intersection(scope).isNotEmpty) result.add(employee.id);
    }
    return result;
  }

  test('legacy stats permission stays inside only/subtree organization context', () async {
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

    await Hive.box<dynamic>('wesios_settings').put('team_current_employee', manager.id);
    await OrganizationContext.initialize();
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);
    await OrganizationContext.setScope(OrganizationScope.only);

    var ids = await visiblePeopleIds();
    expect(ids, contains(rootWorker.id));
    expect(ids, isNot(contains(childWorker.id)));

    await OrganizationContext.setScope(OrganizationScope.subtree);
    ids = await visiblePeopleIds();
    expect(ids, contains(childWorker.id));
  });

  test('revoking manager grant removes child scope immediately', () async {
    final child = await OrganizationService.create(
      name: 'Studio B',
      parentId: OrganizationModel.rootId,
      createdBy: 'test',
    );
    final manager = await addEmployee('manager-revoke', 'Manager', seeOthers: true);
    final childWorker = await addEmployee('child-revoke', 'Child Worker');

    await OrganizationAccessService.grant(
      employeeId: manager.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: true,
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
    await Hive.box<dynamic>('wesios_settings').put('team_current_employee', manager.id);
    await OrganizationContext.initialize();
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);
    await OrganizationContext.setScope(OrganizationScope.subtree);

    expect(
      await OrganizationAccessService.visibleOrganizationIds(employeeId: manager.id),
      contains(child.id),
    );

    await OrganizationAccessService.revoke(
      manager.id,
      OrganizationModel.rootId,
      enforceActor: false,
    );
    expect(
      await OrganizationAccessService.visibleOrganizationIds(employeeId: manager.id),
      isNot(contains(child.id)),
    );
  });

  test('TeamStats screen listens for scope and grant changes', () {
    final source = File('lib/features/team/team_stats_screen.dart').readAsStringSync();
    expect(source, contains('OrganizationContext.revision.addListener(_changed)'));
    expect(source, contains('OrganizationAccessService.revision.addListener(_changed)'));
    expect(source, contains('epoch == _loadEpoch'));
  });
}
