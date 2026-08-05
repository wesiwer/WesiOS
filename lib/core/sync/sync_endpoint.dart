import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Куда синхронизироваться и кем.
///
/// WesiOS — корпоративная система с уже развёрнутой инфраструктурой, поэтому
/// обычному пользователю больше не нужно вводить адрес вручную. Клиент всегда
/// использует защищённый основной сервер Wesi Inc. Сохранённый адрес старых
/// установок читается только для совместимости, но новая установка сразу
/// работает с [defaultUrl].
class SyncEndpoint {
  static const String _box = 'wesios_settings';
  static const String _urlKey = 'sync_server_url';
  static const String _loginKey = 'sync_server_login';
  static const String _enabledKey = 'sync_enabled';
  static const String _sessionKey = 'sync_session';
  static const String _lastRunKey = 'sync_last_run';
  static const String _seededKey = 'sync_seeded_at';

  /// Единый российский сервер аккаунтов, портала и синхронизации WesiOS.
  static const String defaultUrl = 'https://api.wesi-inc.ru';

  /// Меняется при входе, выходе и смене состояния — экраны перечитывают.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Box<dynamic>? _open() {
    try {
      return Hive.box<dynamic>(_box);
    } catch (_) {
      return null;
    }
  }

  /// Адрес для отображения и запросов. Пустого состояния больше нет.
  static String get rawUrl {
    final stored = '${_open()?.get(_urlKey) ?? ''}'.trim();
    return normalize(stored) ?? defaultUrl;
  }

  static String get login => '${_open()?.get(_loginKey) ?? ''}';

  static bool get enabled => _open()?.get(_enabledKey) == true;

  static bool get isConfigured => true;

  /// Нормализация оставлена для миграции старых установок и тестов.
  static String? normalize(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty) return null;

    if (!s.contains('://')) {
      final host = s.split(':').first;
      final isBareIp = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host);
      s = '${isBareIp ? 'http' : 'https'}://$s';
    }

    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return '${uri.scheme}://${uri.authority}';
  }

  /// Nullable-тип сохранён для совместимости существующих транспортов, но
  /// фактически getter всегда возвращает [defaultUrl] или его мигрированную
  /// копию.
  static String? get url => normalize(rawUrl) ?? defaultUrl;

  static Future<void> configure({String? url, String? login}) async {
    final box = _open();
    if (box == null) return;
    // Адрес фиксирован продуктом. Старый параметр принимается ради
    // совместимости вызовов, но сохраняем только проверенный Wesi endpoint.
    if (url != null) await box.put(_urlKey, defaultUrl);
    if (login != null) await box.put(_loginKey, login.trim());
    revision.value++;
  }

  /// Одноразовая миграция старых установок на основной сервер.
  static Future<void> ensureDefaultServer() async {
    final box = _open();
    if (box == null) return;
    if (normalize('${box.get(_urlKey) ?? ''}') != defaultUrl) {
      await box.put(_urlKey, defaultUrl);
      revision.value++;
    }
  }

  static Future<void> setEnabled(bool on) async {
    await _open()?.put(_enabledKey, on);
    revision.value++;
  }

  // ------------------------------------------------------------- сессия

  /// Токен и срок его жизни. Пароль после входа не сохраняется.
  static Map<String, dynamic>? get session {
    final raw = _open()?.get(_sessionKey);
    if (raw is! String) return null;
    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> ? json : null;
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
