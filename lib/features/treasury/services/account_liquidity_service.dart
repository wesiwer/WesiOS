import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/services/currency_service.dart';
import '../models/account_model.dart';
import '../models/transaction_model.dart';
import 'account_service.dart';
import 'forecast_engine.dart';

class AccountLiquidityMeta {
  final String accountId;
  final String currency;

  /// Canonical reporting-currency (RUB in org-v1) equivalent.
  final double minimumBalanceRub;
  final bool allowNetting;
  final double fxHaircut;
  final int transferDelayDays;

  const AccountLiquidityMeta({
    required this.accountId,
    this.currency = 'rub',
    this.minimumBalanceRub = 0,
    this.allowNetting = true,
    this.fxHaircut = 0.03,
    this.transferDelayDays = 0,
  });

  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'currency': currency,
        'minimumBalanceRub': minimumBalanceRub,
        'allowNetting': allowNetting,
        'fxHaircut': fxHaircut,
        'transferDelayDays': transferDelayDays,
      };

  factory AccountLiquidityMeta.fromJson(Map<String, dynamic> json) {
    final rawCurrency = '${json['currency'] ?? 'rub'}'.toLowerCase();
    return AccountLiquidityMeta(
      accountId: '${json['accountId'] ?? ''}',
      currency: CurrencyService.currencies.containsKey(rawCurrency)
          ? rawCurrency
          : 'rub',
      minimumBalanceRub: (json['minimumBalanceRub'] as num?)?.toDouble() ?? 0,
      allowNetting: json['allowNetting'] != false,
      fxHaircut: ((json['fxHaircut'] as num?)?.toDouble() ?? 0.03)
          .clamp(0, 0.25)
          .toDouble(),
      transferDelayDays:
          ((json['transferDelayDays'] as num?)?.toInt() ?? 0).clamp(0, 14),
    );
  }
}

/// Compatibility facade for Horizon liquidity. AccountModel is now the only
/// authoritative source for currency/minimum balance/netting/risk metadata.
/// The old JSON box is read once only to migrate fields that did not previously
/// exist on AccountModel, then ignored to prevent cross-device divergence.
class AccountLiquidityService {
  AccountLiquidityService._();

  static const String boxName = 'wesios_account_liquidity';
  static const String _key = 'meta_v1';
  static bool _legacyMigrated = false;

  static Future<Box<dynamic>> _openLegacy() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<dynamic>(boxName);
    return Hive.openBox<dynamic>(boxName);
  }

  static Future<Map<String, AccountLiquidityMeta>> _legacyMeta() async {
    try {
      final box = await _openLegacy();
      final raw = box.get(_key);
      if (raw is! String || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, AccountLiquidityMeta>{};
      for (final entry in decoded.entries) {
        if (entry.value is! Map) continue;
        final meta = AccountLiquidityMeta.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (meta.accountId.isNotEmpty) result[meta.accountId] = meta;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _migrateLegacyRiskFields() async {
    if (_legacyMigrated) return;
    _legacyMigrated = true;
    final legacy = await _legacyMeta();
    if (legacy.isEmpty) return;
    for (final account in await AccountService.getAllRaw()) {
      final old = legacy[account.id];
      if (old == null) continue;
      // currency/minimumBalance/allowNetting already existed on AccountModel
      // and therefore win any old conflict. Only formerly meta-only fields are
      // migrated into the authoritative account record.
      if ((account.fxHaircut - old.fxHaircut).abs() > 1e-12 ||
          account.transferDelayDays != old.transferDelayDays) {
        await AccountService.save(account.copyWith(
          fxHaircut: old.fxHaircut,
          transferDelayDays: old.transferDelayDays,
        ));
      }
    }
    try {
      await (await _openLegacy()).delete(_key);
    } catch (_) {}
  }

  static AccountLiquidityMeta _fromAccount(AccountModel account) =>
      AccountLiquidityMeta(
        accountId: account.id,
        currency: account.currency.toLowerCase(),
        minimumBalanceRub: account.minimumBalance,
        allowNetting: account.allowNetting,
        fxHaircut: account.fxHaircut,
        transferDelayDays: account.transferDelayDays,
      );

  static Future<Map<String, AccountLiquidityMeta>> allMeta() async {
    await _migrateLegacyRiskFields();
    return {
      for (final account in await AccountService.getAllRaw())
        account.id: _fromAccount(account),
    };
  }

  static Future<AccountLiquidityMeta> forAccount(AccountModel account) async {
    await _migrateLegacyRiskFields();
    final fresh = await AccountService.byId(account.id) ?? account;
    return _fromAccount(fresh);
  }

  static Future<void> save(AccountLiquidityMeta meta) async {
    await _migrateLegacyRiskFields();
    final account = await AccountService.byId(meta.accountId);
    if (account == null) throw StateError('account does not exist');
    await AccountService.save(account.copyWith(
      currency: meta.currency.toUpperCase(),
      minimumBalance: meta.minimumBalanceRub,
      allowNetting: meta.allowNetting,
      fxHaircut: meta.fxHaircut,
      transferDelayDays: meta.transferDelayDays,
    ));
  }

  static Future<List<AccountLiquiditySnapshot>> snapshots(
    List<TransactionModel> transactions, {
    Set<String>? organizationIds,
  }) async {
    await _migrateLegacyRiskFields();
    final summaries = await AccountService.summaries(
      transactions,
      organizationIds: organizationIds,
    );
    return [
      for (final summary in summaries)
        AccountLiquiditySnapshot(
          accountId: summary.account.id,
          name: summary.account.name,
          balance: summary.balance,
          currency: summary.account.currency.toLowerCase(),
          minimumBalance: summary.account.minimumBalance,
          allowNetting: summary.account.allowNetting,
          fxHaircut: summary.account.fxHaircut,
          transferDelayDays: summary.account.transferDelayDays,
        ),
    ];
  }

  static Future<double> nettableRub({
    required AccountLiquiditySnapshot from,
    required AccountLiquiditySnapshot to,
  }) async {
    if (!from.allowNetting || from.accountId == to.accountId) return 0;
    final free = (from.balance - from.minimumBalance)
        .clamp(0, double.infinity)
        .toDouble();
    if (free == 0) return 0;
    if (from.currency.toLowerCase() == to.currency.toLowerCase()) return free;
    final account = await AccountService.byId(from.accountId);
    final haircut = account?.fxHaircut ?? 0.03;
    return free * (1 - haircut);
  }

  static Future<void> clearForTest() async {
    _legacyMigrated = false;
    final box = await _openLegacy();
    await box.clear();
  }
}
