import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/organizations/models/inter_org_transfer_model.dart';
import 'package:wesios/features/organizations/models/organization_access_grant.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/models/transaction_audit_model.dart';
import 'package:wesios/features/organizations/services/inter_org_transfer_service.dart';
import 'package:wesios/features/organizations/services/organization_access_service.dart';
import 'package:wesios/features/organizations/services/organization_context.dart';
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
    temp = await Directory.systemTemp.createTemp('wesios-org-behavior-');
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

    await Hive.openBox<dynamic>('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<OrganizationAccessGrant>(OrganizationAccessService.boxName);
    await Hive.openBox<AccountModel>('wesios_accounts');
    await Hive.openBox<TransactionModel>('wesios_treasury');
    await Hive.openBox<InterOrgTransferModel>(InterOrgTransferService.boxName);
    await Hive.openBox<TransactionAuditModel>('wesios_transaction_audit');
  });

  setUp(() async {
    InterOrgTransferService.debugFailAfterStep = null;
    await Hive.box<dynamic>('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<OrganizationAccessGrant>(OrganizationAccessService.boxName).clear();
    await Hive.box<AccountModel>('wesios_accounts').clear();
    await Hive.box<TransactionModel>('wesios_treasury').clear();
    await Hive.box<InterOrgTransferModel>(InterOrgTransferService.boxName).clear();
    await Hive.box<TransactionAuditModel>('wesios_transaction_audit').clear();
    if (Hive.isBoxOpen('wesios_critical_audit')) {
      await Hive.box<String>('wesios_critical_audit').clear();
    }
    await OrganizationService.ensureBaseline();
    final owner = EmployeeModel(
      id: 'owner-ui',
      login: 'owner-ui',
      fullName: 'Owner',
      createdAt: DateTime(2026, 1, 1),
      isOwner: true,
      permissions: TeamPermissions.owner,
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(owner.id, owner);
    await Hive.box<dynamic>('wesios_settings').put('team_current_employee', owner.id);
    await OrganizationContext.initialize();
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);
    await OrganizationContext.setScope(OrganizationScope.only);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<OrganizationModel> createStudio() => OrganizationService.create(
        name: 'Studio A',
        parentId: OrganizationModel.rootId,
        createdBy: 'test',
      );

  test('organization context switches organization and scope', () async {
    final studio = await createStudio();
    await OrganizationContext.selectOrganization(studio.id);
    expect(OrganizationContext.currentOrganizationId, studio.id);

    await OrganizationContext.setScope(OrganizationScope.subtree);
    expect(OrganizationContext.scope, OrganizationScope.subtree);

    await OrganizationContext.setScope(OrganizationScope.only);
    expect(OrganizationContext.scope, OrganizationScope.only);
  });

  test('subtree account can be selected', () async {
    final studio = await createStudio();
    await AccountService.ensureMain(organizationId: OrganizationModel.rootId);
    final childAccount = await AccountService.create(
      name: 'Studio Wallet',
      organizationId: studio.id,
      currency: 'RUB',
    );
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);
    await OrganizationContext.setScope(OrganizationScope.subtree);

    await AccountService.select(childAccount.id);
    expect(AccountService.selectedId, childAccount.id);
  });

  test('inter-org transfer creates two legs and cancellation removes both', () async {
    final studio = await createStudio();
    final from = await AccountService.ensureMain(
      organizationId: OrganizationModel.rootId,
    );
    final to = await AccountService.ensureMain(organizationId: studio.id);

    final transfer = await InterOrgTransferService.execute(
      fromOrganizationId: OrganizationModel.rootId,
      toOrganizationId: studio.id,
      fromAccountId: from.id,
      toAccountId: to.id,
      amount: 1000,
      currency: 'RUB',
      type: InterOrgTransferType.internalTransfer,
    );

    expect(
      Hive.box<TransactionModel>('wesios_treasury')
          .values
          .where((tx) => tx.interOrgTransferId == transfer.id),
      hasLength(2),
    );

    await InterOrgTransferService.cancel(transfer.id, reason: 'test');
    expect((await InterOrgTransferService.byId(transfer.id))!.cancelled, isTrue);
    expect(
      Hive.box<TransactionModel>('wesios_treasury')
          .values
          .where((tx) => tx.interOrgTransferId == transfer.id),
      isEmpty,
    );
  });

  test('UI source remains wired to organization, account and transfer actions', () {
    final switcher = File(
      'lib/features/organizations/widgets/organization_switcher.dart',
    ).readAsStringSync();
    expect(switcher, contains('OrganizationContext.selectOrganization'));
    expect(switcher, contains('OrganizationContext.setScope'));

    final accounts = File(
      'lib/features/treasury/widgets/accounts_bar.dart',
    ).readAsStringSync();
    expect(accounts, contains('onSelect'));

    final transfers = File(
      'lib/features/organizations/inter_org_transfer_screen.dart',
    ).readAsStringSync();
    expect(transfers, contains('InterOrgTransferService.execute'));
    expect(transfers, contains('InterOrgTransferService.cancel'));
  });
}
