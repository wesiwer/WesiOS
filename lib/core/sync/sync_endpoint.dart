import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Куда синхронизироваться и кем.
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

  /// Сессия считается действующей только если есть и PocketBase token, и
  /// отзывной серверный WesiOS session id. Старые однофакторные сессии без
  /// sessionId намеренно перестают работать после security-обновления.
  static bool get isConnected {
    final s = session;
    if (s == null) return false;
    final token = s['token'];
    final userId = s['userId'];
    final sid = s['sessionId'];
    final until = DateTime.tryParse('${s['expiresAt']}');
    return token is String &&
        token.isNotEmpty &&
        userId is String &&
        userId.isNotEmpty &&
        sid is String &&
        sid.isNotEmpty &&
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

  static String? get sessionId {
    final value = session?['sessionId'];
    return value is String && value.isNotEmpty ? value : null;
  }

  static Future<void> saveSession({
    required String token,
    required String userId,
    required String sessionId,
    required DateTime expiresAt,
  }) async {
    await _open()?.put(
      _sessionKey,
      jsonEncode({
        'token': token,
        'userId': userId,
        'sessionId': sessionId,
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
