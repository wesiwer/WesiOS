import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/treasury/models/account_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/account_service.dart';

void main() {
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-account-history-');
    Hive.init(temp.path);
    Hive.registerAdapter(AccountKindAdapter());
    Hive.registerAdapter(AccountModelAdapter());
    Hive.registerAdapter(TransactionModelAdapter());
    Hive.registerAdapter(TransactionTypeAdapter());
    Hive.registerAdapter(RecurringPeriodAdapter());
    Hive.registerAdapter(TransactionSourceAdapter());
    Hive.registerAdapter(OrganizationStatusAdapter());
    Hive.registerAdapter(OrganizationModelAdapter());
    await Hive.openBox<dynamic>('wesios_settings');
    await Hive.openBox<AccountModel>('wesios_accounts');
    await Hive.openBox<TransactionModel>('wesios_treasury');
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
  });

  setUp(() async {
    await Hive.box<dynamic>('wesios_settings').clear();
    await Hive.box<AccountModel>('wesios_accounts').clear();
    await Hive.box<TransactionModel>('wesios_treasury').clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    if (Hive.isBoxOpen('wesios_critical_audit')) {
      await Hive.box<String>('wesios_critical_audit').clear();
    }
    await OrganizationService.ensureBaseline();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('existing account cannot be moved to another organization', () async {
    final account = await AccountService.create(name: 'Stable account');
    final child = await OrganizationService.create(
      name: 'Child',
      parentId: OrganizationModel.rootId,
      createdBy: 'test',
    );
    await expectLater(
      AccountService.save(account.copyWith(organizationId: child.id)),
      throwsStateError,
    );
  });

  test('deleting an empty account archives it', () async {
    final account = await AccountService.create(name: 'Archive me');
    expect(await AccountService.delete(account.id, hasOperations: false), isTrue);
    expect((await AccountService.byId(account.id))?.archived, isTrue);
  });

  test('account sync cannot re-own or tombstone-delete an account', () async {
    final account = await AccountService.create(name: 'Synced account');
    final child = await OrganizationService.create(
      name: 'Child sync',
      parentId: OrganizationModel.rootId,
      createdBy: 'test',
    );
    final sync = AccountsSync();
    final forged = sync.encode(account)..['organizationId'] = child.id;
    expect(await sync.applyFields(forged), isFalse);
    await sync.removeById(account.id);
    expect(await AccountService.byId(account.id), isNotNull);
  });
}
