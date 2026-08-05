import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Куда синхронизироваться и кем.
///
/// Рабочая сборка всегда использует корпоративный сервер WesiOS. Метод
/// [normalize] остаётся совместимым со старыми импортами и тестами, но его
/// результат больше не выбирает production endpoint.
class SyncEndpoint {
  static const String _box = 'wesios_settings';
  static const String _urlKey = 'sync_server_url';
  static const String _loginKey = 'sync_server_login';
  static const String _enabledKey = 'sync_enabled';
  static const String _sessionKey = 'sync_session';
  static const String _lastRunKey = 'sync_last_run';
  static const String _seededKey = 'sync_seeded_at';

  static const String defaultUrl = 'https://api.wesi-inc.ru';

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
  static bool get isConfigured => true;

  static String? normalize(String input) {
    var value = input.trim();
    if (value.isEmpty) return null;
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.isEmpty) return null;

    if (!value.contains('://')) {
      final host = value.split(':').first;
      final isBareIp = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host);
      value = '${isBareIp ? 'http' : 'https'}://$value';
    }

    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return '${uri.scheme}://${uri.authority}';
  }

  static String get url => defaultUrl;

  /// [url] сохранён только для обратной совместимости и игнорируется.
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
