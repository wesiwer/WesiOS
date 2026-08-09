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

  /// Stored in RUB-equivalent, like the rest of Treasury's internal ledger.
  final double minimumBalanceRub;
  final bool allowNetting;
  final double fxHaircut;

  const AccountLiquidityMeta({
    required this.accountId,
    this.currency = 'rub',
    this.minimumBalanceRub = 0,
    this.allowNetting = true,
    this.fxHaircut = 0.03,
  });

  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'currency': currency,
        'minimumBalanceRub': minimumBalanceRub,
        'allowNetting': allowNetting,
        'fxHaircut': fxHaircut,
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
    );
  }
}

/// Metadata that turns “several accounts” into liquidity locations rather
/// than one undifferentiated balance. Existing AccountModel/Hive adapters are
/// intentionally not changed, so old installations require no migration.
class AccountLiquidityService {
  AccountLiquidityService._();

  static const String boxName = 'wesios_account_liquidity';
  static const String _key = 'meta_v1';

  static Future<Box<dynamic>> _open() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<dynamic>(boxName);
    return Hive.openBox<dynamic>(boxName);
  }

  static Future<Map<String, AccountLiquidityMeta>> allMeta() async {
    try {
      final box = await _open();
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

  static Future<AccountLiquidityMeta> forAccount(AccountModel account) async {
    final map = await allMeta();
    return map[account.id] ?? AccountLiquidityMeta(accountId: account.id);
  }

  static Future<void> save(AccountLiquidityMeta meta) async {
    final map = await allMeta();
    map[meta.accountId] = meta;
    final box = await _open();
    await box.put(
      _key,
      jsonEncode({for (final e in map.entries) e.key: e.value.toJson()}),
    );
  }

  /// Converts AccountService summaries into the risk-engine representation.
  /// Balances stay in RUB-equivalent for arithmetic; [currency] says where
  /// that liquidity physically lives and therefore whether FX/netting is
  /// required to cover another location.
  static Future<List<AccountLiquiditySnapshot>> snapshots(
    List<TransactionModel> transactions,
  ) async {
    final summaries = await AccountService.summaries(transactions);
    final meta = await allMeta();
    return [
      for (final summary in summaries)
        AccountLiquiditySnapshot(
          accountId: summary.account.id,
          name: summary.account.name,
          balance: summary.balance,
          currency: (meta[summary.account.id] ??
                  AccountLiquidityMeta(accountId: summary.account.id))
              .currency,
          minimumBalance: (meta[summary.account.id] ??
                  AccountLiquidityMeta(accountId: summary.account.id))
              .minimumBalanceRub,
          allowNetting: (meta[summary.account.id] ??
                  AccountLiquidityMeta(accountId: summary.account.id))
              .allowNetting,
          fxHaircut: (meta[summary.account.id] ??
                  AccountLiquidityMeta(accountId: summary.account.id))
              .fxHaircut,
        ),
    ];
  }

  /// Conservative amount of RUB-equivalent cash transferable from [from] to
  /// cover [to]. FX conversion is haircut when currencies differ, so a USD
  /// balance is not treated as instantly identical to RUB liquidity.
  static Future<double> nettableRub({
    required AccountLiquiditySnapshot from,
    required AccountLiquiditySnapshot to,
  }) async {
    if (!from.allowNetting || from.accountId == to.accountId) return 0;
    final meta = await allMeta();
    final own =
        meta[from.accountId] ?? AccountLiquidityMeta(accountId: from.accountId);
    final free = (from.balance - from.minimumBalance)
        .clamp(0, double.infinity)
        .toDouble();
    if (free == 0) return 0;
    if (from.currency == to.currency) return free;
    return free * (1 - own.fxHaircut);
  }

  static Future<void> clearForTest() async {
    final box = await _open();
    await box.clear();
  }
}
