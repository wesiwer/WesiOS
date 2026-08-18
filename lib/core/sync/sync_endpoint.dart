import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

/// Куда синхронизироваться и кем.
class SyncEndpoint {
  static const String _box = 'wesios_settings';
  static const String _urlKey = 'sync_server_url';
  static const String _loginKey = 'sync_server_login';
  static const String _enabledKey = 'sync_enabled';

  /// Старый ключ остаётся только для одноразовой миграции. Auth token и
  /// server session id больше не должны храниться обычной строкой в Hive.
  static const String _legacySessionKey = 'sync_session';
  static const String _secureSessionKey = 'wesios_server_session_v2';

  static const String _lastRunKey = 'sync_last_run';
  static const String _seededKey = 'sync_seeded_at';

  static const String defaultUrl = 'https://api.wesi-inc.ru';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static Map<String, dynamic>? _session;
  static bool _sessionInitialized = false;

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Box<dynamic>? _open() {
    try {
      return Hive.box<dynamic>(_box);
    } catch (_) {
      return null;
    }
  }

  static String get rawUrl => defaultUrl;
  static String get login => '${_open()?.get(_loginKey) ?? ''}';
  static bool get enabled => _open()?.get(_enabledKey) != false;

  /// Загружает remembered session из системного защищённого хранилища.
  ///
  /// Установки предыдущих версий могли иметь JSON с token/sessionId в Hive.
  /// Такой JSON читается ровно один раз, переносится в secure storage и
  /// удаляется из Hive. Если secure storage недоступен, plaintext fallback не
  /// создаётся: текущий процесс ещё может использовать уже подтверждённую
  /// мигрированную сессию, но после перезапуска потребуется новый вход.
  static Future<void> initializeSession() async {
    if (_sessionInitialized) return;
    _sessionInitialized = true;

    Map<String, dynamic>? loaded;
    String? secureRaw;
    try {
      secureRaw = await _secureStorage.read(key: _secureSessionKey);
      loaded = _decodeSession(secureRaw);
      if (secureRaw != null &&
          secureRaw.isNotEmpty &&
          !_hasRevocableSessionShape(loaded)) {
        await _secureStorage.delete(key: _secureSessionKey);
        loaded = null;
      }
    } catch (error) {
      debugPrint('WesiOS secure session read failed: $error');
      try {
        await _secureStorage.delete(key: _secureSessionKey);
      } catch (_) {}
      loaded = null;
    }

    final box = _open();
    final legacyRaw = box?.get(_legacySessionKey);
    if (loaded == null && legacyRaw is String) {
      final legacy = _decodeSession(legacyRaw);
      if (_hasRevocableSessionShape(legacy)) {
        loaded = legacy;
        try {
          await _secureStorage.write(
            key: _secureSessionKey,
            value: jsonEncode(legacy),
          );
        } catch (error) {
          // Никакого возврата к plaintext. Сессия остаётся только в памяти
          // до закрытия приложения и затем пользователь войдёт заново.
          debugPrint('WesiOS secure session migration write failed: $error');
        }
      }
    }

    // Стираем старый plaintext независимо от результата миграции. Старые
    // однофакторные записи без sessionId также удаляются этим путём.
    try {
      await box?.delete(_legacySessionKey);
    } catch (_) {}

    _session = _hasRevocableSessionShape(loaded) ? loaded : null;
    revision.value++;
  }

  /// Сессия считается действующей только если есть и PocketBase token, и
  /// отзывной серверный WesiOS session id. Старые однофакторные сессии без
  /// sessionId намеренно перестают работать после security-обновления.
  static bool get isConnected {
    final s = session;
    if (s == null) return false;
    final until = DateTime.tryParse('${s['expiresAt']}');
    return _hasRevocableSessionShape(s) &&
        until != null &&
        until.isAfter(DateTime.now());
  }

  static String get url => defaultUrl;

  static Future<void> configure({String? url, String? login}) async {
    final box = _open();
    if (box == null) {
      revision.value++;
      return;
    }
    await box.put(_urlKey, defaultUrl);
    if (login != null) await box.put(_loginKey, login.trim());
    revision.value++;
  }

