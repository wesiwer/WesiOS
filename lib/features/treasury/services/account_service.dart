import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../organizations/models/organization_access_grant.dart';
import '../../organizations/services/organization_access_service.dart';
import '../../organizations/services/organization_context.dart';
import '../../organizations/services/organization_service.dart';
import '../../team/services/team_service.dart';
import '../models/account_model.dart';
import '../models/transaction_model.dart';

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

class AccountService {
  static const String _boxName = 'wesios_accounts';
  static const String _settingsBox = 'wesios_settings';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Box<AccountModel>? _box;

  static Future<Box<AccountModel>> get _accountsBox async {
    _box ??= await Hive.openBox<AccountModel>(_boxName);
    return _box!;
  }

  static String get _selectedKey =>
      'selected_account.${OrganizationContext.currentOrganizationId}';

  static Future<AccountModel> ensureMain({String? organizationId}) async {
    await OrganizationService.ensureBaseline();
    final orgId = organizationId ?? OrganizationContext.currentOrganizationId;
    final org = await OrganizationService.byId(orgId);
    if (org == null) throw StateError('organization does not exist: $orgId');
    final box = await _accountsBox;
    final id = AccountModel.mainIdFor(orgId);
    final existing = box.get(id);
    if (existing != null) {
      if (existing.organizationId == null) {
        final migrated = existing.copyWith(organizationId: orgId);
        await box.put(id, migrated);
        return migrated;
      }
      return existing;
    }
    final main = AccountModel(
      id: id,
      name: WesiLocale.isRussian ? 'Основной счёт' : 'Main account',
      kind: AccountKind.main,
      createdAt: DateTime.now(),
      organizationId: orgId,
      currency: org.baseCurrency,
    );
    await box.put(main.id, main);
    revision.value++;
    return main;
  }

  /// Raw list is intentionally reserved for migration/audit/admin operations.
  static Future<List<AccountModel>> getAllRaw({bool includeArchived = true}) async {
    final box = await _accountsBox;
    return box.values.where((a) => includeArchived || !a.archived).toList();
  }

  static Future<List<AccountModel>> getAll({bool includeArchived = true}) async {
    var ids = await OrganizationContext.effectiveOrganizationIds();
    if (TeamService.current != null) {
      final financeIds = await OrganizationAccessService.organizationIdsFor(
        OrganizationPermissions.viewFinance,
      );
      ids = ids.intersection(financeIds);
    }
    for (final id in ids) {
      await ensureMain(organizationId: id);
    }
    final box = await _accountsBox;
    final list = box.values
        .where((a) =>
            ids.contains(a.effectiveOrganizationId) &&
            (includeArchived || !a.archived))
        .toList()
      ..sort((a, b) {
        if (a.kind == AccountKind.main && b.kind != AccountKind.main) return -1;
        if (b.kind == AccountKind.main && a.kind != AccountKind.main) return 1;
        return a.createdAt.compareTo(b.createdAt);
      });
    return list;
  }

  static Future<List<AccountModel>> forOrganization(
    String organizationId, {
    bool includeArchived = true,
  }) async {
    if (TeamService.current != null &&
        !await OrganizationAccessService.canViewOrganizationFinance(organizationId)) {
      return const <AccountModel>[];
    }
    await ensureMain(organizationId: organizationId);
    final box = await _accountsBox;
    return box.values
        .where((a) =>
            a.effectiveOrganizationId == organizationId &&
            (includeArchived || !a.archived))
        .toList();
  }

  static Future<AccountModel?> byId(String id) async => (await _accountsBox).get(id);

  static Future<void> save(AccountModel account) async {
    final orgId = account.organizationId ?? OrganizationContext.currentOrganizationId;
    if (await OrganizationService.byId(orgId) == null) {
      throw StateError('account organization does not exist');
    }
    if (TeamService.current != null &&
        !await OrganizationAccessService.can(
          orgId,
          OrganizationPermissions.manageAccounts,
        )) {
      throw StateError('manage_accounts permission required');
    }
    final normalized = account.organizationId == null
        ? account.copyWith(organizationId: orgId)
        : account;
    await (await _accountsBox).put(normalized.id, normalized);
    revision.value++;
  }

  static Future<AccountModel> create({
    required String name,
    AccountKind kind = AccountKind.project,
    double openingBalance = 0,
    int colorValue = 0xFF38BDF8,
    String? note,
    String? organizationId,
    double minimumBalance = 0,
    bool allowNetting = true,
    String? currency,
  }) async {
    final orgId = organizationId ?? OrganizationContext.currentOrganizationId;
    final org = await OrganizationService.byId(orgId);
    if (org == null || org.archived) throw StateError('organization unavailable');
    final account = AccountModel(
      id: 'acct_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      kind: kind,
      openingBalance: openingBalance,
      colorValue: colorValue,
      createdAt: DateTime.now(),
      note: note,
      organizationId: orgId,
      minimumBalance: minimumBalance,
      allowNetting: allowNetting,
      currency: (currency ?? org.baseCurrency).toUpperCase(),
    );
    await save(account);
    return account;
  }

  static Future<bool> delete(String id, {required bool hasOperations}) async {
    final box = await _accountsBox;
    final account = box.get(id);
    if (account == null || account.kind == AccountKind.main) return false;
    if (TeamService.current != null &&
        !await OrganizationAccessService.can(
          account.effectiveOrganizationId,
          OrganizationPermissions.manageAccounts,
        )) {
      return false;
    }
    if (hasOperations) {
      await save(account.copyWith(archived: true));
      return true;
    }
    await box.delete(id);
    if (selectedId == id) await select(null);
    revision.value++;
    return true;
  }

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
        final account = await byId(id);
        if (account == null ||
            account.effectiveOrganizationId != OrganizationContext.currentOrganizationId) {
          throw StateError('account is outside current organization');
        }
        await box.put(_selectedKey, id);
      }
      revision.value++;
    } catch (_) {
      if (id != null) rethrow;
    }
  }

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
              t.effectiveOrganizationId == a.effectiveOrganizationId &&
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

  static List<TransactionModel> filter(
      List<TransactionModel> transactions, String? accountId) {
    if (accountId == null) return transactions;
    return transactions.where((t) => t.effectiveAccountId == accountId).toList();
  }

  static Future<Map<String, double>> balancesByOrganization(
    List<TransactionModel> transactions,
  ) async {
    final result = <String, double>{};
    for (final summary in await summaries(transactions)) {
      result.update(
        summary.account.effectiveOrganizationId,
        (value) => value + summary.balance,
        ifAbsent: () => summary.balance,
      );
    }
    return result;
  }
}
