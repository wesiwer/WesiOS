import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Куда синхронизироваться и кем.
///
/// Производственная сборка WesiOS работает только с корпоративным сервером.
/// Адрес больше не вводится руками: это устраняет опечатки, небезопасный HTTP
/// и ситуацию, когда сотрудник случайно подключил приложение не к Wesi Inc.
class SyncEndpoint {
  static const String _box = 'wesios_settings';
  static const String _urlKey = 'sync_server_url';
  static const String _loginKey = 'sync_server_login';
  static const String _enabledKey = 'sync_enabled';
  static const String _sessionKey = 'sync_session';
  static const String _lastRunKey = 'sync_last_run';
  static const String _seededKey = 'sync_seeded_at';

  /// Единый российский сервер учётных записей и синхронизации WesiOS.
  static const String defaultUrl = 'https://api.wesi-inc.ru';

  /// Меняется при входе, выходе и смене настроек — экраны перечитывают.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Box<dynamic>? _open() {
    try {
      return Hive.box<dynamic>(_box);
    } catch (_) {
      return null;
    }
  }

  /// Старые установки могли сохранить IP или пустую строку. Для рабочих
  /// запросов это больше не используется: приложение всегда идёт на домен с
  /// действующим TLS-сертификатом.
  static String get rawUrl => defaultUrl;

  static String get login => '${_open()?.get(_loginKey) ?? ''}';

  /// После успешного входа автоматический обмен включён по умолчанию.
  static bool get enabled => _open()?.get(_enabledKey) != false;

  static bool get isConfigured => true;

  static String? normalize(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    final uri = Uri.tryParse(s.contains('://') ? s : 'https://$s');
    if (uri == null || uri.host.isEmpty || uri.scheme != 'https') return null;
    return '${uri.scheme}://${uri.authority}';
  }

  static String get url => defaultUrl;

  /// [url] оставлен в сигнатуре для совместимости со старым кодом, но
  /// намеренно игнорируется. Логин хранится, пароль — никогда.
  static Future<void> configure({String? url, String? login}) async {
    final box = _open();
    if (box == null) return;
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

  // ------------------------------------------------------------- сессия

  /// Токен и срок его жизни. Пароль после входа нигде не сохраняется.
  static Map<String, dynamic>? get session {
    final raw = _open()?.get(_sessionKey);
    if (raw is! String) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveSession({
    required String token,
    required String userId,
    required DateTime expiresAt,
  }) async {
    await _open()?.put(
      _sessionKey,
      jsonEncode({
        'token': token,
        'userId': userId,
        'expiresAt': expiresAt.toIso8601String(),
      }),
    );
    await ensureDefaults();
    revision.value++;
  }

  static Future<void> clearSession() async {
    await _open()?.delete(_sessionKey);
    revision.value++;
  }

  // -------------------------------------------------------------- отметки

  static DateTime? get lastRun {
    final raw = _open()?.get(_lastRunKey);
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  static Future<void> markRun(DateTime at) async {
    await _open()?.put(_lastRunKey, at.toIso8601String());
    revision.value++;
  }

  static DateTime? get seededAt {
    final raw = _open()?.get(_seededKey);
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  static Future<void> markSeeded(DateTime at) async =>
      _open()?.put(_seededKey, at.toIso8601String());
}
