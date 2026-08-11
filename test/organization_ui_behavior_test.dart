import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/organizations/inter_org_transfer_screen.dart';
import 'package:wesios/features/organizations/models/inter_org_transfer_model.dart';
import 'package:wesios/features/organizations/models/organization_access_grant.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/models/transaction_audit_model.dart';
import 'package:wesios/features/organizations/services/inter_org_transfer_service.dart';
import 'package:wesios/features/organizations/services/organization_access_service.dart';
import 'package:wesios/features/organizations/services/organization_context.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/organizations/widgets/organization_switcher.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';
import 'package:wesios/features/treasury/models/account_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/account_service.dart';
import 'package:wesios/features/treasury/widgets/accounts_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-org-ui-behavior-');
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
        createdBy: 'ui-test',
      );

  testWidgets('user switches organization and only/subtree context through UI',
      (tester) async {
    final studio = await createStudio();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: OrganizationSwitcher()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Wesi Inc'), findsOneWidget);
    expect(find.text('Только эта'), findsOneWidget);
    await tester.tap(find.text('Wesi Inc'));
    await tester.pumpAndSettle();

    expect(find.text('Организация'), findsOneWidget);
    expect(find.text('Studio A'), findsOneWidget);
    await tester.tap(find.text('Studio A'));
    await tester.pumpAndSettle();
    expect(OrganizationContext.currentOrganizationId, studio.id);

    await tester.tap(find.text('С дочерними'));
    await tester.pumpAndSettle();
    expect(OrganizationContext.scope, OrganizationScope.subtree);

    await tester.tap(find.text('Только эта'));
    await tester.pumpAndSettle();
    expect(OrganizationContext.scope, OrganizationScope.only);
  });

  testWidgets('subtree account shown by AccountsBar is actually selectable',
      (tester) async {
    final studio = await createStudio();
    await AccountService.ensureMain(organizationId: OrganizationModel.rootId);
    final childAccount = await AccountService.create(
      name: 'Studio Wallet',
      organizationId: studio.id,
      currency: 'RUB',
    );
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);
    await OrganizationContext.setScope(OrganizationScope.subtree);

    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountsBar(
            transactions: const [],
            selectedId: null,
            onSelect: (id) async {
              selected = id;
              await AccountService.select(id);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Studio Wallet'), findsOneWidget);
    await tester.tap(find.text('Studio Wallet'));
    await tester.pumpAndSettle();
    expect(selected, childAccount.id);
    expect(AccountService.selectedId, childAccount.id);
  });

  testWidgets('inter-org UI requires review, writes both legs, and cancels both',
      (tester) async {
    final studio = await createStudio();
    await AccountService.ensureMain(organizationId: OrganizationModel.rootId);
    await AccountService.ensureMain(organizationId: studio.id);
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);
    await OrganizationContext.setScope(OrganizationScope.subtree);

    await tester.pumpWidget(
      const MaterialApp(home: InterOrgTransferScreen()),
    );
    await tester.pumpAndSettle();

    final amountField = find.byWidgetPredicate(
      (widget) => widget is TextField &&
          (widget.decoration?.labelText ?? '').startsWith('Сумма '),
      description: 'inter-org amount field',
    );
    expect(amountField, findsOneWidget);
    await tester.enterText(amountField, '1000');

    final reviewButton = find.text('Проверить и провести');
    await tester.ensureVisible(reviewButton);
    await tester.tap(reviewButton);
    await tester.pumpAndSettle();

    expect(find.text('Подтверждение перевода'), findsOneWidget);
    expect(find.text('Провести'), findsOneWidget);
    await tester.tap(find.text('Провести'));
    await tester.pumpAndSettle();

    final transfers = Hive.box<InterOrgTransferModel>(InterOrgTransferService.boxName)
        .values
        .toList();
    expect(transfers, hasLength(1));
    final transfer = transfers.single;
    final legs = Hive.box<TransactionModel>('wesios_treasury')
        .values
        .where((tx) => tx.interOrgTransferId == transfer.id)
        .toList();
    expect(legs, hasLength(2));
    expect(find.text('Wesi Inc → Studio A'), findsOneWidget);

    final cancelButton = find.text('Отменить');
    await tester.ensureVisible(cancelButton);
    await tester.tap(cancelButton);
    await tester.pumpAndSettle();
    expect(find.text('Отменить перевод?'), findsOneWidget);
    await tester.tap(find.text('Отменить обе проводки'));
    await tester.pumpAndSettle();

    final cancelled = Hive.box<InterOrgTransferModel>(InterOrgTransferService.boxName)
        .get(transfer.id);
    expect(cancelled, isNotNull);
    expect(cancelled!.cancelled, isTrue);
    expect(
      Hive.box<TransactionModel>('wesios_treasury')
          .values
          .where((tx) => tx.interOrgTransferId == transfer.id),
      isEmpty,
    );
    expect(find.text('Отменён'), findsOneWidget);
  });
}
