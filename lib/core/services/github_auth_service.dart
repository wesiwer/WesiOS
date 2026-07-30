import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Что вернул GitHub на запрос кода устройства.
class DeviceCode {
  /// Код, который человек вводит в браузере. Восемь символов через дефис.
  final String userCode;

  /// Куда идти вводить — обычно https://github.com/login/device
  final String verificationUri;

  /// Внутренний код, которым приложение опрашивает GitHub. Не показывается.
  final String deviceCode;

  /// Как часто можно опрашивать, секунды.
  final int interval;

  /// Сколько живёт код, секунды.
  final int expiresIn;

  const DeviceCode({
    required this.userCode,
    required this.verificationUri,
    required this.deviceCode,
    required this.interval,
    required this.expiresIn,
  });
}

/// Чем закончилось ожидание подтверждения.
enum DeviceAuthOutcome {
  /// Токен получен и сохранён.
  success,

  /// Пользователь отказал в доступе.
  denied,

  /// Код протух — надо начинать заново.
  expired,

  /// Сеть или неожиданный ответ.
  failed,
}

/// Вход в GitHub по Device Flow.
///
/// Зачем вообще: релизы WesiOS лежат в приватном репозитории, и анонимная
/// ссылка на них отдаёт 404 всем, включая само приложение. Значит запросу
/// нужен токен.
///
/// **Почему именно device flow, а не «вставьте сюда токен».** Личный токен
/// пришлось бы создавать руками, копировать и следить за сроком. Здесь
/// приложение просит код само, человек один раз подтверждает вход в браузере,
/// и дальше всё происходит без него.
///
/// **Почему client_id лежит открыто в коде.** Device flow — публичный клиент:
/// в нём нет client_secret именно потому, что клиент невозможно сохранить в
/// тайне. Всё, что даёт client_id, — это право *попросить* пользователя войти;
/// без подтверждения в браузере он бесполезен. Зашивать в сборку сам токен
/// было бы наоборот дырой: APK распаковывается за минуту.
class GitHubAuthService {
  static const String _box = 'wesios_settings';
  static const String _tokenKey = 'github_token';
  static const String _refreshKey = 'github_refresh_token';
  static const String _expiresKey = 'github_token_expires';
  static const String _clientIdKey = 'github_client_id';
  static const String _loginKey = 'github_login';

  /// client_id зарегистрированного OAuth-приложения WesiOS.
  ///
  /// Не секрет: в device flow клиент публичный по устройству протокола.
  ///
  /// Значение из настроек имеет приоритет над этим — чтобы сменить
  /// приложение GitHub можно было без пересборки.
  static const String defaultClientId = 'Ov23liYUSXiSuiA1V4wR';

  /// Права, которые запрашиваем у OAuth-приложения.
  ///
  /// `public_repo` не подойдёт — репозиторий приватный. У классического
  /// OAuth-приложения нет более узкой области, чем `repo`; если это
  /// неприемлемо, GitHub App ограничивается одним репозиторием и правом
  /// только на чтение содержимого (тогда scope не отправляется вовсе).
  static const String scope = 'repo';

  static const String _deviceCodeUrl = 'https://github.com/login/device/code';
  static const String _tokenUrl =
      'https://github.com/login/oauth/access_token';

