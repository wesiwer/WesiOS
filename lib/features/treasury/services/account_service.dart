import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/localization/wesi_locale.dart';
import '../models/account_model.dart';
import '../models/transaction_model.dart';

/// Сводка по одному счёту.
class AccountSummary {
  final AccountModel account;
  final double balance;
  final double income;
  final double expense;
  final int operations;

  const AccountSummary({
    required this.account,
    required this.balance,
    required this.income,
    required this.expense,
    required this.operations,
  });
}

/// Счета внутри Wesi Inc.
///
/// Общий счёт компании разбивается на любое число дополнительных: резерв,
/// отдельный проект, наличные, карта. Операция принадлежит счёту, общий
/// баланс — сумма по всем.
class AccountService {
  static const String _boxName = 'wesios_accounts';

  /// Какой счёт выбран сейчас в интерфейсе. `null` — «все счета».
  static const String _selectedKey = 'selected_account';
  static const String _settingsBox = 'wesios_settings';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Box<AccountModel>? _box;

  static Future<Box<AccountModel>> get _accountsBox async {
    _box ??= await Hive.openBox<AccountModel>(_boxName);
    return _box!;
  }

  /// Основной счёт создаётся сам при первом обращении.
  ///
  /// Без него операции, сделанные до появления счетов, ссылались бы на
  /// несуществующий `main`, и их не было бы видно ни в одном разрезе.
  static Future<AccountModel> ensureMain() async {
    final box = await _accountsBox;
    final existing = box.get(AccountModel.mainId);
    if (existing != null) return existing;
    final main = AccountModel(
      id: AccountModel.mainId,
      name: WesiLocale.isRussian ? 'Основной счёт' : 'Main account',
      kind: AccountKind.main,
      createdAt: DateTime.now(),
    );
    await box.put(main.id, main);
    revision.value++;
    return main;
  }

  static Future<List<AccountModel>> getAll(
      {bool includeArchived = true}) async {
    await ensureMain();
    final box = await _accountsBox;
    final list =
        box.values.where((a) => includeArchived || !a.archived).toList()
          // Основной всегда первым, остальные по дате создания: так порядок не
          // прыгает при переименованиях.
          ..sort((a, b) {
            if (a.id == AccountModel.mainId) return -1;
            if (b.id == AccountModel.mainId) return 1;
            return a.createdAt.compareTo(b.createdAt);
          });
    return list;
  }

  static Future<AccountModel?> byId(String id) async {
    final box = await _accountsBox;
    return box.get(id);
  }

  static Future<void> save(AccountModel account) async {
    final box = await _accountsBox;
    await box.put(account.id, account);
    revision.value++;
  }

  static Future<AccountModel> create({
    required String name,
    AccountKind kind = AccountKind.project,
    double openingBalance = 0,
    int colorValue = 0xFF38BDF8,
    String? note,
  }) async {
    final account = AccountModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      kind: kind,
      openingBalance: openingBalance,
      colorValue: colorValue,
      createdAt: DateTime.now(),
      note: note,
    );
    await save(account);
    return account;
  }

  /// Удаляет счёт. Основной удалить нельзя — на него ссылаются все старые
  /// операции. Счёт с историей тоже не удаляется, а архивируется: удаление
  /// потеряло бы часть прошлого.
  static Future<bool> delete(String id, {required bool hasOperations}) async {
    if (id == AccountModel.mainId) return false;
    final box = await _accountsBox;
    final account = box.get(id);
    if (account == null) return false;
    if (hasOperations) {
      await save(account.copyWith(archived: true));
      return true;
    }
    await box.delete(id);
    if (selectedId == id) await select(null);
    revision.value++;
    return true;
  }

  /// Выбранный счёт. `null` — показывать все.
  static String? get selectedId {
    try {
      return Hive.box(_settingsBox).get(_selectedKey) as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> select(String? id) async {
    try {
      final box = Hive.box(_settingsBox);
      if (id == null) {
        await box.delete(_selectedKey);
      } else {
        await box.put(_selectedKey, id);
      }
      revision.value++;
    } catch (_) {/* настройки недоступны — выбор просто не запомнится */}
  }

  /// Считает сводку по каждому счёту из переданных операций.
  ///
  /// Операции без `accountId` попадают в основной счёт — см.
  /// [TransactionModel.effectiveAccountId].
  static Future<List<AccountSummary>> summaries(
    List<TransactionModel> transactions, {
    DateTime? asOf,
  }) async {
    final accounts = await getAll();
    final now = asOf ?? DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day, now.hour, now.minute,
        now.second, now.millisecond, now.microsecond);
    final recurringIncomeIds = transactions
        .where((tx) => tx.isRecurring && tx.type == TransactionType.income)
        .map((tx) => tx.id)
        .toList();
    bool legacyAutoIncome(TransactionModel tx) =>
        !tx.isRecurring &&
        tx.type == TransactionType.income &&
        recurringIncomeIds.any((id) => tx.id.startsWith('${id}_'));
    bool actualForBalance(TransactionModel tx) =>
        !tx.isRecurring && !legacyAutoIncome(tx);

    return accounts.map((a) {
      final own = transactions
          .where((t) =>
              t.effectiveAccountId == a.id &&
              !t.date.isAfter(cutoff) &&
              actualForBalance(t))
          .toList();
      var income = 0.0;
      var expense = 0.0;
      for (final t in own) {
        if (t.type == TransactionType.income) {
          income += t.amount;
        } else {
          expense += t.amount;
        }
      }
      return AccountSummary(
        account: a,
        balance: a.openingBalance + income - expense,
        income: income,
        expense: expense,
        operations: own.length,
      );
    }).toList();
  }

  /// Отфильтровать операции по выбранному счёту. `null` — вернуть все.
  static List<TransactionModel> filter(
      List<TransactionModel> transactions, String? accountId) {
    if (accountId == null) return transactions;
    return transactions
        .where((t) => t.effectiveAccountId == accountId)
        .toList();
  }
}
