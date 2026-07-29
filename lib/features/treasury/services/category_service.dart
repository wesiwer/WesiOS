import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/localization/wesi_locale.dart';

/// Категории операций, которые пользователь может менять сам.
///
/// Раньше список был захардкожен прямо в диалоге добавления, поэтому
/// подогнать его под своё дело было нельзя — а «ПО / Маркетинг / Офис»
/// подходит далеко не каждому. Теперь набор хранится в Hive и правится
/// из самого диалога.
class CategoryService {
  static const String _box = 'wesios_settings';
  static const String _keyRu = 'categories_ru';
  static const String _keyEn = 'categories_en';

  /// Инкрементируется при любом изменении списка — открытые экраны
  /// перечитывают категории без перезапуска.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static const List<String> defaultsRu = [
    'ПО',
    'Маркетинг',
    'Офис',
    'Зарплаты',
    'Фриланс',
    'Инвестиции',
    'Инфраструктура',
    'Другое',
  ];

  static const List<String> defaultsEn = [
    'Software',
    'Marketing',
    'Office',
    'Salaries',
    'Freelance',
    'Investments',
    'Infrastructure',
    'Other',
  ];

  static String get _key => WesiLocale.isRussian ? _keyRu : _keyEn;
  static List<String> get _defaults =>
      WesiLocale.isRussian ? defaultsRu : defaultsEn;

  /// Текущий список для активного языка.
  static List<String> get all {
    try {
      final raw = Hive.box(_box).get(_key);
      if (raw is List && raw.isNotEmpty) {
        return raw.map((e) => '$e').toList();
      }
    } catch (_) {
      // Бокс не открыт — отдаём значения по умолчанию.
    }
    return List<String>.from(_defaults);
  }

  static Future<void> _save(List<String> list) async {
    await Hive.box(_box).put(_key, list);
    revision.value++;
  }

  /// Добавляет категорию. Дубликаты игнорируются без ошибки — повторное
  /// добавление того же имени не должно ломать поток пользователя.
  static Future<void> add(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final list = all;
    if (list.any((c) => c.toLowerCase() == trimmed.toLowerCase())) return;
    list.add(trimmed);
    await _save(list);
  }

  static Future<void> rename(String from, String to) async {
    final trimmed = to.trim();
    if (trimmed.isEmpty) return;
    final list = all;
    final i = list.indexOf(from);
    if (i == -1) return;
    list[i] = trimmed;
    await _save(list);
  }

  /// Удаляет категорию. Последнюю удалить нельзя — иначе в диалоге
  /// добавления операции не осталось бы ни одного варианта.
  static Future<bool> remove(String name) async {
    final list = all;
    if (list.length <= 1) return false;
    if (!list.remove(name)) return false;
    await _save(list);
    return true;
  }

  static Future<void> resetToDefaults() async {
    await _save(List<String>.from(_defaults));
  }
}
