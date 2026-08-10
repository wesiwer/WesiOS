import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/localization/wesi_locale.dart';
import '../../organizations/models/organization_model.dart';
import '../../organizations/services/organization_context.dart';
import '../models/transaction_model.dart';

/// Categories are organization-owned vocabulary. Legacy keys remain the
/// Wesi Inc source so existing custom categories survive migration without
/// duplicating or silently resetting them.
class CategoryService {
  static const String _box = 'wesios_settings';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static const List<String> incomeDefaultsRu = [
    'Продажи', 'Услуги', 'Фриланс', 'Подписки', 'Инвестиции', 'Возвраты', 'Прочий доход',
  ];
  static const List<String> incomeDefaultsEn = [
    'Sales', 'Services', 'Freelance', 'Subscriptions', 'Investments', 'Refunds', 'Other income',
  ];
  static const List<String> expenseDefaultsRu = [
    'ПО', 'Маркетинг', 'Офис', 'Зарплаты', 'Инфраструктура', 'Налоги', 'Оборудование', 'Прочие расходы',
  ];
  static const List<String> expenseDefaultsEn = [
    'Software', 'Marketing', 'Office', 'Salaries', 'Infrastructure', 'Taxes', 'Equipment', 'Other expenses',
  ];

  static String _legacyKey(TransactionType type) {
    final lang = WesiLocale.isRussian ? 'ru' : 'en';
    final kind = type == TransactionType.income ? 'income' : 'expense';
    return 'categories_${kind}_$lang';
  }

  static String _key(TransactionType type, [String? organizationId]) {
    final orgId = organizationId ?? OrganizationContext.currentOrganizationId;
    if (orgId == OrganizationModel.rootId) return _legacyKey(type);
    return '${_legacyKey(type)}.$orgId';
  }

  static List<String> defaultsFor(TransactionType type) {
    final ru = WesiLocale.isRussian;
    if (type == TransactionType.income) {
      return List<String>.from(ru ? incomeDefaultsRu : incomeDefaultsEn);
    }
    return List<String>.from(ru ? expenseDefaultsRu : expenseDefaultsEn);
  }

  static List<String> forType(
    TransactionType type, {
    String? organizationId,
  }) {
    try {
      final raw = Hive.box(_box).get(_key(type, organizationId));
      if (raw is List && raw.isNotEmpty) {
        return raw.map((e) => '$e').toList();
      }
    } catch (_) {}
    return defaultsFor(type);
  }

  static List<String> get all => [
        ...forType(TransactionType.income),
        ...forType(TransactionType.expense),
      ];

  static Future<void> _save(
    TransactionType type,
    List<String> list, {
    String? organizationId,
  }) async {
    await Hive.box(_box).put(_key(type, organizationId), list);
    revision.value++;
  }

  static Future<void> add(TransactionType type, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final list = forType(type);
    if (list.any((c) => c.toLowerCase() == trimmed.toLowerCase())) return;
    list.add(trimmed);
    await _save(type, list);
  }

  static Future<void> rename(
    TransactionType type,
    String from,
    String to,
  ) async {
    final trimmed = to.trim();
    if (trimmed.isEmpty) return;
    final list = forType(type);
    final i = list.indexOf(from);
    if (i == -1) return;
    list[i] = trimmed;
    await _save(type, list);
  }

  static Future<bool> remove(TransactionType type, String name) async {
    final list = forType(type);
    if (list.length <= 1) return false;
    if (!list.remove(name)) return false;
    await _save(type, list);
    return true;
  }

  static Future<void> resetToDefaults(TransactionType type) async {
    await _save(type, defaultsFor(type));
  }
}
