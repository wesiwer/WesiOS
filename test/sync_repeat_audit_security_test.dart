import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/features/organizations/models/inter_org_transfer_model.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/inter_org_transfer_service.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';
import 'package:wesios/features/treasury/models/account_model.dart';
import 'package:wesios/features/treasury/services/account_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-sync-repeat-audit-');
    Hive.init(temp.path);
    if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(AccountKindAdapter());
    if (!Hive.isAdapterRegistered(15)) Hive.registerAdapter(AccountModelAdapter());
    if (!Hive.isAdapterRegistered(20)) Hive.registerAdapter(TeamPermissionsAdapter());
    if (!Hive.isAdapterRegistered(21)) Hive.registerAdapter(EmployeeModelAdapter());
    if (!Hive.isAdapterRegistered(80)) Hive.registerAdapter(OrganizationStatusAdapter());
    if (!Hive.isAdapterRegistered(81)) Hive.registerAdapter(OrganizationModelAdapter());
    if (!Hive.isAdapterRegistered(83)) Hive.registerAdapter(InterOrgTransferTypeAdapter());
    if (!Hive.isAdapterRegistered(84)) Hive.registerAdapter(InterOrgTransferModelAdapter());

    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<AccountModel>('wesios_accounts');
    await Hive.openBox<InterOrgTransferModel>(InterOrgTransferService.boxName);
  });

  setUp(() async {
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<AccountModel>('wesios_accounts').clear();
    await Hive.box<InterOrgTransferModel>(InterOrgTransferService.boxName).clear();
    await OrganizationService.ensureBaseline();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('generic employee sync cannot mint, demote or tombstone owner identity',
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
    final ordinary = EmployeeModel(
      id: 'ordinary',
      login: 'ordinary',
      fullName: 'Ordinary',
      createdAt: DateTime(2026, 1, 2),
      permissions: const TeamPermissions(),
    );
    await employees.put(owner.id, owner);
    await employees.put(ordinary.id, ordinary);

    final sync = EmployeesSync();

    final promoted = sync.encode(ordinary)..['isOwner'] = true;
    expect(await sync.applyFields(promoted), isFalse);
    expect(employees.get(ordinary.id)!.isOwner, isFalse);

    final minted = sync.encode(ordinary)
      ..['id'] = 'remote-owner'
      ..['login'] = 'remote-owner'
      ..['isOwner'] = true;
    expect(await sync.applyFields(minted), isFalse);
    expect(employees.get('remote-owner'), isNull);

    final demoted = sync.encode(owner)..['isOwner'] = false;
    expect(await sync.applyFields(demoted), isFalse);
    expect(employees.get(owner.id)!.isOwner, isTrue);

    await sync.removeById(owner.id);
    expect(employees.get(owner.id), isNotNull);

    final refreshed = sync.encode(owner)..['fullName'] = 'Owner refreshed';
    expect(await sync.applyFields(refreshed), isTrue,
        reason: 'the already-established same owner may receive profile refreshes');
    expect(employees.get(owner.id)!.fullName, 'Owner refreshed');
  });

  test('inter-org sync cannot rewrite immutable financial core', () async {
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
    final at = DateTime(2026, 8, 1);
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
      date: at,
      createdBy: 'owner-secure',
      createdAt: at,
      linkedDebitTransactionId: 'immutable-transfer_debit',
      linkedCreditTransactionId: 'immutable-transfer_credit',
    );
    await Hive.box<InterOrgTransferModel>(InterOrgTransferService.boxName)
        .put(transfer.id, transfer);

    final sync = InterOrgTransfersSync();
    final forgedAmount = sync.encode(transfer)..['amount'] = 999;
    expect(await sync.applyFields(forgedAmount), isFalse);
    expect(
      Hive.box<InterOrgTransferModel>(InterOrgTransferService.boxName)
          .get(transfer.id)!
          .amount,
      100,
    );

    final forgedDestination = sync.encode(transfer)
      ..['toOrganizationId'] = a.id;
    expect(await sync.applyFields(forgedDestination), isFalse);
    expect(
      Hive.box<InterOrgTransferModel>(InterOrgTransferService.boxName)
          .get(transfer.id)!
          .toOrganizationId,
      b.id,
    );
  });
}
