import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/organizations/models/organization_access_grant.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/organization_access_service.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-org-service-auth-');
    Hive.init(temp.path);
    Hive.registerAdapter(TeamPermissionsAdapter());
    Hive.registerAdapter(EmployeeModelAdapter());
    Hive.registerAdapter(OrganizationStatusAdapter());
    Hive.registerAdapter(OrganizationModelAdapter());
    Hive.registerAdapter(OrganizationAccessGrantAdapter());
    await Hive.openBox('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<OrganizationAccessGrant>(OrganizationAccessService.boxName);
  });

  setUp(() async {
    await Hive.box('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<OrganizationAccessGrant>(OrganizationAccessService.boxName).clear();
    await OrganizationService.ensureBaseline();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<EmployeeModel> employee(String id, {bool owner = false}) async {
    final value = EmployeeModel(
      id: id,
      login: id,
      fullName: id,
      createdAt: DateTime(2026, 1, 1),
      isOwner: owner,
      permissions: owner ? TeamPermissions.owner : const TeamPermissions(),
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(id, value);
    return value;
  }

  Future<void> signIn(String id) =>
      Hive.box('wesios_settings').put('team_current_employee', id);

  test('direct create is denied without manage_org_settings', () async {
    final manager = await employee('manager');
    await OrganizationAccessService.grant(
      employeeId: manager.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [OrganizationPermissions.view],
      enforceActor: false,
    );
    await signIn(manager.id);

    await expectLater(
      OrganizationService.create(
        name: 'Forbidden child',
        parentId: OrganizationModel.rootId,
        createdBy: manager.id,
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      (await OrganizationService.all()).where((o) => o.name == 'Forbidden child'),
      isEmpty,
    );
  });

  test('direct update archive and restore enforce domain permission', () async {
    final owner = await employee('owner', owner: true);
    final manager = await employee('manager');
    await signIn(owner.id);
    final child = await OrganizationService.create(
      name: 'Protected',
      parentId: OrganizationModel.rootId,
      createdBy: owner.id,
    );
    await OrganizationAccessService.grant(
      employeeId: manager.id,
      organizationId: child.id,
      includeSubtree: false,
      permissions: const [OrganizationPermissions.view],
    );
    await signIn(manager.id);

    expect(TeamService.current?.id, manager.id);
    expect(TeamService.current?.isOwner, isFalse);
    expect(
      await OrganizationAccessService.can(
        child.id,
        OrganizationPermissions.manageOrgSettings,
        employeeId: manager.id,
      ),
      isFalse,
    );
    await expectLater(
      OrganizationService.update(child, name: 'Nope'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      OrganizationService.archive(child.id),
      throwsA(isA<StateError>()),
    );

    await signIn(owner.id);
    expect(await OrganizationService.archive(child.id), isTrue);
    await signIn(manager.id);
    await expectLater(
      OrganizationService.restore(child.id),
      throwsA(isA<StateError>()),
    );
  });

  test('authorized manager may create within scope but not move outside it', () async {
    final owner = await employee('owner', owner: true);
    final manager = await employee('manager');
    await signIn(owner.id);
    final branch = await OrganizationService.create(
      name: 'Managed',
      parentId: OrganizationModel.rootId,
      createdBy: owner.id,
    );
    final outside = await OrganizationService.create(
      name: 'Outside',
      parentId: OrganizationModel.rootId,
      createdBy: owner.id,
    );
    await OrganizationAccessService.grant(
      employeeId: manager.id,
      organizationId: branch.id,
      includeSubtree: true,
      permissions: const [
        OrganizationPermissions.view,
        OrganizationPermissions.manageOrgSettings,
      ],
    );
    await signIn(manager.id);

    final child = await OrganizationService.create(
      name: 'Allowed',
      parentId: branch.id,
      createdBy: manager.id,
    );
    expect(child.parentId, branch.id);
    await expectLater(
      OrganizationService.update(child, parentId: outside.id),
      throwsA(isA<StateError>()),
    );
  });
}
