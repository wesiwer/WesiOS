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
    temp = await Directory.systemTemp.createTemp('wesios-org-privilege-');
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

  Future<EmployeeModel> addEmployee(String id, {bool owner = false}) async {
    final employee = EmployeeModel(
      id: id,
      login: id,
      fullName: id,
      createdAt: DateTime(2026, 1, 1),
      isOwner: owner,
      permissions: owner ? TeamPermissions.owner : const TeamPermissions(),
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(id, employee);
    return employee;
  }

  Future<void> signIn(String employeeId) async {
    await Hive.box('wesios_settings').put('team_current_employee', employeeId);
  }

  test('manager cannot grant a permission the manager does not hold', () async {
    final manager = await addEmployee('manager');
    final target = await addEmployee('target');

    await OrganizationAccessService.grant(
      employeeId: manager.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [
        OrganizationPermissions.view,
        OrganizationPermissions.manageMembers,
      ],
      enforceActor: false,
    );
    await signIn(manager.id);

    expect(
      () => OrganizationAccessService.grant(
        employeeId: target.id,
        organizationId: OrganizationModel.rootId,
        includeSubtree: false,
        permissions: const [
          OrganizationPermissions.view,
          OrganizationPermissions.manageOrgSettings,
        ],
      ),
      throwsA(isA<StateError>()),
    );

    expect(await OrganizationAccessService.grantsFor(target.id), isEmpty);
  });

  test('exact-scope manager cannot grant subtree scope', () async {
    final manager = await addEmployee('manager');
    final target = await addEmployee('target');

    await OrganizationAccessService.grant(
      employeeId: manager.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [
        OrganizationPermissions.view,
        OrganizationPermissions.manageMembers,
      ],
      enforceActor: false,
    );
    await signIn(manager.id);

    expect(
      () => OrganizationAccessService.grant(
        employeeId: target.id,
        organizationId: OrganizationModel.rootId,
        includeSubtree: true,
        permissions: const [OrganizationPermissions.view],
      ),
      throwsA(isA<StateError>()),
    );

    expect(await OrganizationAccessService.grantsFor(target.id), isEmpty);
  });

  test('manager cannot add permissions or subtree to own grant', () async {
    final manager = await addEmployee('manager');

    await OrganizationAccessService.grant(
      employeeId: manager.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [
        OrganizationPermissions.view,
        OrganizationPermissions.manageMembers,
      ],
      enforceActor: false,
    );
    await signIn(manager.id);

    expect(
      () => OrganizationAccessService.grant(
        employeeId: manager.id,
        organizationId: OrganizationModel.rootId,
        includeSubtree: false,
        permissions: const [
          OrganizationPermissions.view,
          OrganizationPermissions.manageMembers,
          OrganizationPermissions.manageOrgSettings,
        ],
      ),
      throwsA(isA<StateError>()),
    );

    expect(
      () => OrganizationAccessService.grant(
        employeeId: manager.id,
        organizationId: OrganizationModel.rootId,
        includeSubtree: true,
        permissions: const [
          OrganizationPermissions.view,
          OrganizationPermissions.manageMembers,
        ],
      ),
      throwsA(isA<StateError>()),
    );

    final grant = (await OrganizationAccessService.grantsFor(manager.id)).single;
    expect(grant.includeSubtree, isFalse);
    expect(grant.permissions, isNot(contains(OrganizationPermissions.manageOrgSettings)));
  });

  test('manager cannot grant team finance access the manager does not hold', () async {
    final manager = await addEmployee('manager');
    final target = await addEmployee('target');

    await OrganizationAccessService.grant(
      employeeId: manager.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [
        OrganizationPermissions.view,
        OrganizationPermissions.manageMembers,
      ],
      canViewTeamFinance: false,
      enforceActor: false,
    );
    await signIn(manager.id);

    expect(
      () => OrganizationAccessService.grant(
        employeeId: target.id,
        organizationId: OrganizationModel.rootId,
        includeSubtree: false,
        permissions: const [OrganizationPermissions.view],
        canViewTeamFinance: true,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('root owner may grant permissions and subtree explicitly', () async {
    final owner = await addEmployee('owner', owner: true);
    final target = await addEmployee('target');
    await signIn(owner.id);

    final grant = await OrganizationAccessService.grant(
      employeeId: target.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: true,
      permissions: OrganizationPermissions.all,
      canViewTeamFinance: true,
    );

    expect(grant.includeSubtree, isTrue);
    expect(grant.permissions, contains(OrganizationPermissions.manageOrgSettings));
    expect(grant.permissions, contains(OrganizationPermissions.manageMembers));
    expect(grant.canViewTeamFinance, isTrue);
  });
}