  /// Меняется при входе и выходе — экраны перечитывают статус.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static dynamic _get(String key) {
    try {
      return Hive.box(_box).get(key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _put(String key, dynamic value) async {
    try {
      await Hive.box(_box).put(key, value);
    } catch (_) {/* настройки недоступны — не критично */}
  }

  static String get clientId {
    final stored = _get(_clientIdKey);
    if (stored is String && stored.trim().isNotEmpty) return stored.trim();
    return defaultClientId;
  }

  static bool get isConfigured => clientId.isNotEmpty;

  static Future<void> setClientId(String value) async {
    await _put(_clientIdKey, value.trim());
    revision.value++;
  }

  /// Имя аккаунта, которым вошли. Нужно только чтобы показать в настройках,
  /// кто именно авторизован.
  static String? get login {
    final v = _get(_loginKey);
    return v is String && v.isNotEmpty ? v : null;
  }

  static String? get token {
    final v = _get(_tokenKey);
    if (v is! String || v.isEmpty) return null;
    return v;
  }

  static bool get isSignedIn => token != null;

  /// Срок жизни токена. У классического OAuth-приложения его нет вовсе —
  /// тогда null и обновлять нечего.
  static DateTime? get expiresAt {
    final v = _get(_expiresKey);
    if (v is! String) return null;
    return DateTime.tryParse(v);
  }

  static bool get _isExpired {
    final at = expiresAt;
    if (at == null) return false;
    // Минута запаса: токен, который протухнет посреди скачивания, — то же
    // самое, что протухший.
    return DateTime.now().isAfter(at.subtract(const Duration(minutes: 1)));
  }

  static Future<void> signOut() async {
    for (final key in [_tokenKey, _refreshKey, _expiresKey, _loginKey]) {
      try {
        await Hive.box(_box).delete(key);
      } catch (_) {/* нечего удалять */}
    }
    revision.value++;
  }

  // ------------------------------------------------------------------ поток

  /// Шаг первый: просим у GitHub код для человека.
  static Future<DeviceCode?> requestDeviceCode() async {
    if (!isConfigured) return null;
    final body = {
      'client_id': clientId,
      if (scope.isNotEmpty) 'scope': scope,
    };
    final json = await _postForm(_deviceCodeUrl, body);
    if (json == null) return null;

    final userCode = json['user_code'];
    final deviceCode = json['device_code'];
    final uri = json['verification_uri'];
    if (userCode is! String || deviceCode is! String || uri is! String) {
      return null;
    }
    return DeviceCode(
      userCode: userCode,
      verificationUri: uri,
      deviceCode: deviceCode,
      interval: (json['interval'] as num?)?.toInt() ?? 5,
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 900,
    );
  }

  /// Шаг второй: ждём, пока человек подтвердит вход в браузере.
  ///
  /// Опрашивать чаще, чем сказал GitHub, нельзя: он отвечает `slow_down` и
  /// увеличивает интервал, а при упорстве временно блокирует. Поэтому пауза
  /// растёт по его команде, а не по нашему усмотрению.
  static Future<DeviceAuthOutcome> pollForToken(
    DeviceCode code, {
    bool Function()? cancelled,
  }) async {
    var interval = code.interval;
    final deadline = DateTime.now().add(Duration(seconds: code.expiresIn));

    while (DateTime.now().isBefore(deadline)) {
      if (cancelled?.call() == true) return DeviceAuthOutcome.failed;
      await Future<void>.delayed(Duration(seconds: interval));
      if (cancelled?.call() == true) return DeviceAuthOutcome.failed;

      final json = await _postForm(_tokenUrl, {
        'client_id': clientId,
        'device_code': code.deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      });
      if (json == null) continue;

      final error = json['error'];
      if (error == 'authorization_pending') continue;
      if (error == 'slow_down') {
        interval = (json['interval'] as num?)?.toInt() ?? interval + 5;
        continue;
      }
      if (error == 'access_denied') return DeviceAuthOutcome.denied;
      if (error == 'expired_token') return DeviceAuthOutcome.expired;
      if (error is String) return DeviceAuthOutcome.failed;

      final accessToken = json['access_token'];
      if (accessToken is! String || accessToken.isEmpty) continue;

      await _put(_tokenKey, accessToken);
      final refresh = json['refresh_token'];
      if (refresh is String && refresh.isNotEmpty) {
        await _put(_refreshKey, refresh);
      }
      final expiresIn = (json['expires_in'] as num?)?.toInt();
      await _put(
        _expiresKey,
        expiresIn == null
            ? null
            : DateTime.now()
                .add(Duration(seconds: expiresIn))
                .toIso8601String(),
      );
      await _fetchLogin();
      revision.value++;
      return DeviceAuthOutcome.success;
    }
    return DeviceAuthOutcome.expired;
  }

  /// Обновляет токен по refresh_token. У GitHub App токен живёт восемь часов,
  /// поэтому без этого пришлось бы входить заново по три раза на дню.
  static Future<bool> refresh() async {
    final refreshToken = _get(_refreshKey);
    if (refreshToken is! String || refreshToken.isEmpty) return false;

    final json = await _postForm(_tokenUrl, {
      'client_id': clientId,
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
    });
    final accessToken = json?['access_token'];
    if (accessToken is! String || accessToken.isEmpty) return false;

    await _put(_tokenKey, accessToken);
    final newRefresh = json!['refresh_token'];
    if (newRefresh is String && newRefresh.isNotEmpty) {
      await _put(_refreshKey, newRefresh);
    }
    final expiresIn = (json['expires_in'] as num?)?.toInt();
    await _put(
      _expiresKey,
      expiresIn == null
          ? null
          : DateTime.now().add(Duration(seconds: expiresIn)).toIso8601String(),
    );
    revision.value++;
    return true;
  }

  /// Готовый к работе токен: при необходимости молча продлевает.
  static Future<String?> validToken() async {
    final current = token;
    if (current == null) return null;
    if (!_isExpired) return current;
    if (await refresh()) return token;
    return null;
  }

  /// Заголовки для запросов к API GitHub.
  ///
  /// Пусто, если входа нет: вызывающий код тогда сам решает, что делать, —
  /// молча промолчать при фоновой проверке или сказать вслух при явной.
  static Future<Map<String, String>> authHeaders() async {
    final t = await validToken();
    if (t == null) return const {};
    return {
      'Authorization': 'Bearer $t',
      'X-GitHub-Api-Version': '2022-11-28',
    };
  }

  static Future<void> _fetchLogin() async {
    final t = token;
    if (t == null) return;
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse('https://api.github.com/user'));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $t');
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'WesiOS');
      final res = await req.close();
      if (res.statusCode != 200) return;
      final json = jsonDecode(await res.transform(utf8.decoder).join());
      if (json is Map && json['login'] is String) {
        await _put(_loginKey, json['login']);
      }
    } catch (_) {
      // Имя аккаунта — украшение, его отсутствие ничего не ломает.
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>?> _postForm(
    String url,
    Map<String, String> fields,
  ) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse(url));
      req.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      // Без этого заголовка GitHub отвечает form-urlencoded, а не JSON.
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.userAgentHeader, 'WesiOS');
      req.write(fields.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
