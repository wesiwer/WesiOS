import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/treasury/models/account_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/account_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('wesios_accounts_test');
    Hive.init(tempDir.path);
    Hive.registerAdapter(OrganizationStatusAdapter());
    Hive.registerAdapter(OrganizationModelAdapter());
    Hive.registerAdapter(TransactionModelAdapter());
    Hive.registerAdapter(TransactionTypeAdapter());
    Hive.registerAdapter(RecurringPeriodAdapter());
    Hive.registerAdapter(TransactionSourceAdapter());
    Hive.registerAdapter(AccountKindAdapter());
    Hive.registerAdapter(AccountModelAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    final box = await Hive.openBox<AccountModel>('wesios_accounts');
    await box.clear();
  });

  TransactionModel tx({
    required double amount,
    TransactionType type = TransactionType.income,
    String? accountId,
    String id = 't',
  }) =>
      TransactionModel(
        id: id,
        title: 'op',
        amount: amount,
        type: type,
        date: DateTime(2026, 5, 1),
        accountId: accountId,
      );

  group('TransactionModel.effectiveAccountId', () {
    test('an operation created before accounts existed belongs to the main '
        'account — if such rows fell out of every query, the balance would '
        'drop to zero the moment the user updated the app', () {
      expect(tx(amount: 100).effectiveAccountId, AccountModel.mainId);
    });

    test('an explicit account is respected', () {
      expect(tx(amount: 100, accountId: 'proj').effectiveAccountId, 'proj');
    });
  });

  group('AccountService.filter', () {
    final rows = [
      tx(id: 'a', amount: 100),
      tx(id: 'b', amount: 200, accountId: AccountModel.mainId),
      tx(id: 'c', amount: 300, accountId: 'proj'),
    ];

    test('null means all accounts', () {
      expect(AccountService.filter(rows, null).length, 3);
    });

    test('the main account picks up legacy rows without an accountId', () {
      final main = AccountService.filter(rows, AccountModel.mainId);
      expect(main.map((t) => t.id), containsAll(['a', 'b']));
      expect(main.length, 2);
    });

    test('a secondary account sees only its own rows', () {
      final proj = AccountService.filter(rows, 'proj');
      expect(proj.single.id, 'c');
    });
  });

  group('AccountService.ensureMain', () {
    test('creates the main account once and reuses it afterwards', () async {
      final first = await AccountService.ensureMain();
      final second = await AccountService.ensureMain();
      expect(first.id, AccountModel.mainId);
      expect(second.id, AccountModel.mainId);
      final all = await AccountService.getAll();
      expect(all.where((a) => a.id == AccountModel.mainId).length, 1);
    });
  });

  group('AccountService.summaries', () {
    test('balance includes the opening balance, income and expenses', () async {
      await AccountService.ensureMain();
      final proj = await AccountService.create(
        name: 'Проект',
        openingBalance: 5000,
      );

      final rows = [
        tx(id: '1', amount: 1000, accountId: proj.id),
        tx(id: '2', amount: 400, type: TransactionType.expense, accountId: proj.id),
        tx(id: '3', amount: 250), // legacy -> main
      ];

      final summaries = await AccountService.summaries(rows);
      final projSummary = summaries.firstWhere((s) => s.account.id == proj.id);
      final mainSummary =
          summaries.firstWhere((s) => s.account.id == AccountModel.mainId);

      expect(projSummary.balance, 5000 + 1000 - 400);
      expect(projSummary.income, 1000);
      expect(projSummary.expense, 400);
      expect(projSummary.operations, 2);

      expect(mainSummary.balance, 250);
      expect(mainSummary.operations, 1);
    });

    test('the main account always sorts first, so the list does not reshuffle '
        'when accounts get renamed', () async {
      await AccountService.create(name: 'Б');
      await AccountService.create(name: 'А');
      final all = await AccountService.getAll();
      expect(all.first.id, AccountModel.mainId);
    });
  });

  group('AccountService.delete', () {
    test('refuses to delete the main account — every legacy operation points '
        'at it', () async {
      await AccountService.ensureMain();
      final ok = await AccountService.delete(AccountModel.mainId,
          hasOperations: false);
      expect(ok, isFalse);
      final all = await AccountService.getAll();
      expect(all.any((a) => a.id == AccountModel.mainId), isTrue);
    });

    test('an account holding history is archived, not erased — deleting it '
        'would take part of the past with it', () async {
      final a = await AccountService.create(name: 'Старый проект');
      final ok = await AccountService.delete(a.id, hasOperations: true);
      expect(ok, isTrue);
      final all = await AccountService.getAll();
      final still = all.firstWhere((x) => x.id == a.id);
      expect(still.archived, isTrue);
    });

    test('an empty account is removed outright', () async {
      final a = await AccountService.create(name: 'Пустой');
      final ok = await AccountService.delete(a.id, hasOperations: false);
      expect(ok, isTrue);
      final all = await AccountService.getAll();
      expect(all.any((x) => x.id == a.id), isFalse);
    });
  });
}
