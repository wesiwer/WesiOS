import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/features/organizations/models/inter_org_transfer_model.dart';
import 'package:wesios/features/organizations/models/organization_access_grant.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/inter_org_transfer_service.dart';
import 'package:wesios/features/organizations/services/organization_access_service.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';
import 'package:wesios/features/treasury/models/account_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/account_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-sync-corruption-');
    Hive.init(temp.path);
    if (!Hive.isAdapterRegistered(1))
      Hive.registerAdapter(TransactionModelAdapter());
    if (!Hive.isAdapterRegistered(2))
      Hive.registerAdapter(TransactionTypeAdapter());
    if (!Hive.isAdapterRegistered(3))
      Hive.registerAdapter(RecurringPeriodAdapter());
    if (!Hive.isAdapterRegistered(14))
      Hive.registerAdapter(AccountKindAdapter());
    if (!Hive.isAdapterRegistered(15))
      Hive.registerAdapter(AccountModelAdapter());
    if (!Hive.isAdapterRegistered(20))
      Hive.registerAdapter(TeamPermissionsAdapter());
    if (!Hive.isAdapterRegistered(21))
      Hive.registerAdapter(EmployeeModelAdapter());
    if (!Hive.isAdapterRegistered(80))
      Hive.registerAdapter(OrganizationStatusAdapter());
    if (!Hive.isAdapterRegistered(81))
      Hive.registerAdapter(OrganizationModelAdapter());
    if (!Hive.isAdapterRegistered(82))
      Hive.registerAdapter(OrganizationAccessGrantAdapter());
    if (!Hive.isAdapterRegistered(83))
      Hive.registerAdapter(InterOrgTransferTypeAdapter());
    if (!Hive.isAdapterRegistered(84))
      Hive.registerAdapter(InterOrgTransferModelAdapter());
    if (!Hive.isAdapterRegistered(86))
      Hive.registerAdapter(TransactionSourceAdapter());

    await Hive.openBox('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<OrganizationAccessGrant>(
        OrganizationAccessService.boxName);
    await Hive.openBox<AccountModel>('wesios_accounts');
    await Hive.openBox<TransactionModel>('wesios_treasury');
    await Hive.openBox<InterOrgTransferModel>(InterOrgTransferService.boxName);
  });

  setUp(() async {
    await Hive.box('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<OrganizationAccessGrant>(OrganizationAccessService.boxName)
        .clear();
    await Hive.box<AccountModel>('wesios_accounts').clear();
    await Hive.box<TransactionModel>('wesios_treasury').clear();
    await Hive.box<InterOrgTransferModel>(InterOrgTransferService.boxName)
        .clear();
    await OrganizationService.ensureBaseline();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Map<String, dynamic> organizationFields(OrganizationModel org,
          {String? parentId}) =>
      {
        ...org.toJson(),
        'parentId': parentId ?? org.parentId,
      };

  test('organization sync rejects dangling parents, fake roots and cycles',
      () async {
    final organizations = OrganizationsSync();
    final now = DateTime(2026, 8, 1).toIso8601String();

    expect(
      await organizations.applyFields({
        'id': 'org-dangling',
        'name': 'Dangling',
        'parentId': 'missing-parent',
        'isRoot': false,
        'baseCurrency': 'RUB',
        'status': 'active',
        'createdAt': now,
        'updatedAt': now,
        'createdBy': 'remote',
        'sortOrder': 0,
      }),
      isFalse,
    );
    expect(
        Hive.box<OrganizationModel>(OrganizationService.boxName)
            .containsKey('org-dangling'),
        isFalse);

    expect(
      await organizations.applyFields({
        'id': 'fake-root',
        'name': 'Fake root',
        'parentId': null,
        'isRoot': true,
        'baseCurrency': 'RUB',
        'status': 'active',
        'createdAt': now,
        'updatedAt': now,
        'createdBy': 'remote',
        'sortOrder': 0,
      }),
      isFalse,
    );

    final a = await OrganizationService.create(
      name: 'A',
      parentId: OrganizationModel.rootId,
      createdBy: 'setup',
    );
    final b = await OrganizationService.create(
      name: 'B',
      parentId: a.id,
      createdBy: 'setup',
    );
    expect(
      await organizations.applyFields(organizationFields(a, parentId: b.id)),
      isFalse,
    );
    expect((await OrganizationService.byId(a.id))!.parentId,
        OrganizationModel.rootId);
  });

  test('grant sync rejects malformed and unauthenticated privilege grants',
      () async {
    final employee = EmployeeModel(
      id: 'target',
      login: 'target',
      fullName: 'Target',
      createdAt: DateTime(2026, 1, 1),
      permissions: const TeamPermissions(),
    );
    await Hive.box<EmployeeModel>(TeamService.boxName)
        .put(employee.id, employee);
    final sync = OrganizationGrantsSync();
    final now = DateTime(2026, 8, 1).toIso8601String();

    expect(
      await sync.applyFields({
        'id': 'target::${OrganizationModel.rootId}',
        'employeeId': 'target',
        'organizationId': OrganizationModel.rootId,
        'includeSubtree': false,
        'canViewTeamFinance': true,
        'canViewSelfFinance': true,
        'permissions': [OrganizationPermissions.view],
        'createdAt': now,
        'updatedAt': now,
        'createdBy': 'sync',
      }),
      isFalse,
      reason: 'team-finance without view_finance must fail closed',
    );

    expect(
      await sync.applyFields({
        'id': 'target::${OrganizationModel.rootId}',
        'employeeId': 'target',
        'organizationId': OrganizationModel.rootId,
        'includeSubtree': true,
        'canViewTeamFinance': false,
        'canViewSelfFinance': true,
        'permissions': [
          OrganizationPermissions.view,
          OrganizationPermissions.manageMembers,
          OrganizationPermissions.manageOrgSettings,
        ],
        'createdAt': now,
        'updatedAt': now,
        'createdBy': 'sync',
      }),
      isFalse,
      reason: 'remote data cannot use a magic sync actor to mint admin rights',
    );
    expect(await OrganizationAccessService.grantsFor(employee.id), isEmpty);
  });

  test('transaction sync rejects cross-organization account ownership',
      () async {
    final a = await OrganizationService.create(
      name: 'A',
      parentId: OrganizationModel.rootId,
      createdBy: 'setup',
    );
    final b = await OrganizationService.create(
      name: 'B',
      parentId: OrganizationModel.rootId,
      createdBy: 'setup',
    );
    final accountA = await AccountService.ensureMain(organizationId: a.id);
    final now = DateTime(2026, 8, 1).toIso8601String();

    expect(
      await TransactionsSync().applyFields({
        'id': 'bad-tx',
        'title': 'Bad ownership',
        'amount': 100,
        'type': 'income',
        'date': now,
        'accountId': accountA.id,
        'organizationId': b.id,
      }),
      isFalse,
    );
    expect(Hive.box<TransactionModel>('wesios_treasury').containsKey('bad-tx'),
        isFalse);
  });

  test('inter-org sync rejects dangling or forged linked references', () async {
    final a = await OrganizationService.create(
      name: 'A',
      parentId: OrganizationModel.rootId,
      createdBy: 'setup',
    );
    final b = await OrganizationService.create(
      name: 'B',
      parentId: OrganizationModel.rootId,
      createdBy: 'setup',
    );
    final accountA = await AccountService.ensureMain(organizationId: a.id);
    final accountB = await AccountService.ensureMain(organizationId: b.id);
    final now = DateTime(2026, 8, 1).toIso8601String();

    expect(
      await InterOrgTransfersSync().applyFields({
        'id': 'transfer-bad',
        'fromOrganizationId': a.id,
        'toOrganizationId': b.id,
        'fromAccountId': accountA.id,
        'toAccountId': accountB.id,
        'amount': 100,
        'currency': 'RUB',
        'amountInFromOrgBase': 100,
        'amountInToOrgBase': 100,
        'type': 'internalTransfer',
        'date': now,
        'createdBy': 'remote',
        'createdAt': now,
        'linkedDebitTransactionId': 'forged-debit',
        'linkedCreditTransactionId': 'forged-credit',
      }),
      isFalse,
    );
    expect(
      Hive.box<InterOrgTransferModel>(InterOrgTransferService.boxName)
          .containsKey('transfer-bad'),
      isFalse,
    );
  });

  test(
      'organization sync tombstone cannot hard-delete an existing organization',
      () async {
    final child = await OrganizationService.create(
      name: 'Protected child',
      parentId: OrganizationModel.rootId,
      createdBy: 'setup',
    );
    await OrganizationsSync().removeById(child.id);
    expect(await OrganizationService.byId(child.id), isNotNull);
  });

  test(
      'account sync cannot re-own or delete an account that has ledger history',
      () async {
    final child = await OrganizationService.create(
      name: 'Target org',
      parentId: OrganizationModel.rootId,
      createdBy: 'setup',
    );
    final account = await AccountService.create(
      name: 'Historical account',
      organizationId: OrganizationModel.rootId,
    );
    await Hive.box<TransactionModel>('wesios_treasury').put(
      'historical-account-tx',
      TransactionModel(
        id: 'historical-account-tx',
        title: 'History',
        amount: 100,
        type: TransactionType.income,
        date: DateTime(2026, 8, 1),
        accountId: account.id,
        organizationId: OrganizationModel.rootId,
      ),
    );
    final moved =
        AccountsSync().encode(account.copyWith(organizationId: child.id));
    expect(await AccountsSync().applyFields(moved), isFalse);
    expect(
      (await AccountService.byId(account.id))!.effectiveOrganizationId,
      OrganizationModel.rootId,
    );
    await AccountsSync().removeById(account.id);
    expect(await AccountService.byId(account.id), isNotNull);
  });

  test('employee sync cannot mint, demote or tombstone owner identity',
      () async {
    final employees = Hive.box<EmployeeModel>(TeamService.boxName);
    final owner = EmployeeModel(
      id: 'owner-secure',
      login: 'owner-secure',
      fullName: 'Owner',
      createdAt: DateTime(2026, 1, 1),
      permissions: TeamPermissions.owner,
      isOwner: true,
    );
    final employee = EmployeeModel(
      id: 'ordinary',
      login: 'ordinary',
      fullName: 'Ordinary',
      createdAt: DateTime(2026, 1, 2),
      permissions: const TeamPermissions(),
    );
    await employees.put(owner.id, owner);
    await employees.put(employee.id, employee);
    final sync = EmployeesSync();

    final forgedOwner = sync.encode(employee)..['isOwner'] = true;
    expect(await sync.applyFields(forgedOwner), isFalse);
    expect(TeamService.byId(employee.id)!.isOwner, isFalse);

    final forgedNewOwner = sync.encode(employee)
      ..['id'] = 'remote-owner'
      ..['login'] = 'remote-owner'
      ..['isOwner'] = true;
    expect(await sync.applyFields(forgedNewOwner), isFalse);
    expect(TeamService.byId('remote-owner'), isNull);

    final demotedOwner = sync.encode(owner)..['isOwner'] = false;
    expect(await sync.applyFields(demotedOwner), isFalse);
    expect(TeamService.byId(owner.id)!.isOwner, isTrue);

    await sync.removeById(owner.id);
    expect(TeamService.byId(owner.id), isNotNull);
  });

  test('sync tombstone cannot delete one linked inter-org ledger leg',
      () async {
    final account = await AccountService.ensureMain(
      organizationId: OrganizationModel.rootId,
    );
    final leg = TransactionModel(
      id: 'transfer-1_debit',
      title: 'Inter-org debit',
      amount: 100,
      type: TransactionType.expense,
      date: DateTime(2026, 8, 1),
      accountId: account.id,
      organizationId: OrganizationModel.rootId,
      source: TransactionSource.interorg,
      interOrgTransferId: 'transfer-1',
    );
    await Hive.box<TransactionModel>('wesios_treasury').put(leg.id, leg);
    await TransactionsSync().removeById(leg.id);
    expect(Hive.box<TransactionModel>('wesios_treasury').containsKey(leg.id),
        isTrue);
  });

  test('inter-org sync cannot rewrite immutable transfer core', () async {
    final a = await OrganizationService.create(
      name: 'Immutable A',
      parentId: OrganizationModel.rootId,
      createdBy: 'setup',
    );
    final b = await OrganizationService.create(
      name: 'Immutable B',
      parentId: OrganizationModel.rootId,
      createdBy: 'setup',
    );
    final accountA = await AccountService.ensureMain(organizationId: a.id);
    final accountB = await AccountService.ensureMain(organizationId: b.id);
    final now = DateTime(2026, 8, 1);
    final transfer = InterOrgTransferModel(
      id: 'immutable-transfer',
      fromOrganizationId: a.id,
      toOrganizationId: b.id,
      fromAccountId: accountA.id,
      toAccountId: accountB.id,
      amount: 100,
      currency: 'RUB',
      amountInFromOrgBase: 100,
      amountInToOrgBase: 100,
      type: InterOrgTransferType.internalTransfer,
      date: now,
      createdBy: 'owner',
      createdAt: now,
      linkedDebitTransactionId: 'immutable-transfer_debit',
      linkedCreditTransactionId: 'immutable-transfer_credit',
    );
    await Hive.box<InterOrgTransferModel>(InterOrgTransferService.boxName)
        .put(transfer.id, transfer);

    final forged = InterOrgTransfersSync().encode(transfer)..['amount'] = 999;
    expect(await InterOrgTransfersSync().applyFields(forged), isFalse);
    expect(
      Hive.box<InterOrgTransferModel>(InterOrgTransferService.boxName)
          .get(transfer.id)!
          .amount,
      100,
    );
  });
}
