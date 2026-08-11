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
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-crm-interaction-integrity-');
    Hive.init(temp.path);
    if (!Hive.isAdapterRegistered(20)) Hive.registerAdapter(TeamPermissionsAdapter());
    if (!Hive.isAdapterRegistered(21)) Hive.registerAdapter(EmployeeModelAdapter());
    if (!Hive.isAdapterRegistered(80)) Hive.registerAdapter(OrganizationStatusAdapter());
    if (!Hive.isAdapterRegistered(81)) Hive.registerAdapter(OrganizationModelAdapter());
    if (!Hive.isAdapterRegistered(82)) {
      Hive.registerAdapter(OrganizationAccessGrantAdapter());
    }

    await Hive.openBox<dynamic>('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<OrganizationAccessGrant>(OrganizationAccessService.boxName);
    await Hive.openBox<dynamic>(CrmService.boxName);
  });

  setUp(() async {
    await Hive.box<dynamic>('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<OrganizationAccessGrant>(OrganizationAccessService.boxName).clear();
    await Hive.box<dynamic>(CrmService.boxName).clear();
    await OrganizationService.ensureBaseline();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<EmployeeModel> addEmployee(String id) async {
    final employee = EmployeeModel(
      id: id,
      login: id,
      fullName: id,
      createdAt: DateTime(2026, 1, 1),
      permissions: const TeamPermissions(moduleList: [TeamModules.crm]),
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(id, employee);
    return employee;
  }

  Future<void> signIn(EmployeeModel employee) async {
    await Hive.box<dynamic>('wesios_settings')
        .put('team_current_employee', employee.id);
    await OrganizationContext.initialize();
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);
    await OrganizationContext.setScope(OrganizationScope.only);
  }

  Future<({EmployeeModel alice, EmployeeModel bob, DateTime now})> seed() async {
    final alice = await addEmployee('alice');
    final bob = await addEmployee('bob');
    await OrganizationAccessService.grant(
      employeeId: alice.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [OrganizationPermissions.view],
      enforceActor: false,
    );
    final now = DateTime(2026, 8, 1);
    await CrmService.saveClient(CrmClient(
      id: 'alice-client',
      name: 'Alice client',
      createdAt: now,
      updatedAt: now,
      organizationId: OrganizationModel.rootId,
      ownerEmployeeId: alice.id,
    ));
    await CrmService.saveClient(CrmClient(
      id: 'bob-client',
      name: 'Bob client',
      createdAt: now,
      updatedAt: now,
      organizationId: OrganizationModel.rootId,
      ownerEmployeeId: bob.id,
    ));
    await CrmService.saveDeal(CrmDeal(
      id: 'alice-deal',
      clientId: 'alice-client',
      title: 'Alice deal',
      createdAt: now,
      updatedAt: now,
      organizationId: OrganizationModel.rootId,
      responsibleEmployeeId: alice.id,
    ));
    return (alice: alice, bob: bob, now: now);
  }

  test('owned deal cannot bridge an interaction into another client', () async {
    final data = await seed();
    await signIn(data.alice);

    await expectLater(
      CrmService.saveInteraction(CrmInteraction(
        id: 'bridge',
        clientId: 'bob-client',
        dealId: 'alice-deal',
        title: 'Forbidden bridge',
        details: 'must fail',
        at: data.now,
      )),
      throwsA(isA<StateError>()),
    );

    expect(
      (await CrmService.interactionsRaw()).where((row) => row.id == 'bridge'),
      isEmpty,
    );
  });

  test('existing hidden interaction cannot be stolen by re-parenting its id',
      () async {
    final data = await seed();
    await CrmService.saveInteraction(CrmInteraction(
      id: 'hidden-interaction',
      clientId: 'bob-client',
      title: 'Bob private note',
      at: data.now,
    ));
    await signIn(data.alice);

    await expectLater(
      CrmService.saveInteraction(CrmInteraction(
        id: 'hidden-interaction',
        clientId: 'alice-client',
        dealId: 'alice-deal',
        title: 'Attempted takeover',
        at: data.now,
      )),
      throwsA(isA<StateError>()),
    );

    final stored = (await CrmService.interactionsRaw())
        .singleWhere((row) => row.id == 'hidden-interaction');
    expect(stored.clientId, 'bob-client');
    expect(stored.title, 'Bob private note');
  });
}
