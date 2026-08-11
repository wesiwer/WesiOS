import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/crm/models/crm_models.dart';
import 'package:wesios/features/crm/services/crm_service.dart';
import 'package:wesios/features/organizations/models/organization_access_grant.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/organization_access_service.dart';
import 'package:wesios/features/organizations/services/organization_context.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/tasks/services/task_service.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-org-scope-isolation-');
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

    await Hive.openBox('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<OrganizationAccessGrant>(OrganizationAccessService.boxName);
    await Hive.openBox<TaskModel>('wesios_tasks');
    await Hive.openBox<dynamic>(CrmService.boxName);
  });

  setUp(() async {
    await Hive.box('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<OrganizationAccessGrant>(OrganizationAccessService.boxName).clear();
    await Hive.box<TaskModel>('wesios_tasks').clear();
    await Hive.box<dynamic>(CrmService.boxName).clear();
    await OrganizationService.ensureBaseline();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<EmployeeModel> employee() async {
    final value = EmployeeModel(
      id: 'employee-a',
      login: 'employee-a',
      fullName: 'Employee A',
      createdAt: DateTime(2026, 1, 1),
      permissions: const TeamPermissions(
        moduleList: [TeamModules.tasks, TeamModules.crm],
      ),
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(value.id, value);
    return value;
  }

  Future<void> signIn(String id) =>
      Hive.box('wesios_settings').put('team_current_employee', id);

  test('ordinary employee cannot read or mutate Tasks outside granted organization', () async {
    final a = await OrganizationService.create(
      name: 'Studio A',
      parentId: OrganizationModel.rootId,
      createdBy: 'setup',
    );
    final b = await OrganizationService.create(
      name: 'Studio B',
      parentId: OrganizationModel.rootId,
      createdBy: 'setup',
    );
    final user = await employee();

    final service = TaskService();
    await service.save(TaskModel(
      id: 'task-a',
      title: 'A task',
      createdAt: DateTime(2026, 8, 1),
      assignee: user.id,
      organizationId: a.id,
      responsibleEmployeeId: user.id,
    ));
    await service.save(TaskModel(
      id: 'task-b',
      title: 'B task',
      createdAt: DateTime(2026, 8, 1),
      assignee: user.id,
      organizationId: b.id,
      responsibleEmployeeId: user.id,
    ));

    await OrganizationAccessService.grant(
      employeeId: user.id,
      organizationId: a.id,
      includeSubtree: false,
      permissions: const [OrganizationPermissions.view],
      enforceActor: false,
    );
    await signIn(user.id);
    await OrganizationContext.initialize();
    await OrganizationContext.selectOrganization(a.id);
    await OrganizationContext.setScope(OrganizationScope.only);

    final visible = await service.getAll();
    expect(visible.map((t) => t.id), ['task-a']);

    final foreign = (await service.getAllRaw()).singleWhere((t) => t.id == 'task-b');
    await expectLater(
      service.save(foreign.copyWith(title: 'stolen edit')),
      throwsStateError,
    );
    expect(
      (await service.getAllRaw()).singleWhere((t) => t.id == 'task-b').title,
      'B task',
    );
  });

  test('ordinary employee cannot read or mutate CRM outside granted organization', () async {
    final a = await OrganizationService.create(
      name: 'Studio A',
      parentId: OrganizationModel.rootId,
      createdBy: 'setup',
    );
    final b = await OrganizationService.create(
      name: 'Studio B',
      parentId: OrganizationModel.rootId,
      createdBy: 'setup',
    );
    final user = await employee();
    final now = DateTime(2026, 8, 1);

    await CrmService.saveClient(CrmClient(
      id: 'client-a',
      name: 'Client A',
      createdAt: now,
      updatedAt: now,
      organizationId: a.id,
      ownerEmployeeId: user.id,
    ));
    await CrmService.saveClient(CrmClient(
      id: 'client-b',
      name: 'Client B',
      createdAt: now,
      updatedAt: now,
      organizationId: b.id,
      ownerEmployeeId: user.id,
    ));

    await OrganizationAccessService.grant(
      employeeId: user.id,
      organizationId: a.id,
      includeSubtree: false,
      permissions: const [OrganizationPermissions.view],
      enforceActor: false,
    );
    await signIn(user.id);
    await OrganizationContext.initialize();
    await OrganizationContext.selectOrganization(a.id);
    await OrganizationContext.setScope(OrganizationScope.only);

    final visible = await CrmService.clients();
    expect(visible.map((c) => c.id), ['client-a']);

    final foreign = (await CrmService.clientsRaw())
        .singleWhere((c) => c.id == 'client-b');
    await expectLater(
      CrmService.saveClient(foreign.copyWith(notes: 'stolen edit')),
      throwsStateError,
    );
    expect(
      (await CrmService.clientsRaw()).singleWhere((c) => c.id == 'client-b').notes,
      isEmpty,
    );
  });
}
