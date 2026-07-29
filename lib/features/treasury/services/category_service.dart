import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/localization/wesi_locale.dart';
import '../models/transaction_model.dart';

/// Категории операций, которые пользователь может менять сам.
///
/// Раньше список был захардкожен прямо в диалоге добавления, поэтому
/// подогнать его под своё дело было нельзя — а «ПО / Маркетинг / Офис»
/// подходит далеко не каждому.
///
/// Наборы у доходов и расходов **раздельные**: общий список заставлял
/// выбирать «Зарплаты» для поступления и «Фриланс» для траты — категории
/// из другой половины бизнеса только мешали и портили разрезы в аналитике.
class CategoryService {
  static const String _box = 'wesios_settings';

  /// Инкрементируется при любом изменении списка — открытые экраны
  /// перечитывают категории без перезапуска.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static const List<String> incomeDefaultsRu = [
    'Продажи',
    'Услуги',
    'Фриланс',
    'Подписки',
    'Инвестиции',
    'Возвраты',
    'Прочий доход',
  ];

  static const List<String> incomeDefaultsEn = [
    'Sales',
    'Services',
    'Freelance',
    'Subscriptions',
    'Investments',
    'Refunds',
    'Other income',
  ];

  static const List<String> expenseDefaultsRu = [
    'ПО',
    'Маркетинг',
    'Офис',
    'Зарплаты',
    'Инфраструктура',
    'Налоги',
    'Оборудование',
    'Прочие расходы',
  ];

  static const List<String> expenseDefaultsEn = [
    'Software',
    'Marketing',
    'Office',
    'Salaries',
    'Infrastructure',
    'Taxes',
    'Equipment',
    'Other expenses',
  ];

  /// Ключ хранения: свой на каждую пару (тип операции × язык).
  static String _key(TransactionType type) {
    final lang = WesiLocale.isRussian ? 'ru' : 'en';
    final kind = type == TransactionType.income ? 'income' : 'expense';
    return 'categories_${kind}_$lang';
  }

  static List<String> defaultsFor(TransactionType type) {
    final ru = WesiLocale.isRussian;
    if (type == TransactionType.income) {
      return List<String>.from(ru ? incomeDefaultsRu : incomeDefaultsEn);
    }
    return List<String>.from(ru ? expenseDefaultsRu : expenseDefaultsEn);
  }

  /// Текущий список для типа операции и активного языка.
  static List<String> forType(TransactionType type) {
    try {
      final raw = Hive.box(_box).get(_key(type));
      if (raw is List && raw.isNotEmpty) {
        return raw.map((e) => '$e').toList();
      }
    } catch (_) {
      // Бокс не открыт — отдаём значения по умолчанию.
    }
    return defaultsFor(type);
  }

  /// Все категории обеих половин — для фильтров и разрезов в аналитике,
  /// где операции обоих типов лежат вперемешку.
  static List<String> get all => [
        ...forType(TransactionType.income),
        ...forType(TransactionType.expense),
      ];

  static Future<void> _save(TransactionType type, List<String> list) async {
    await Hive.box(_box).put(_key(type), list);
    revision.value++;
  }

  /// Добавляет категорию. Дубликаты игнорируются без ошибки — повторное
  /// добавление того же имени не должно ломать поток пользователя.
  static Future<void> add(TransactionType type, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final list = forType(type);
    if (list.any((c) => c.toLowerCase() == trimmed.toLowerCase())) return;
    list.add(trimmed);
    await _save(type, list);
  }

  static Future<void> rename(
      TransactionType type, String from, String to) async {
    final trimmed = to.trim();
    if (trimmed.isEmpty) return;
    final list = forType(type);
    final i = list.indexOf(from);
    if (i == -1) return;
    list[i] = trimmed;
    await _save(type, list);
  }

  /// Удаляет категорию. Последнюю удалить нельзя — иначе в диалоге
  /// добавления операции не осталось бы ни одного варианта.
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
