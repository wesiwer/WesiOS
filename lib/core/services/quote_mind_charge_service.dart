import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Счётчик «заряда умных мыслей» — сколько цитат пользователь реально
/// пролистал (кнопка «другая фраза» на карточке).
///
/// Хранится в `wesios_settings`, чтобы прогресс не сбрасывался при
/// перезапуске. Пороги:
/// - 10 → полный прогресс + поздравление;
/// - 40 (ещё 30) → секретная надпись.
class QuoteMindChargeService {
  QuoteMindChargeService._();

  static const String _boxName = 'wesios_settings';
  static const String _keyCount = 'quotes_read_count';
  static const String _keySeen10 = 'quotes_milestone_10_seen';
  static const String _keySeen40 = 'quotes_milestone_40_seen';

  static const int goalPrimary = 10;
  static const int goalSecret = 40;

  /// Текущий счётчик — слушают UI (прогресс-бар, подписи).
  static final ValueNotifier<int> count = ValueNotifier<int>(0);

  /// Событие «только что достигли 10» — одноразовый салют.
  static final ValueNotifier<int> celebratePrimary = ValueNotifier<int>(0);

  /// Событие «только что достигли 40» — секретная надпись.
  static final ValueNotifier<int> celebrateSecret = ValueNotifier<int>(0);

  static bool _loaded = false;

  /// Вызывать после открытия Hive (как ThemeNotifier.load).
  static void load() {
    try {
      final box = Hive.box(_boxName);
      count.value = (box.get(_keyCount) as int?) ?? 0;
    } catch (_) {
      count.value = 0;
    }
    _loaded = true;
  }

  /// +1 за каждую новую просмотренную цитату (refresh на карточке).
  static Future<void> registerRead() async {
    if (!_loaded) load();
    final next = count.value + 1;
    count.value = next;

    try {
      final box = Hive.box(_boxName);
      await box.put(_keyCount, next);

      if (next >= goalPrimary && box.get(_keySeen10) != true) {
        await box.put(_keySeen10, true);
        celebratePrimary.value = celebratePrimary.value + 1;
      }
      if (next >= goalSecret && box.get(_keySeen40) != true) {
        await box.put(_keySeen40, true);
        celebrateSecret.value = celebrateSecret.value + 1;
      }
    } catch (_) {
      // Hive недоступен — счётчик всё равно живёт в сессии через ValueNotifier.
    }
  }

  static double get progress01 =>
      (count.value / goalPrimary).clamp(0.0, 1.0);

  static bool get reachedPrimary => count.value >= goalPrimary;
  static bool get reachedSecret => count.value >= goalSecret;
}
