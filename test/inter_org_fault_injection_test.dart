import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/organizations/models/inter_org_transfer_model.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/models/transaction_audit_model.dart';
import 'package:wesios/features/organizations/services/inter_org_transfer_service.dart';
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
    temp = await Directory.systemTemp.createTemp('wesios-interorg-faults-');
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
    InterOrgTransferService.debugFailAfterStep = null;
    await Hive.box('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<AccountModel>('wesios_accounts').clear();
    await Hive.box<TransactionModel>('wesios_treasury').clear();
    await Hive.box<InterOrgTransferModel>(InterOrgTransferService.boxName).clear();
    await Hive.box<TransactionAuditModel>('wesios_transaction_audit').clear();
    await OrganizationService.ensureBaseline();
    final owner = EmployeeModel(
      id: 'owner-interorg-faults',
      login: 'owner-interorg-faults',
      fullName: 'Owner',
      createdAt: DateTime(2026, 1, 1),
      isOwner: true,
      permissions: TeamPermissions.owner,
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(owner.id, owner);
    await Hive.box('wesios_settings').put('team_current_employee', owner.id);
  });

  tearDown(() {
    InterOrgTransferService.debugFailAfterStep = null;
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<({String fromOrg, String toOrg, String fromAccount, String toAccount})>
      fixture() async {
    final fromOrg = await OrganizationService.create(
      name: 'IT',
      parentId: OrganizationModel.rootId,
      createdBy: 'test',
    );
    final toOrg = await OrganizationService.create(
      name: 'Studio A',
      parentId: fromOrg.id,
      createdBy: 'test',
    );
    final fromAccount = await AccountService.ensureMain(organizationId: fromOrg.id);
    final toAccount = await AccountService.ensureMain(organizationId: toOrg.id);
    return (
      fromOrg: fromOrg.id,
      toOrg: toOrg.id,
      fromAccount: fromAccount.id,
      toAccount: toAccount.id,
    );
  }

  test('inter-org create converges to two legs after failure at every write step', () async {
    final f = await fixture();
    for (final step in const [1, 2, 3]) {
      await Hive.box<TransactionModel>('wesios_treasury').clear();
      await Hive.box<InterOrgTransferModel>(InterOrgTransferService.boxName).clear();
      InterOrgTransferService.debugFailAfterStep = step;

      await expectLater(
        InterOrgTransferService.execute(
          fromOrganizationId: f.fromOrg,
          toOrganizationId: f.toOrg,
          fromAccountId: f.fromAccount,
          toAccountId: f.toAccount,
          amount: (1000 + step).toDouble(),
          currency: 'RUB',
          type: InterOrgTransferType.internalTransfer,
        ),
        throwsStateError,
        reason: 'fault point $step must interrupt the foreground call',
      );

      InterOrgTransferService.debugFailAfterStep = null;
      await InterOrgTransferService.recoverPending();

      final transfers = Hive.box<InterOrgTransferModel>(InterOrgTransferService.boxName)
          .values
          .toList();
      expect(transfers, hasLength(1), reason: 'journal survives failure $step');
      expect(transfers.single.cancelled, isFalse);
      final legs = (await TreasuryService().getAllTransactionsRaw())
          .where((t) => t.interOrgTransferId == transfers.single.id)
          .toList();
      expect(legs, hasLength(2), reason: 'recovery completes failure $step');
      expect(legs.map((e) => e.id).toSet(), {
        transfers.single.linkedDebitTransactionId,
        transfers.single.linkedCreditTransactionId,
      });
    }
  });

  test('inter-org cancellation converges to zero legs after every failure point', () async {
    final f = await fixture();
    for (final step in const [4, 5, 6]) {
      await Hive.box<TransactionModel>('wesios_treasury').clear();
      await Hive.box<InterOrgTransferModel>(InterOrgTransferService.boxName).clear();
      final transfer = await InterOrgTransferService.execute(
        fromOrganizationId: f.fromOrg,
        toOrganizationId: f.toOrg,
        fromAccountId: f.fromAccount,
        toAccountId: f.toAccount,
        amount: (2000 + step).toDouble(),
        currency: 'RUB',
        type: InterOrgTransferType.funding,
      );
      expect(
        (await TreasuryService().getAllTransactionsRaw())
            .where((t) => t.interOrgTransferId == transfer.id),
        hasLength(2),
      );

      InterOrgTransferService.debugFailAfterStep = step;
      await expectLater(
        InterOrgTransferService.cancel(transfer.id, reason: 'fault $step'),
        throwsStateError,
      );
      InterOrgTransferService.debugFailAfterStep = null;
      await InterOrgTransferService.recoverPending();

      final journal = await InterOrgTransferService.byId(transfer.id);
      expect(journal, isNotNull);
      expect(journal!.cancelled, isTrue);
      expect(
        (await TreasuryService().getAllTransactionsRaw())
            .where((t) => t.interOrgTransferId == transfer.id),
        isEmpty,
        reason: 'recovery finishes cancellation after fault $step',
      );
    }
  });
}
