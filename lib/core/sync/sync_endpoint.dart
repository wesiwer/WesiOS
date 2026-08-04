import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Куда синхронизироваться и кем.
///
/// Адрес не зашит в сборку намеренно: сервер — ваш, и его адрес может
/// смениться (переезд, домен вместо голого IP) без выпуска новой версии.
class SyncEndpoint {
  static const String _box = 'wesios_settings';
  static const String _urlKey = 'sync_server_url';
  static const String _loginKey = 'sync_server_login';
  static const String _enabledKey = 'sync_enabled';
  static const String _sessionKey = 'sync_session';
  static const String _lastRunKey = 'sync_last_run';
  static const String _seededKey = 'sync_seeded_at';

  /// Меняется при входе, выходе и смене адреса — экраны перечитывают.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Box<dynamic>? _open() {
    try {
      return Hive.box<dynamic>(_box);
    } catch (_) {
      return null;
    }
  }

  static String get rawUrl => '${_open()?.get(_urlKey) ?? ''}';

  static String get login => '${_open()?.get(_loginKey) ?? ''}';

  static bool get enabled => _open()?.get(_enabledKey) == true;

  static bool get isConfigured => normalize(rawUrl) != null;

  /// Приводит то, что человек набрал, к пригодному адресу.
  ///
  /// null — набрано что-то, что адресом не является. Возвращать в этом случае
  /// «как есть» нельзя: запрос уйдёт в никуда, а человек увидит «нет связи» и
  /// будет чинить сервер вместо опечатки.
  ///
  /// Схема по умолчанию — `https://`, кроме голого IP-адреса: у свежего
  /// сервера ещё нет ни домена, ни сертификата, и `https://185.x.x.x` не
  /// ответит никогда. Домен по умолчанию считается уже с сертификатом —
  /// отправлять пароли открытым текстом по умолчанию недопустимо.
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

  static String? get url => normalize(rawUrl);

  static Future<void> configure({String? url, String? login}) async {
    final box = _open();
    if (box == null) return;
    if (url != null) await box.put(_urlKey, url.trim());
    if (login != null) await box.put(_loginKey, login.trim());
    revision.value++;
  }

  static Future<void> setEnabled(bool on) async {
    await _open()?.put(_enabledKey, on);
    revision.value++;
  }

  // ------------------------------------------------------------- сессия

  /// Токен и срок его жизни. Хранится рядом с настройками, как и сессия
  /// Firebase: это не пароль, а пропуск с ограниченным сроком, и потеря его
  /// стоит одного повторного входа.
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

  /// Когда журнал впервые проставил отметки уже существующим записям.
  ///
  /// Нужно ровно один раз за жизнь установки: второй «первый запуск» переписал
  /// бы отметки заново и объявил все местные записи свежими.
  static DateTime? get seededAt {
    final raw = _open()?.get(_seededKey);
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  static Future<void> markSeeded(DateTime at) async =>
      _open()?.put(_seededKey, at.toIso8601String());
}
