import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/organizations/models/organization_access_grant.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/organization_access_service.dart';
import 'package:wesios/features/organizations/services/organization_migration_service.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';
import 'package:wesios/features/treasury/models/account_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-org-legacy-rehearsal-');
    Hive.init(temp.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(TransactionModelAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TransactionTypeAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(RecurringPeriodAdapter());
    if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(TaskStatusAdapter());
    if (!Hive.isAdapterRegistered(11)) Hive.registerAdapter(TaskPriorityAdapter());
    if (!Hive.isAdapterRegistered(12)) Hive.registerAdapter(SubTaskAdapter());
    if (!Hive.isAdapterRegistered(13)) Hive.registerAdapter(TaskModelAdapter());
    if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(AccountKindAdapter());
    if (!Hive.isAdapterRegistered(15)) Hive.registerAdapter(AccountModelAdapter());
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
    await Hive.openBox<AccountModel>(OrganizationMigrationService.accountBoxName);
    await Hive.openBox<TransactionModel>(OrganizationMigrationService.treasuryBoxName);
    await Hive.openBox<TaskModel>(OrganizationMigrationService.taskBoxName);
    await Hive.openBox<dynamic>(OrganizationMigrationService.crmBoxName);
    await Hive.openBox<dynamic>(OrganizationMigrationService.logBoxName);
  });

  setUp(() async {
    await Hive.box<dynamic>('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<OrganizationAccessGrant>(OrganizationAccessService.boxName).clear();
    await Hive.box<AccountModel>(OrganizationMigrationService.accountBoxName).clear();
    await Hive.box<TransactionModel>(OrganizationMigrationService.treasuryBoxName).clear();
    await Hive.box<TaskModel>(OrganizationMigrationService.taskBoxName).clear();
    await Hive.box<dynamic>(OrganizationMigrationService.crmBoxName).clear();
    await Hive.box<dynamic>(OrganizationMigrationService.logBoxName).clear();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('legacy fixture migrates once to Wesi Inc and never into Wesi Beats', () async {
    final owner = EmployeeModel(
      id: 'legacy-owner',
      login: 'legacy-owner',
      fullName: 'Legacy Owner',
      createdAt: DateTime(2024, 1, 1),
      isOwner: true,
      permissions: TeamPermissions.owner,
    );
    final employee = EmployeeModel(
      id: 'legacy-worker',
      login: 'legacy-worker',
      fullName: 'Legacy Worker',
      createdAt: DateTime(2024, 1, 2),
      permissions: const TeamPermissions(moduleList: [TeamModules.tasks]),
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(owner.id, owner);
    await Hive.box<EmployeeModel>(TeamService.boxName).put(employee.id, employee);

    await Hive.box<AccountModel>(OrganizationMigrationService.accountBoxName).put(
      'legacy-account',
      AccountModel(
        id: 'legacy-account',
        name: 'Legacy cash',
        kind: AccountKind.cash,
        openingBalance: 1500,
        createdAt: DateTime(2024, 2, 1),
        organizationId: null,
      ),
    );
    await Hive.box<TransactionModel>(OrganizationMigrationService.treasuryBoxName).put(
      'legacy-tx',
      TransactionModel(
        id: 'legacy-tx',
        title: 'Legacy income',
        amount: 2500,
        type: TransactionType.income,
        date: DateTime(2024, 2, 2),
        accountId: 'legacy-account',
        organizationId: null,
        ownerEmployeeId: employee.id,
      ),
    );
    await Hive.box<TaskModel>(OrganizationMigrationService.taskBoxName).put(
      'legacy-task',
      TaskModel(
        id: 'legacy-task',
        title: 'Legacy task',
        createdAt: DateTime(2024, 2, 3),
        assignee: employee.id,
        organizationId: null,
      ),
    );

    final crm = Hive.box<dynamic>(OrganizationMigrationService.crmBoxName);
    await crm.put(
      'clients_v1',
      jsonEncode([
        {
          'id': 'legacy-client',
          'name': 'Legacy Client',
          'createdAt': DateTime(2024, 2, 4).toIso8601String(),
          'updatedAt': DateTime(2024, 2, 4).toIso8601String(),
        }
      ]),
    );
    await crm.put(
      'deals_v1',
      jsonEncode([
        {
          'id': 'legacy-deal',
          'clientId': 'legacy-client',
          'title': 'Legacy Deal',
          'amount': 3000,
          'createdAt': DateTime(2024, 2, 5).toIso8601String(),
          'updatedAt': DateTime(2024, 2, 5).toIso8601String(),
        }
      ]),
    );

    await OrganizationMigrationService.runV1();

    final root = await OrganizationService.byId(OrganizationModel.rootId);
    final beats = await OrganizationService.byId(OrganizationModel.wesiBeatsId);
    expect(root, isNotNull);
    expect(root!.isRoot, isTrue);
    expect(beats, isNotNull);
    expect(beats!.parentId, OrganizationModel.rootId);

    final migratedAccount = Hive.box<AccountModel>(
      OrganizationMigrationService.accountBoxName,
    ).get('legacy-account')!;
    final migratedTx = Hive.box<TransactionModel>(
      OrganizationMigrationService.treasuryBoxName,
    ).get('legacy-tx')!;
    final migratedTask = Hive.box<TaskModel>(
      OrganizationMigrationService.taskBoxName,
    ).get('legacy-task')!;
    expect(migratedAccount.organizationId, OrganizationModel.rootId);
    expect(migratedTx.organizationId, OrganizationModel.rootId);
    expect(migratedTask.organizationId, OrganizationModel.rootId);
    expect(migratedTask.responsibleEmployeeId, employee.id);

    final clients = jsonDecode(crm.get('clients_v1') as String) as List;
    final deals = jsonDecode(crm.get('deals_v1') as String) as List;
    expect(clients.single['organizationId'], OrganizationModel.rootId);
    expect(clients.single['ownerEmployeeId'], isNull);
    expect(deals.single['organizationId'], OrganizationModel.rootId);
    expect(deals.single['responsibleEmployeeId'], isNull);

    expect(
      Hive.box<AccountModel>(OrganizationMigrationService.accountBoxName)
          .values
          .where((a) => a.organizationId == OrganizationModel.wesiBeatsId),
      isEmpty,
    );
    expect(
      Hive.box<TransactionModel>(OrganizationMigrationService.treasuryBoxName)
          .values
          .where((t) => t.organizationId == OrganizationModel.wesiBeatsId),
      isEmpty,
    );
    expect(
      Hive.box<TaskModel>(OrganizationMigrationService.taskBoxName)
          .values
          .where((t) => t.organizationId == OrganizationModel.wesiBeatsId),
      isEmpty,
    );

    final migrationLog = Hive.box<dynamic>(OrganizationMigrationService.logBoxName)
        .get(OrganizationMigrationService.migrationKey) as Map;
    expect(migrationLog['completed'], isTrue);
    expect(migrationLog['accountsUpdated'], 1);
    expect(migrationLog['transactionsUpdated'], 1);
    expect(migrationLog['tasksUpdated'], 1);
    expect(migrationLog['crmClientsUpdated'], 1);
    expect(migrationLog['crmDealsUpdated'], 1);

    final beforeSecondRun = jsonEncode(migrationLog);
    await OrganizationMigrationService.runV1();
    final secondLog = Hive.box<dynamic>(OrganizationMigrationService.logBoxName)
        .get(OrganizationMigrationService.migrationKey) as Map;
    expect(jsonEncode(secondLog), beforeSecondRun);

    final ownerGrant = (await OrganizationAccessService.grantsFor(owner.id)).single;
    final workerGrant = (await OrganizationAccessService.grantsFor(employee.id)).single;
    expect(ownerGrant.organizationId, OrganizationModel.rootId);
    expect(ownerGrant.includeSubtree, isTrue);
    expect(workerGrant.organizationId, OrganizationModel.rootId);
    expect(workerGrant.includeSubtree, isFalse);
  });
}
