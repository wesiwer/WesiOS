import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/services/currency_service.dart';
import 'package:wesios/features/organizations/models/inter_org_transfer_model.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/models/transaction_audit_model.dart';
import 'package:wesios/features/organizations/services/inter_org_transfer_service.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/treasury/models/account_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/account_service.dart';
import 'package:wesios/features/treasury/services/treasury_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-multicurrency-org-');
    Hive.init(temp.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(TransactionModelAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TransactionTypeAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(RecurringPeriodAdapter());
    if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(AccountKindAdapter());
    if (!Hive.isAdapterRegistered(15)) Hive.registerAdapter(AccountModelAdapter());
    if (!Hive.isAdapterRegistered(80)) Hive.registerAdapter(OrganizationStatusAdapter());
    if (!Hive.isAdapterRegistered(81)) Hive.registerAdapter(OrganizationModelAdapter());
    if (!Hive.isAdapterRegistered(83)) Hive.registerAdapter(InterOrgTransferTypeAdapter());
    if (!Hive.isAdapterRegistered(84)) Hive.registerAdapter(InterOrgTransferModelAdapter());
    if (!Hive.isAdapterRegistered(85)) Hive.registerAdapter(TransactionAuditModelAdapter());
    if (!Hive.isAdapterRegistered(86)) Hive.registerAdapter(TransactionSourceAdapter());

    await Hive.openBox('wesios_settings');
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<AccountModel>('wesios_accounts');
    await Hive.openBox<TransactionModel>('wesios_treasury');
    await Hive.openBox<InterOrgTransferModel>(InterOrgTransferService.boxName);
    await Hive.openBox<TransactionAuditModel>('wesios_transaction_audit');
  });

  setUp(() async {
    await Hive.box('wesios_settings').clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<AccountModel>('wesios_accounts').clear();
    await Hive.box<TransactionModel>('wesios_treasury').clear();
    await Hive.box<InterOrgTransferModel>(InterOrgTransferService.boxName).clear();
    await Hive.box<TransactionAuditModel>('wesios_transaction_audit').clear();
    CurrencyService.setRates({
      'rub': 1.0,
      'eur': 100.0,
      'usd': 90.0,
    });
    await OrganizationService.ensureBaseline();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('EUR local balance and RUB reporting balance use frozen normalized amounts', () async {
    final studio = await OrganizationService.create(
      name: 'Studio EUR',
      parentId: OrganizationModel.rootId,
      baseCurrency: 'EUR',
      createdBy: 'test',
    );
    final account = await AccountService.ensureMain(organizationId: studio.id);

    await TreasuryService().addTransaction(TransactionModel(
      id: 'eur-income',
      title: 'EUR income',
      amount: 10000,
      type: TransactionType.income,
      date: DateTime(2026, 8, 1),
      accountId: account.id,
      organizationId: studio.id,
      originalAmount: 100,
      originalCurrency: 'EUR',
      fxRateAt: DateTime(2026, 8, 1),
      fxSource: 'test-rate',
    ));

    final tx = Hive.box<TransactionModel>('wesios_treasury').get('eur-income')!;
    expect(tx.amount, 10000, reason: 'canonical reporting currency is RUB');
    expect(tx.effectiveOriginalAmount, 100);
    expect(tx.originalCurrency, 'EUR');
    expect(tx.effectiveOrganizationBaseAmount, 100);
    expect(tx.organizationBaseCurrency, 'EUR');
    expect(tx.fxRateToReporting, 100);

    final base = await AccountService.baseBalancesByOrganization(
      {studio.id},
      [tx],
    );
    expect(base[studio.id], closeTo(100, 0.000001));
    final reporting = await AccountService.reportingBalanceForOrganizations(
      {studio.id},
      [tx],
    );
    expect(reporting, closeTo(10000, 0.000001));
  });

  test('cross-currency inter-org legs cancel in consolidation but retain local bases', () async {
    final studio = await OrganizationService.create(
      name: 'Studio EUR',
      parentId: OrganizationModel.rootId,
      baseCurrency: 'EUR',
      createdBy: 'test',
    );
    final rootAccount = await AccountService.ensureMain(
      organizationId: OrganizationModel.rootId,
    );
    final studioAccount = await AccountService.ensureMain(organizationId: studio.id);

    final transfer = await InterOrgTransferService.execute(
      fromOrganizationId: OrganizationModel.rootId,
      toOrganizationId: studio.id,
      fromAccountId: rootAccount.id,
      toAccountId: studioAccount.id,
      amount: 10,
      currency: 'USD',
      type: InterOrgTransferType.funding,
      date: DateTime(2026, 8, 2),
    );

    final legs = (await TreasuryService().getAllTransactionsRaw())
        .where((t) => t.interOrgTransferId == transfer.id)
        .toList();
    expect(legs, hasLength(2));
    expect(legs.map((t) => t.amount).toSet(), {900.0});
    expect(TreasuryService.eliminateInternalTransfers(legs), isEmpty);

    final debit = legs.singleWhere((t) => t.type == TransactionType.expense);
    final credit = legs.singleWhere((t) => t.type == TransactionType.income);
    expect(debit.effectiveOrganizationBaseAmount, closeTo(900, 0.000001));
    expect(debit.organizationBaseCurrency, 'RUB');
    expect(credit.effectiveOrganizationBaseAmount, closeTo(9, 0.000001));
    expect(credit.organizationBaseCurrency, 'EUR');
    expect(debit.originalCurrency, 'USD');
    expect(credit.originalCurrency, 'USD');

    final local = await AccountService.baseBalancesByOrganization(
      {OrganizationModel.rootId, studio.id},
      legs,
    );
    expect(local[OrganizationModel.rootId], closeTo(-900, 0.000001));
    expect(local[studio.id], closeTo(9, 0.000001));
  });
}
