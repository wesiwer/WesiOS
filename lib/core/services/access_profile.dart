import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../features/team/services/team_service.dart';

/// Совместимый фасад прав доступа для старых экранов.
///
/// Источник истины теперь только один — подтверждённая сервером TeamService
/// сессия. Старый Firebase access document больше не может открыть модуль и,
/// главное, отсутствие Firebase-сессии больше не означает «разрешить всё».
class AccessProfile {
  static const List<String> modules = [
    'treasury',
    'forecast',
    'sandbox',
    'analytics',
    'tasks',
    'calendar',
    'knowledge',
  ];

  /// Fail-closed состояние до входа.
  static const Map<String, bool> defaults = {
    'treasury': false,
    'forecast': false,
    'sandbox': false,
    'analytics': false,
    'tasks': false,
    'calendar': false,
    'knowledge': false,
  };

  static const String _box = 'wesios_settings';
  static const String _cacheKey = 'access_profile';
  static const String _cacheUidKey = 'access_profile_uid';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Действующий набор строится из текущего подтверждённого пользователя.
  static Map<String, bool> get current {
    final employee = TeamService.current;
    if (employee == null) return defaults;
    final permissions = employee.permissions;
    return {
      for (final module in modules) module: permissions.allows(module),
    };
  }

  static bool allows(String module) => current[module] ?? false;

  /// Оставлено для совместимости со старыми вызовами refresh(). Сетевого
  /// Firebase-запроса здесь больше нет: права уже пришли из PocketBase
  /// bootstrap вместе с личностью пользователя.
  static Future<Map<String, bool>> refresh() async {
    revision.value++;
    return current;
  }

  /// Чистим legacy Firebase access cache, чтобы старые сохранённые true не
  /// могли когда-нибудь снова стать источником разрешений.
  static Future<void> clear() async {
    try {
      final box = Hive.box(_box);
      await box.delete(_cacheKey);
      await box.delete(_cacheUidKey);
    } catch (_) {/* legacy кеш мог отсутствовать */}
    revision.value++;
  }
}
