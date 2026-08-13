import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/organizations/models/organization_access_grant.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/employee_finance_service.dart';
import 'package:wesios/features/organizations/services/organization_access_service.dart';
import 'package:wesios/features/organizations/services/organization_context.dart';
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

  EmployeeModel employee(String id, {bool owner = false}) => EmployeeModel(
        id: id,
        login: id,
        fullName: id,
        position: owner ? 'CEO' : 'Developer',
        permissions: const TeamPermissions(),
        createdAt: DateTime(2026, 1, 1),
        isOwner: owner,
      );

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-employee-finance-');
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
    await Hive.openBox<TransactionModel>('wesios_treasury');
    await Hive.openBox<AccountModel>('wesios_accounts');
    await Hive.openBox<TaskModel>('wesios_tasks');
    await Hive.openBox<dynamic>('wesios_crm');
  });

  setUp(() async {
    await Hive.box('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<OrganizationAccessGrant>(OrganizationAccessService.boxName).clear();
    await Hive.box<TransactionModel>('wesios_treasury').clear();
    await Hive.box<AccountModel>('wesios_accounts').clear();
    await Hive.box<TaskModel>('wesios_tasks').clear();
    await Hive.box<dynamic>('wesios_crm').clear();
    await OrganizationService.ensureBaseline();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('employee can see self plus allowed org aggregate without seeing coworker rows', () async {
    final dev = employee('dev-a');
    final other = employee('dev-b');
    await Hive.box<EmployeeModel>(TeamService.boxName).putAll({
      dev.id: dev,
      other.id: other,
    });
    await Hive.box('wesios_settings').put('team_current_employee', dev.id);

    await OrganizationAccessService.grant(
      employeeId: dev.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [
        OrganizationPermissions.view,
        OrganizationPermissions.viewFinance,
        OrganizationPermissions.createTransactions,
      ],
      canViewSelfFinance: true,
      canViewTeamFinance: false,
      enforceActor: false,
    );
    await OrganizationAccessService.grant(
      employeeId: other.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [OrganizationPermissions.view],
      canViewSelfFinance: true,
      canViewTeamFinance: false,
      enforceActor: false,
    );
    await OrganizationContext.initialize();
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);
    await OrganizationContext.setScope(OrganizationScope.only);

    final treasury = TreasuryService();
    await treasury.addTransaction(TransactionModel(
      id: 'mine',
      title: 'My contribution',
      amount: 1000,
      type: TransactionType.income,
      date: DateTime.now(),
      organizationId: OrganizationModel.rootId,
      ownerEmployeeId: dev.id,
    ));
    await Hive.box<TransactionModel>('wesios_treasury').put(
      'other',
      TransactionModel(
        id: 'other',
        title: 'Other contribution',
        amount: 9000,
        type: TransactionType.income,
        date: DateTime.now(),
        organizationId: OrganizationModel.rootId,
        ownerEmployeeId: other.id,
      ),
    );

    final mine = await EmployeeFinanceService.self();
    expect(mine.contribution, 1000);
    expect(mine.net, 1000);

    final org = await EmployeeFinanceService.organizationFinance(
      organizationId: OrganizationModel.rootId,
    );
    expect(org.income, 10000);
    expect(org.net, 10000);

    final team = await EmployeeFinanceService.teamBreakdown(
      organizationId: OrganizationModel.rootId,
    );
    expect(team, isEmpty,
        reason: 'view_finance must not reveal coworker attribution');
  });

  test('CEO keeps personal self view while also seeing root organization and team', () async {
    final owner = employee('owner', owner: true);
    final dev = employee('dev-a');
    await Hive.box<EmployeeModel>(TeamService.boxName).putAll({
      owner.id: owner,
      dev.id: dev,
    });
    await Hive.box('wesios_settings').put('team_current_employee', owner.id);
    await OrganizationAccessService.ensureLegacyGrants();
    await OrganizationContext.initialize();
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);
    await OrganizationContext.setScope(OrganizationScope.only);

    await Hive.box<TransactionModel>('wesios_treasury').putAll({
      'owner-income': TransactionModel(
        id: 'owner-income',
        title: 'CEO contribution',
        amount: 2000,
        type: TransactionType.income,
        date: DateTime.now(),
        organizationId: OrganizationModel.rootId,
        ownerEmployeeId: owner.id,
      ),
      'dev-income': TransactionModel(
        id: 'dev-income',
        title: 'Developer contribution',
        amount: 5000,
        type: TransactionType.income,
        date: DateTime.now(),
        organizationId: OrganizationModel.rootId,
        ownerEmployeeId: dev.id,
      ),
    });

    final self = await EmployeeFinanceService.self();
    expect(self.contribution, 2000,
        reason: 'CEO management access must not replace personal finance');

    final org = await EmployeeFinanceService.organizationFinance(
      organizationId: OrganizationModel.rootId,
    );
    expect(org.income, 7000);

    final team = await EmployeeFinanceService.teamBreakdown(
      organizationId: OrganizationModel.rootId,
    );
    expect(team.map((r) => r.employee.id).toSet(), containsAll([owner.id, dev.id]));
    expect(
      team.firstWhere((r) => r.employee.id == dev.id).metrics.contribution,
      5000,
    );
  });

  test('subtree finance is additive to self and requires explicit subtree grant', () async {
    final lead = employee('it-lead');
    await Hive.box<EmployeeModel>(TeamService.boxName).put(lead.id, lead);

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
    await Hive.box('wesios_settings').put('team_current_employee', lead.id);
    await OrganizationAccessService.grant(
      employeeId: lead.id,
      organizationId: it.id,
      includeSubtree: true,
      permissions: const [
        OrganizationPermissions.view,
        OrganizationPermissions.viewFinance,
      ],
      canViewSelfFinance: true,
      canViewTeamFinance: false,
      enforceActor: false,
    );
    await OrganizationContext.initialize();
    await OrganizationContext.selectOrganization(it.id);
    await OrganizationContext.setScope(OrganizationScope.subtree);

    await Hive.box<TransactionModel>('wesios_treasury').putAll({
      'lead-self': TransactionModel(
        id: 'lead-self',
        title: 'Lead contribution',
        amount: 100,
        type: TransactionType.income,
        date: DateTime.now(),
        organizationId: it.id,
        ownerEmployeeId: lead.id,
      ),
      'studio-income': TransactionModel(
        id: 'studio-income',
        title: 'Studio revenue',
        amount: 900,
        type: TransactionType.income,
        date: DateTime.now(),
        organizationId: studio.id,
      ),
    });

    final self = await EmployeeFinanceService.self();
    expect(self.contribution, 100);
    final branch = await EmployeeFinanceService.organizationFinance(
      organizationId: it.id,
      view: EmployeeFinanceView.subtree,
    );
    expect(branch.income, 1000);
    expect(await OrganizationAccessService.canUseSubtreeFinance(it.id), isTrue);
  });
}
