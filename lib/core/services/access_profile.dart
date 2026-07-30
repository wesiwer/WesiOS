import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'firebase_rest_service.dart';

/// Что открыто конкретному человеку.
///
/// Владелец заводит учётную запись в консоли Firebase и там же создаёт
/// документ `access/<UID>` с набором разрешённых разделов. Приложение его
/// читает и показывает только то, что открыто.
///
/// **Это не защита, а удобство** — и путать одно с другим опасно. Спрятать
/// вкладку значит убрать её с экрана, а не закрыть данные: приложение можно
/// переписать. По-настоящему закрывают данные правила Firestore, и они
/// действуют независимо от этого списка.
class AccessProfile {
  /// Разделы, которые можно выдавать по отдельности.
  ///
  /// Имена совпадают с полями документа `access/<UID>`, чтобы владелец в
  /// консоли видел ровно те слова, что и в приложении.
  static const List<String> modules = [
    'treasury',
    'forecast',
    'sandbox',
    'analytics',
    'tasks',
    'calendar',
    'knowledge',
  ];

  /// Что открыто, если документа `access/<UID>` нет вовсе.
  ///
  /// Не пусто — и это осознанно. Забытый документ означал бы, что человек
  /// вошёл и не увидел ничего: выглядит как поломка, а не как политика.
  /// Базовый набор безопасен, потому что данные всё равно изолированы
  /// правилами: коллега видит свои цифры, а не чужие. Чтобы урезать —
  /// владелец создаёт документ явно.
  static const Map<String, bool> defaults = {
    'treasury': true,
    'forecast': true,
    'sandbox': true,
    'analytics': true,
    'tasks': true,
    'calendar': true,
    'knowledge': true,
  };

  static const String _box = 'wesios_settings';
  static const String _cacheKey = 'access_profile';
  static const String _cacheUidKey = 'access_profile_uid';

  /// Меняется при обновлении — экраны перечитывают набор.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Map<String, bool>? _current;

  /// Действующий набор прав.
  ///
  /// Без входа — базовый: приложение работает локально и никого не
  /// ограничивает, ограничивать там некого.
  static Map<String, bool> get current {
    if (!FirebaseRestService.isSignedIn) return defaults;
    return _current ?? _readCache() ?? defaults;
  }

  static bool allows(String module) => current[module] ?? false;

  static Map<String, bool>? _readCache() {
    try {
      final box = Hive.box(_box);
      // Кеш чужого профиля показывать нельзя: сменили аккаунт — набор прав
      // должен смениться вместе с ним, а не остаться от предыдущего.
      if (box.get(_cacheUidKey) != FirebaseRestService.session?.uid) {
        return null;
      }
      final raw = box.get(_cacheKey);
      if (raw is! Map) return null;
      return {
        for (final m in modules) m: raw[m] == true,
      };
    } catch (_) {
      return null;
    }
  }

  /// Перечитывает права из Firestore.
  ///
  /// Кеширует их локально, чтобы без сети приложение не схлопывалось до
  /// базового набора и обратно — мигающие вкладки хуже, чем чуть устаревший
  /// список.
  static Future<Map<String, bool>> refresh() async {
    final uid = FirebaseRestService.session?.uid;
    if (uid == null) {
      _current = null;
      revision.value++;
      return defaults;
    }

    final doc = await FirebaseRestService.getDocument('access/$uid');
    if (doc == null) {
      // Документа нет или нет связи. Кеш предпочтительнее умолчаний: он
      // ближе к тому, что владелец действительно выдал.
      _current = _readCache() ?? defaults;
      revision.value++;
      return _current!;
    }

    // В Firestore значения приходят строками через наш REST-слой, поэтому
    // истиной считаем явное 'true'. Всё остальное — запрет: неизвестное
    // значение безопаснее прочитать как «не открыто».
    final parsed = {
      for (final m in modules) m: doc[m]?.toLowerCase() == 'true',
    };
    _current = parsed;

    try {
      final box = Hive.box(_box);
      await box.put(_cacheKey, parsed);
      await box.put(_cacheUidKey, uid);
    } catch (_) {/* кеш не обязателен */}

    revision.value++;
    return parsed;
  }

  /// Забыть права: вызывается при выходе.
  static Future<void> clear() async {
    _current = null;
    try {
      final box = Hive.box(_box);
      await box.delete(_cacheKey);
      await box.delete(_cacheUidKey);
    } catch (_) {/* нечего удалять */}
    revision.value++;
  }
}
