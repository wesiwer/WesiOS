import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/organizations/models/organization_access_grant.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/organization_access_service.dart';
import 'package:wesios/features/organizations/services/organization_context.dart';
import 'package:wesios/features/organizations/services/organization_migration_service.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';
import 'package:wesios/features/treasury/models/account_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/treasury_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-org-migration-');
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

    await Hive.openBox('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<OrganizationAccessGrant>(OrganizationAccessService.boxName);
    await Hive.openBox<AccountModel>('wesios_accounts');
    await Hive.openBox<TransactionModel>('wesios_treasury');
    await Hive.openBox<TaskModel>('wesios_tasks');
    await Hive.openBox<dynamic>('wesios_crm');
    await Hive.openBox<dynamic>(OrganizationMigrationService.logBoxName);
  });

  setUp(() async {
    await Hive.box('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<OrganizationAccessGrant>(OrganizationAccessService.boxName).clear();
    await Hive.box<AccountModel>('wesios_accounts').clear();
    await Hive.box<TransactionModel>('wesios_treasury').clear();
    await Hive.box<TaskModel>('wesios_tasks').clear();
    await Hive.box<dynamic>('wesios_crm').clear();
    await Hive.box<dynamic>(OrganizationMigrationService.logBoxName).clear();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('legacy money/tasks/CRM are physically backfilled to Wesi Beats once', () async {
    final accounts = Hive.box<AccountModel>('wesios_accounts');
    await accounts.put(
      'main',
      AccountModel(
        id: 'main',
        name: 'Legacy main',
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    final treasury = Hive.box<TransactionModel>('wesios_treasury');
    await treasury.put(
      'legacy-tx',
      TransactionModel(
        id: 'legacy-tx',
        title: 'Legacy income',
        amount: 100,
        type: TransactionType.income,
        date: DateTime(2026, 1, 2),
      ),
    );
    final tasks = Hive.box<TaskModel>('wesios_tasks');
    await tasks.put(
      'legacy-task',
      TaskModel(
        id: 'legacy-task',
        title: 'Legacy task',
        createdAt: DateTime(2026, 1, 3),
      ),
    );
    final crm = Hive.box<dynamic>('wesios_crm');
    await crm.put('clients_v1', jsonEncode([
      {
        'id': 'client-1',
        'name': 'Client',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      }
    ]));
    await crm.put('deals_v1', jsonEncode([
      {
        'id': 'deal-1',
        'clientId': 'client-1',
        'title': 'Deal',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      }
    ]));

    await OrganizationMigrationService.runV1();

    expect(accounts.get('main')!.organizationId, OrganizationModel.wesiBeatsId);
    expect(treasury.get('legacy-tx')!.organizationId, OrganizationModel.wesiBeatsId);
    expect(tasks.get('legacy-task')!.organizationId, OrganizationModel.wesiBeatsId);
    expect(
      tasks.get('legacy-task')!.tags,
      contains('${TaskModel.organizationTagPrefix}${OrganizationModel.wesiBeatsId}'),
    );

    final clientJson = (jsonDecode('${crm.get('clients_v1')}') as List).single as Map;
    final dealJson = (jsonDecode('${crm.get('deals_v1')}') as List).single as Map;
    expect(clientJson['organizationId'], OrganizationModel.wesiBeatsId);
    expect(dealJson['organizationId'], OrganizationModel.wesiBeatsId);

    final log = Hive.box<dynamic>(OrganizationMigrationService.logBoxName);
    final first = Map<String, dynamic>.from(
      log.get(OrganizationMigrationService.migrationKey) as Map,
    );
    expect(first['completed'], isTrue);
    expect(first['accountsUpdated'], 1);
    expect(first['transactionsUpdated'], 1);

    await OrganizationMigrationService.runV1();
    final second = Map<String, dynamic>.from(
      log.get(OrganizationMigrationService.migrationKey) as Map,
    );
    expect(second['completedAt'], first['completedAt']);
    expect(accounts.get('main')!.organizationId, OrganizationModel.wesiBeatsId);
  });

  test('only and subtree select different Treasury sets', () async {
    await OrganizationMigrationService.runV1();
    final it = await OrganizationService.create(
      name: 'IT',
      parentId: OrganizationModel.rootId,
      createdBy: 'test',
    );
    final studio = await OrganizationService.create(
      name: 'Studio A',
      parentId: it.id,
      createdBy: 'test',
    );

    final service = TreasuryService();
    await service.addTransaction(TransactionModel(
      id: 'it-income',
      title: 'IT',
      amount: 100,
      type: TransactionType.income,
      date: DateTime.now(),
      organizationId: it.id,
    ));
    await service.addTransaction(TransactionModel(
      id: 'studio-income',
      title: 'Studio',
      amount: 200,
      type: TransactionType.income,
      date: DateTime.now(),
      organizationId: studio.id,
    ));

    await OrganizationContext.selectOrganization(it.id);
    await OrganizationContext.setScope(OrganizationScope.only);
    expect((await service.getAllTransactions()).map((e) => e.id), ['it-income']);

    await OrganizationContext.setScope(OrganizationScope.subtree);
    expect(
      (await service.getAllTransactions()).map((e) => e.id).toSet(),
      {'it-income', 'studio-income'},
    );

    await OrganizationContext.selectOrganization(studio.id);
    await OrganizationContext.setScope(OrganizationScope.only);
    expect((await service.getAllTransactions()).map((e) => e.id), ['studio-income']);
  });
}
