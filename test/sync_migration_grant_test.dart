import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
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
    temp = await Directory.systemTemp.createTemp('wesios-sync-migration-grant-');
    Hive.init(temp.path);
    if (!Hive.isAdapterRegistered(20)) Hive.registerAdapter(TeamPermissionsAdapter());
    if (!Hive.isAdapterRegistered(21)) Hive.registerAdapter(EmployeeModelAdapter());
    if (!Hive.isAdapterRegistered(80)) Hive.registerAdapter(OrganizationStatusAdapter());
    if (!Hive.isAdapterRegistered(81)) Hive.registerAdapter(OrganizationModelAdapter());
    if (!Hive.isAdapterRegistered(82)) Hive.registerAdapter(OrganizationAccessGrantAdapter());

    await Hive.openBox<dynamic>('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<OrganizationAccessGrant>(OrganizationAccessService.boxName);
  });

  setUp(() async {
    await Hive.box<dynamic>('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<OrganizationAccessGrant>(OrganizationAccessService.boxName).clear();
    await OrganizationService.ensureBaseline();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<EmployeeModel> addEmployee(
    String id,
    TeamPermissions permissions, {
    bool owner = false,
  }) async {
    final employee = EmployeeModel(
      id: id,
      login: id,
      fullName: id,
      createdAt: DateTime(2024, 1, 1),
      isOwner: owner,
      permissions: owner ? TeamPermissions.owner : permissions,
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(id, employee);
    return employee;
  }

  Map<String, dynamic> grantFields({
    required EmployeeModel employee,
    required List<String> permissions,
    required bool includeSubtree,
    required bool canViewTeamFinance,
    bool canViewSelfFinance = true,
    String createdBy = 'migration',
  }) {
    final now = DateTime(2026, 8, 10);
    return {
      'id': '${employee.id}::${OrganizationModel.rootId}',
      'employeeId': employee.id,
      'organizationId': OrganizationModel.rootId,
      'includeSubtree': includeSubtree,
      'canViewTeamFinance': canViewTeamFinance,
      'canViewSelfFinance': canViewSelfFinance,
      'permissions': permissions,
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'createdBy': createdBy,
    };
  }

  test('root-only view migration grant for ordinary legacy employee is accepted',
      () async {
    final employee = await addEmployee(
      'worker',
      const TeamPermissions(moduleList: [TeamModules.tasks]),
    );
    final accepted = await OrganizationGrantsSync().applyFields(
      grantFields(
        employee: employee,
        permissions: const [OrganizationPermissions.view],
        includeSubtree: false,
        canViewTeamFinance: false,
      ),
    );
    expect(accepted, isTrue);
    final grant = (await OrganizationAccessService.grantsFor(employee.id)).single;
    expect(grant.createdBy, 'migration/internal');
    expect(grant.includeSubtree, isFalse);
    expect(grant.permissions, [OrganizationPermissions.view]);
  });

  test('finance-visible legacy employee receives only the exact migration shape',
      () async {
    final employee = await addEmployee(
      'finance-worker',
      const TeamPermissions(
        moduleList: [TeamModules.treasury],
        canSeeOthersStats: true,
      ),
    );
    const expected = [
      OrganizationPermissions.view,
      OrganizationPermissions.viewFinance,
      OrganizationPermissions.createTransactions,
      OrganizationPermissions.editTransactions,
      OrganizationPermissions.manageAccounts,
      OrganizationPermissions.manageRecurring,
      OrganizationPermissions.viewForecast,
    ];
    expect(
      await OrganizationGrantsSync().applyFields(
        grantFields(
          employee: employee,
          permissions: expected,
          includeSubtree: false,
          canViewTeamFinance: true,
        ),
      ),
      isTrue,
    );
    final grant = (await OrganizationAccessService.grantsFor(employee.id)).single;
    expect(grant.permissions.toSet(), expected.toSet());
    expect(grant.canViewTeamFinance, isTrue);
  });

  test('migration label cannot mint subtree, admin, or incomplete grants for non-owner',
      () async {
    final employee = await addEmployee(
      'worker',
      const TeamPermissions(moduleList: [TeamModules.tasks]),
    );
    expect(
      await OrganizationGrantsSync().applyFields(
        grantFields(
          employee: employee,
          permissions: const [
            OrganizationPermissions.view,
            OrganizationPermissions.manageMembers,
          ],
          includeSubtree: false,
          canViewTeamFinance: false,
        ),
      ),
      isFalse,
    );
    expect(
      await OrganizationGrantsSync().applyFields(
        grantFields(
          employee: employee,
          permissions: const [OrganizationPermissions.view],
          includeSubtree: true,
          canViewTeamFinance: false,
        ),
      ),
      isFalse,
    );
    expect(
      await OrganizationGrantsSync().applyFields(
        grantFields(
          employee: employee,
          permissions: const [OrganizationPermissions.view],
          includeSubtree: false,
          canViewTeamFinance: false,
          canViewSelfFinance: false,
        ),
      ),
      isFalse,
    );
    expect(await OrganizationAccessService.grantsFor(employee.id), isEmpty);
  });

  test('transport sync identity can never authorize a grant', () async {
    final employee = await addEmployee(
      'worker',
      const TeamPermissions(moduleList: [TeamModules.tasks]),
    );
    expect(
      await OrganizationGrantsSync().applyFields(
        grantFields(
          employee: employee,
          permissions: const [OrganizationPermissions.view],
          includeSubtree: false,
          canViewTeamFinance: false,
          createdBy: 'sync',
        ),
      ),
      isFalse,
    );
  });

  test('owner migration grant is accepted only as full root subtree grant',
      () async {
    final owner = await addEmployee('owner', TeamPermissions.owner, owner: true);
    expect(
      await OrganizationGrantsSync().applyFields(
        grantFields(
          employee: owner,
          permissions: OrganizationPermissions.all,
          includeSubtree: true,
          canViewTeamFinance: true,
        ),
      ),
      isTrue,
    );
    await Hive.box<OrganizationAccessGrant>(OrganizationAccessService.boxName).clear();
    expect(
      await OrganizationGrantsSync().applyFields(
        grantFields(
          employee: owner,
          permissions: const [OrganizationPermissions.view],
          includeSubtree: true,
          canViewTeamFinance: true,
        ),
      ),
      isFalse,
    );
  });
}
