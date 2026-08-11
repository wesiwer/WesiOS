import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/organizations/models/inter_org_transfer_model.dart';
import 'package:wesios/features/organizations/models/organization_access_grant.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/models/transaction_audit_model.dart';
import 'package:wesios/features/organizations/services/inter_org_transfer_service.dart';
import 'package:wesios/features/organizations/services/organization_context.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';
import 'package:wesios/features/treasury/models/account_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/account_service.dart';
import 'package:wesios/features/treasury/services/treasury_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-interorg-');
    Hive.init(temp.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(TransactionModelAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TransactionTypeAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(RecurringPeriodAdapter());
    if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(AccountKindAdapter());
    if (!Hive.isAdapterRegistered(15)) Hive.registerAdapter(AccountModelAdapter());
    if (!Hive.isAdapterRegistered(20)) Hive.registerAdapter(TeamPermissionsAdapter());
    if (!Hive.isAdapterRegistered(21)) Hive.registerAdapter(EmployeeModelAdapter());
    if (!Hive.isAdapterRegistered(80)) Hive.registerAdapter(OrganizationStatusAdapter());
    if (!Hive.isAdapterRegistered(81)) Hive.registerAdapter(OrganizationModelAdapter());
    if (!Hive.isAdapterRegistered(82)) Hive.registerAdapter(OrganizationAccessGrantAdapter());
    if (!Hive.isAdapterRegistered(83)) Hive.registerAdapter(InterOrgTransferTypeAdapter());
    if (!Hive.isAdapterRegistered(84)) Hive.registerAdapter(InterOrgTransferModelAdapter());
    if (!Hive.isAdapterRegistered(85)) Hive.registerAdapter(TransactionAuditModelAdapter());
    if (!Hive.isAdapterRegistered(86)) Hive.registerAdapter(TransactionSourceAdapter());

    await Hive.openBox('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<AccountModel>('wesios_accounts');
    await Hive.openBox<TransactionModel>('wesios_treasury');
    await Hive.openBox<InterOrgTransferModel>(InterOrgTransferService.boxName);
    await Hive.openBox<TransactionAuditModel>('wesios_transaction_audit');
  });

  setUp(() async {
    await Hive.box('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<AccountModel>('wesios_accounts').clear();
    await Hive.box<TransactionModel>('wesios_treasury').clear();
    await Hive.box<InterOrgTransferModel>(InterOrgTransferService.boxName).clear();
    await Hive.box<TransactionAuditModel>('wesios_transaction_audit').clear();
    await OrganizationService.ensureBaseline();
    final owner = EmployeeModel(
      id: 'owner-interorg',
      login: 'owner-interorg',
      fullName: 'Owner',
      createdAt: DateTime(2026, 1, 1),
      isOwner: true,
      permissions: TeamPermissions.owner,
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(owner.id, owner);
    await Hive.box('wesios_settings').put('team_current_employee', owner.id);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('transfer creates two linked legs and subtree elimination removes double count', () async {
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
    final from = await AccountService.ensureMain(organizationId: it.id);
    final to = await AccountService.ensureMain(organizationId: studio.id);

    final transfer = await InterOrgTransferService.execute(
      fromOrganizationId: it.id,
      toOrganizationId: studio.id,
      fromAccountId: from.id,
      toAccountId: to.id,
      amount: 100000,
      currency: 'RUB',
      type: InterOrgTransferType.investment,
      note: 'Studio seed',
    );

    final raw = await TreasuryService().getAllTransactionsRaw();
    final legs = raw.where((t) => t.interOrgTransferId == transfer.id).toList();
    expect(legs, hasLength(2));
    expect(legs.map((e) => e.source).toSet(), {TransactionSource.interorg});
    expect(legs.map((e) => e.effectiveOrganizationId).toSet(), {it.id, studio.id});
    expect(legs.where((e) => e.type == TransactionType.expense), hasLength(1));
    expect(legs.where((e) => e.type == TransactionType.income), hasLength(1));

    final consolidated = TreasuryService.eliminateInternalTransfers(legs);
    expect(consolidated, isEmpty);

    await OrganizationContext.selectOrganization(it.id);
    await OrganizationContext.setScope(OrganizationScope.only);
    final onlyIt = await TreasuryService().getAllTransactions();
    expect(onlyIt.where((t) => t.interOrgTransferId == transfer.id), hasLength(1));

    await OrganizationContext.setScope(OrganizationScope.subtree);
    final subtree = await TreasuryService().getAllTransactions();
    expect(subtree.where((t) => t.interOrgTransferId == transfer.id), hasLength(2));
  });

  test('linked leg cannot be deleted alone; transfer cancellation removes both and audits', () async {
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
    final from = await AccountService.ensureMain(organizationId: it.id);
    final to = await AccountService.ensureMain(organizationId: studio.id);
    final transfer = await InterOrgTransferService.execute(
      fromOrganizationId: it.id,
      toOrganizationId: studio.id,
      fromAccountId: from.id,
      toAccountId: to.id,
      amount: 50000,
      currency: 'RUB',
      type: InterOrgTransferType.funding,
    );

    await expectLater(
      TreasuryService().deleteTransaction(transfer.linkedDebitTransactionId),
      throwsStateError,
    );

    await InterOrgTransferService.cancel(transfer.id, reason: 'test cancellation');
    final updated = await InterOrgTransferService.byId(transfer.id);
    expect(updated!.cancelled, isTrue);
    final raw = await TreasuryService().getAllTransactionsRaw();
    expect(raw.any((t) => t.interOrgTransferId == transfer.id), isFalse);

    final audits = Hive.box<TransactionAuditModel>('wesios_transaction_audit')
        .values
        .where((a) =>
            a.transactionId == transfer.linkedDebitTransactionId ||
            a.transactionId == transfer.linkedCreditTransactionId)
        .toList();
    expect(audits, hasLength(4));
    for (final legId in [
      transfer.linkedDebitTransactionId,
      transfer.linkedCreditTransactionId,
    ]) {
      final legAudits = audits.where((a) => a.transactionId == legId).toList();
      expect(legAudits, hasLength(2));
      expect(
        legAudits.map((a) => a.reason).toSet(),
        containsAll(<String?>{
          'inter-org recovery restore',
          'inter-org recovery delete',
        }),
      );
    }
  });
}