  static Future<void> ensureDefaults() async {
    final box = _open();
    if (box == null) return;
    if (box.get(_urlKey) != defaultUrl) await box.put(_urlKey, defaultUrl);
    if (box.get(_enabledKey) == null) await box.put(_enabledKey, true);
  }

  static Future<void> setEnabled(bool on) async {
    await _open()?.put(_enabledKey, on);
    revision.value++;
  }

  /// Только in-memory snapshot. Persistent copy находится исключительно в
  /// platform secure storage и загружается [initializeSession] на старте.
  static Map<String, dynamic>? get session {
    final value = _session;
    return value == null ? null : Map<String, dynamic>.unmodifiable(value);
  }

  static String? get sessionId {
    final value = _session?['sessionId'];
    return value is String && value.isNotEmpty ? value : null;
  }

  static Future<void> saveSession({
    required String token,
    required String userId,
    required String sessionId,
    required DateTime expiresAt,
  }) async {
    final next = <String, dynamic>{
      'token': token,
      'userId': userId,
      'sessionId': sessionId,
      'expiresAt': expiresAt.toIso8601String(),
    };
    _session = next;
    _sessionInitialized = true;

    try {
      await _secureStorage.write(
        key: _secureSessionKey,
        value: jsonEncode(next),
      );
    } catch (error) {
      // Fail closed for persistence: do not put the token back into Hive.
      // The verified session remains usable only until this process exits.
      debugPrint('WesiOS secure session write failed: $error');
    }
    try {
      await _open()?.delete(_legacySessionKey);
    } catch (_) {}

    await ensureDefaults();
    revision.value++;
  }

  static Future<void> clearSession() async {
    _session = null;
    _sessionInitialized = true;
    try {
      await _secureStorage.delete(key: _secureSessionKey);
    } catch (error) {
      debugPrint('WesiOS secure session delete failed: $error');
    }
    try {
      await _open()?.delete(_legacySessionKey);
    } catch (_) {}
    revision.value++;
  }

  static Map<String, dynamic>? _decodeSession(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } catch (_) {
      return null;
    }
  }

  static bool _hasRevocableSessionShape(Map<String, dynamic>? value) {
    if (value == null) return false;
    final token = value['token'];
    final userId = value['userId'];
    final sid = value['sessionId'];
    final expiresAt = value['expiresAt'];
    return token is String &&
        token.isNotEmpty &&
        userId is String &&
        userId.isNotEmpty &&
        sid is String &&
        sid.isNotEmpty &&
        expiresAt is String &&
        expiresAt.isNotEmpty;
  }

  /// Служебные маркеры обмена должны принадлежать конкретной серверной
  /// учётной записи, а не всей установке приложения. Иначе после выхода из
  /// аккаунта A и входа в аккаунт B второй пользователь наследовал бы
  /// `sync_last_run` первого и движок ошибочно пропускал бы безопасное правило
  /// первого обмена (server wins on conflicts).
  ///
  /// Старые глобальные ключи намеренно НЕ мигрируются в scoped-ключ. После
  /// обновления каждый уже существующий аккаунт один раз проходит безопасный
  /// first-exchange заново. Это консервативнее, чем ошибочно считать его уже
  /// сверенным после смены схемы идентичности.
  static String _metadataKey(String base) {
    final userId = _session?['userId'];
    if (userId is! String || userId.isEmpty) return base;
    return '$base::$userId';
  }

  static DateTime? get lastRun {
    final raw = _open()?.get(_metadataKey(_lastRunKey));
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  static Future<void> markRun(DateTime at) async {
    await _open()?.put(_metadataKey(_lastRunKey), at.toIso8601String());
    revision.value++;
  }

  static DateTime? get seededAt {
    final raw = _open()?.get(_metadataKey(_seededKey));
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  static Future<void> markSeeded(DateTime at) async =>
      _open()?.put(_metadataKey(_seededKey), at.toIso8601String());
}
