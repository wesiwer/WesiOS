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

  /// День, за который накоплен текущий счётчик, в виде `2026-08-03`.
  ///
  /// Хранится строкой, а не числом миллисекунд: «сутки» здесь — это
  /// календарный день по местному времени, а не 24 часа с последнего чтения.
  /// Иначе тот, кто читает цитаты каждый вечер, никогда бы не увидел сброса.
  static const String _keyDay = 'quotes_read_day';

  static const int goalPrimary = 10;
  static const int goalSecret = 40;

  /// Текущий счётчик — слушают UI (прогресс-бар, подписи).
  static final ValueNotifier<int> count = ValueNotifier<int>(0);

  /// Событие «только что достигли 10» — одноразовый салют.
  static final ValueNotifier<int> celebratePrimary = ValueNotifier<int>(0);

  /// Событие «только что достигли 40» — секретная надпись.
  static final ValueNotifier<int> celebrateSecret = ValueNotifier<int>(0);

  static bool _loaded = false;

  /// Календарный день как ключ хранения.
  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Вызывать после открытия Hive (как ThemeNotifier.load).
  ///
  /// [now] существует ради тестов: без него «наступил следующий день»
  /// проверялось бы только ожиданием суток.
  static void load({DateTime? now}) {
    try {
      final box = Hive.box(_boxName);
      final today = dayKey(now ?? DateTime.now());
      if (box.get(_keyDay) != today) {
        // Новый день — заряд начинается заново, вместе с поздравлениями.
        // Иначе полоса, набранная однажды, оставалась бы полной навсегда и
        // перестала бы что-либо значить.
        _resetTo(box, today);
        count.value = 0;
      } else {
        count.value = (box.get(_keyCount) as int?) ?? 0;
      }
    } catch (_) {
      count.value = 0;
    }
    _loaded = true;
  }

  static void _resetTo(Box<dynamic> box, String today) {
    box.put(_keyDay, today);
    box.put(_keyCount, 0);
    box.put(_keySeen10, false);
    box.put(_keySeen40, false);
  }

  /// +1 за каждую новую просмотренную цитату (refresh на карточке).
  static Future<void> registerRead({DateTime? now}) async {
    if (!_loaded) load(now: now);

    try {
      final box = Hive.box(_boxName);
      final today = dayKey(now ?? DateTime.now());
      // Проверяем день и здесь: приложение на компьютере живёт неделями, и
      // без этого счётчик, начатый вчера, продолжал бы расти сегодня.
      if (box.get(_keyDay) != today) {
        _resetTo(box, today);
        count.value = 0;
      }

      final next = count.value + 1;
      count.value = next;
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
      count.value = count.value + 1;
    }
  }

  static double get progress01 =>
      (count.value / goalPrimary).clamp(0.0, 1.0);

  static bool get reachedPrimary => count.value >= goalPrimary;
  static bool get reachedSecret => count.value >= goalSecret;
}
