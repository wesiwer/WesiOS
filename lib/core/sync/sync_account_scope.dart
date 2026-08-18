import 'sync_endpoint.dart';

/// Единый namespace локальных хранилищ, которые сервер считает приватными.
///
/// Серверный private scope привязан к PocketBase auth user (`e.auth.id`).
/// Локальный Hive обязан использовать тот же идентификатор: иначе данные
/// сотрудника A, оставшиеся на общем устройстве, становятся «локальными» для
/// сотрудника B и первый Sync может загрузить их уже в private scope B.
class SyncAccountScope {
  const SyncAccountScope._();

  /// Имя персонального Hive-box для текущей подтверждённой server-сессии.
  ///
  /// Когда сессии нет, используем отдельный anonymous namespace и никогда не
  /// возвращаем старое unscoped-имя. Это принципиально: logout не должен снова
  /// открыть legacy-box, в котором могли остаться данные предыдущего аккаунта.
  static String boxName(String base) {
    final userId = SyncEndpoint.session?['userId'];
    return forUser(base, userId is String ? userId : null);
  }

  /// Чистая часть вынесена отдельно, чтобы правило namespace можно было
  /// проверить unit-тестом без подмены secure session.
  static String forUser(String base, String? userId) {
    final normalizedBase = _safe(base.trim().isEmpty ? 'wesios_private' : base);
    final rawUser = (userId ?? '').trim();
    final normalizedUser = rawUser.isEmpty ? 'anonymous' : _safe(rawUser);
    return '${normalizedBase}__acct_$normalizedUser';
  }

  static String _safe(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return sanitized.isEmpty ? 'anonymous' : sanitized;
  }
}
