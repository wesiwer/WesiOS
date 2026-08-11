import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/crm/models/crm_models.dart';
import 'package:wesios/features/crm/services/crm_service.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/models/transaction_audit_model.dart';
import 'package:wesios/features/organizations/services/organization_context.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/tasks/services/task_service.dart';
import 'package:wesios/features/treasury/models/account_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/account_service.dart';
import 'package:wesios/features/treasury/services/treasury_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-physical-ownership-');
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
    if (!Hive.isAdapterRegistered(80)) Hive.registerAdapter(OrganizationStatusAdapter());
    if (!Hive.isAdapterRegistered(81)) Hive.registerAdapter(OrganizationModelAdapter());
    if (!Hive.isAdapterRegistered(85)) Hive.registerAdapter(TransactionAuditModelAdapter());
    if (!Hive.isAdapterRegistered(86)) Hive.registerAdapter(TransactionSourceAdapter());

    await Hive.openBox('wesios_settings');
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<AccountModel>('wesios_accounts');
    await Hive.openBox<TransactionModel>('wesios_treasury');
    await Hive.openBox<TransactionAuditModel>('wesios_transaction_audit');
    await Hive.openBox<TaskModel>('wesios_tasks');
    await Hive.openBox<dynamic>(CrmService.boxName);
  });

  setUp(() async {
    await Hive.box('wesios_settings').clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<AccountModel>('wesios_accounts').clear();
    await Hive.box<TransactionModel>('wesios_treasury').clear();
    await Hive.box<TransactionAuditModel>('wesios_transaction_audit').clear();
    await Hive.box<TaskModel>('wesios_tasks').clear();
    await Hive.box<dynamic>(CrmService.boxName).clear();
    await OrganizationService.ensureBaseline();
    await OrganizationContext.initialize();
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);
    await OrganizationContext.setScope(OrganizationScope.only);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('service-created account, transaction, recurring, task and CRM rows are physically owned', () async {
    final account = await AccountService.create(
      name: 'Owned account',
      organizationId: OrganizationModel.rootId,
    );
    expect(account.organizationId, OrganizationModel.rootId);

    await TreasuryService().addTransaction(TransactionModel(
      id: 'normal-new',
      title: 'Normal',
      amount: 100,
      type: TransactionType.income,
      date: DateTime(2026, 8, 1),
    ));
    await TreasuryService().addTransaction(TransactionModel(
      id: 'recurring-new',
      title: 'Recurring',
      amount: 50,
      type: TransactionType.expense,
      date: DateTime(2026, 8, 1),
      isRecurring: true,
      recurringPeriod: RecurringPeriod.monthly,
    ));
    final normal = Hive.box<TransactionModel>('wesios_treasury').get('normal-new')!;
    final recurring = Hive.box<TransactionModel>('wesios_treasury').get('recurring-new')!;
    expect(normal.organizationId, OrganizationModel.rootId);
    expect(normal.accountId, isNotNull);
    expect(recurring.organizationId, OrganizationModel.rootId);
    expect(recurring.accountId, isNotNull);

    await TaskService().save(TaskModel(
      id: 'task-new',
      title: 'Owned task',
      createdAt: DateTime(2026, 8, 1),
    ));
    final task = Hive.box<TaskModel>('wesios_tasks').get('task-new')!;
    expect(task.organizationId, OrganizationModel.rootId);

    final now = DateTime(2026, 8, 1);
    await CrmService.saveClient(CrmClient(
      id: 'client-new',
      name: 'Owned client',
      createdAt: now,
      updatedAt: now,
    ));
    final client = (await CrmService.clientsRaw()).single;
    expect(client.organizationId, OrganizationModel.rootId);

    await CrmService.saveDeal(CrmDeal(
      id: 'deal-new',
      clientId: client.id,
      title: 'Owned deal',
      createdAt: now,
      updatedAt: now,
    ));
    final deal = (await CrmService.dealsRaw()).single;
    expect(deal.organizationId, OrganizationModel.rootId);
  });
}
