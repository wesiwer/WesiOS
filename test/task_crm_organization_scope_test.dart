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
    temp = await Directory.systemTemp.createTemp('wesios-task-crm-scope-');
    Hive.init(temp.path);
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
    await Hive.openBox<TaskModel>('wesios_tasks');
    await Hive.openBox<dynamic>(CrmService.boxName);
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<OrganizationAccessGrant>(OrganizationAccessService.boxName);
  });

  setUp(() async {
    await Hive.box('wesios_settings').clear();
    await Hive.box<TaskModel>('wesios_tasks').clear();
    await Hive.box<dynamic>(CrmService.boxName).clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<OrganizationAccessGrant>(OrganizationAccessService.boxName).clear();
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
      permissions: const TeamPermissions(
        moduleList: [TeamModules.tasks, TeamModules.crm],
      ),
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(id, value);
    return value;
  }

  Future<void> signIn(String id) async {
    await Hive.box('wesios_settings').put('team_current_employee', id);
    await OrganizationContext.initialize();
  }

  test('ordinary employee sees only own task and CRM rows inside current org', () async {
    final alice = await addEmployee('alice');
    final bob = await addEmployee('bob');
    final child = await OrganizationService.create(
      name: 'Studio',
      parentId: OrganizationModel.rootId,
      createdBy: 'seed',
    );
    await OrganizationAccessService.grant(
      employeeId: alice.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [OrganizationPermissions.view],
      enforceActor: false,
    );
    await OrganizationAccessService.grant(
      employeeId: bob.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [OrganizationPermissions.view],
      enforceActor: false,
    );

    final taskBox = Hive.box<TaskModel>('wesios_tasks');
    await taskBox.put(
      'alice-root',
      TaskModel(
        id: 'alice-root',
        title: 'Alice root',
        createdAt: DateTime(2026, 1, 1),
        assignee: alice.id,
        responsibleEmployeeId: alice.id,
        organizationId: OrganizationModel.rootId,
      ),
    );
    await taskBox.put(
      'bob-root',
      TaskModel(
        id: 'bob-root',
        title: 'Bob root',
        createdAt: DateTime(2026, 1, 1),
        assignee: bob.id,
        responsibleEmployeeId: bob.id,
        organizationId: OrganizationModel.rootId,
      ),
    );
    await taskBox.put(
      'alice-child',
      TaskModel(
        id: 'alice-child',
        title: 'Alice child',
        createdAt: DateTime(2026, 1, 1),
        assignee: alice.id,
        responsibleEmployeeId: alice.id,
        organizationId: child.id,
      ),
    );

    await CrmService.saveClient(CrmClient(
      id: 'alice-client',
      name: 'Alice client',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      organizationId: OrganizationModel.rootId,
      ownerEmployeeId: alice.id,
    ));
    await CrmService.saveClient(CrmClient(
      id: 'bob-client',
      name: 'Bob client',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      organizationId: OrganizationModel.rootId,
      ownerEmployeeId: bob.id,
    ));
    await CrmService.saveClient(CrmClient(
      id: 'child-client',
      name: 'Child client',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      organizationId: child.id,
      ownerEmployeeId: alice.id,
    ));

    await signIn(alice.id);
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);
    await OrganizationContext.setScope(OrganizationScope.only);

    expect((await TaskService().getAll()).map((e) => e.id), ['alice-root']);
    expect((await CrmService.clients()).map((e) => e.id), ['alice-client']);
  });

  test('ordinary employee cannot edit another employee task or CRM client', () async {
    final alice = await addEmployee('alice');
    final bob = await addEmployee('bob');
    await OrganizationAccessService.grant(
      employeeId: alice.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [OrganizationPermissions.view],
      enforceActor: false,
    );
    await Hive.box<TaskModel>('wesios_tasks').put(
      'bob-task',
      TaskModel(
        id: 'bob-task',
        title: 'Bob',
        createdAt: DateTime(2026, 1, 1),
        assignee: bob.id,
        responsibleEmployeeId: bob.id,
        organizationId: OrganizationModel.rootId,
      ),
    );
    await CrmService.saveClient(CrmClient(
      id: 'bob-client',
      name: 'Bob client',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      organizationId: OrganizationModel.rootId,
      ownerEmployeeId: bob.id,
    ));

    await signIn(alice.id);
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);
    await OrganizationContext.setScope(OrganizationScope.only);

    expect(
      () => TaskService().save(
        (await TaskService().getAllRaw())
            .singleWhere((t) => t.id == 'bob-task')
            .copyWith(title: 'stolen'),
      ),
      throwsA(isA<StateError>()),
    );
    final bobClient = (await CrmService.clientsRaw())
        .singleWhere((c) => c.id == 'bob-client');
    expect(
      () => CrmService.saveClient(bobClient.copyWith(name: 'stolen')),
      throwsA(isA<StateError>()),
    );
  });
}
