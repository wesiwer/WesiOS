import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Настройки проекта Firebase, нужные для REST.
///
/// `apiKey` **не секрет**. Это официальная позиция Google: ключ
/// идентифицирует проект, но ничего не разрешает — он лежит открыто в любом
/// веб-приложении на Firebase. Доступ определяют вход и правила Firestore,
/// а не скрытие ключа. Поэтому он спокойно зашит в сборку, и первый запуск
/// не требует от человека вообще ничего.
class FirebaseProject {
  /// Взято из `android/app/google-services.json` — того же проекта, к
  /// которому уже подключено Android-приложение. Отдельный проект заводить
  /// незачем, а два разных означали бы два места, где лежат ключи.
  static const String defaultApiKey =
      'AIzaSyAlBRd6z6V0t16wgcOd68o2CXA0n8jtE_k';
  static const String defaultProjectId = 'wesios-d7b07';

  static const String _box = 'wesios_settings';
  static const String _apiKeyKey = 'firebase_rest_api_key';
  static const String _projectKey = 'firebase_rest_project_id';

  static dynamic _get(String key) {
    try {
      return Hive.box(_box).get(key);
    } catch (_) {
      return null;
    }
  }

  /// Значение из настроек перекрывает зашитое — сменить проект можно без
  /// пересборки.
  static String get apiKey {
    final v = _get(_apiKeyKey);
    return (v is String && v.trim().isNotEmpty) ? v.trim() : defaultApiKey;
  }

  static String get projectId {
    final v = _get(_projectKey);
    return (v is String && v.trim().isNotEmpty) ? v.trim() : defaultProjectId;
  }

  static bool get isConfigured => apiKey.isNotEmpty && projectId.isNotEmpty;

  static Future<void> configure({
    required String apiKey,
    required String projectId,
  }) async {
    try {
      final box = Hive.box(_box);
      await box.put(_apiKeyKey, apiKey.trim());
      await box.put(_projectKey, projectId.trim());
    } catch (_) {/* настройки недоступны — не критично */}
  }
}

/// Кто вошёл в Firebase.
class FirebaseSession {
  final String idToken;
  final String refreshToken;
  final String uid;
  final String email;
  final DateTime expiresAt;

  const FirebaseSession({
    required this.idToken,
    required this.refreshToken,
    required this.uid,
    required this.email,
    required this.expiresAt,
  });

  /// Минута запаса: токен, истекающий посреди запроса, — то же самое, что
  /// истёкший.
  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 1)));

  Map<String, dynamic> toJson() => {
        'idToken': idToken,
        'refreshToken': refreshToken,
        'uid': uid,
        'email': email,
        'expiresAt': expiresAt.toIso8601String(),
      };

  static FirebaseSession? fromJson(Map<String, dynamic> json) {
    final expires = DateTime.tryParse(json['expiresAt'] as String? ?? '');
    final idToken = json['idToken'];
    final refresh = json['refreshToken'];
    final uid = json['uid'];
    if (expires == null ||
        idToken is! String ||
        refresh is! String ||
        uid is! String) {
      return null;
    }
    return FirebaseSession(
      idToken: idToken,
      refreshToken: refresh,
      uid: uid,
      email: json['email'] as String? ?? '',
      expiresAt: expires,
    );
  }
}

/// Что пошло не так при обращении к Firebase.
class FirebaseFailure {
  final String code;
  final String message;

  const FirebaseFailure(this.code, this.message);

  /// Человеческая формулировка. Коды Firebase вроде INVALID_LOGIN_CREDENTIALS
  /// показывать пользователю бессмысленно.
  String describe({bool russian = true}) {
    if (!russian) return message;
    return switch (code) {
      'EMAIL_NOT_FOUND' ||
      'INVALID_PASSWORD' ||
      'INVALID_LOGIN_CREDENTIALS' =>
        'Неверная почта или пароль',
      'USER_DISABLED' => 'Учётная запись отключена',
      'TOO_MANY_ATTEMPTS_TRY_LATER' =>
        'Слишком много попыток, попробуйте позже',
      'PERMISSION_DENIED' =>
        'Доступ к ключам не разрешён для этой учётной записи',
      'NOT_CONFIGURED' => 'Проект Firebase не настроен',
      'NETWORK' => 'Нет связи с Firebase',
      _ => message,
    };
  }
}

/// Вход в Firebase и чтение Firestore через REST.
///
/// **Почему REST, а не плагины FlutterFire.** `cloud_firestore` не даёт
/// надёжной поддержки Windows, а Windows здесь — основная платформа. REST
/// работает одинаково везде, не требует `google-services.json` и
/// платформенных каналов. Правила Firestore применяются к REST точно так же:
/// проверка всё равно происходит у Google, а не в приложении.
class FirebaseRestService {
  static const String _box = 'wesios_settings';
  static const String _sessionKey = 'firebase_session';

  static const String _authHost = 'identitytoolkit.googleapis.com';
  static const String _tokenHost = 'securetoken.googleapis.com';
  static const String _firestoreHost = 'firestore.googleapis.com';

  /// Меняется при входе и выходе.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static FirebaseSession? _session;

  static FirebaseSession? get session {
    if (_session != null) return _session;
    try {
      final raw = Hive.box(_box).get(_sessionKey);
      if (raw is! String) return null;
      _session = FirebaseSession.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
      return _session;
    } catch (_) {
      return null;
    }
  }

  static bool get isSignedIn => session != null;

  static Future<void> _saveSession(FirebaseSession s) async {
    _session = s;
    try {
      await Hive.box(_box).put(_sessionKey, jsonEncode(s.toJson()));
    } catch (_) {/* настройки недоступны — сессия живёт до перезапуска */}
    revision.value++;
  }

  static Future<void> signOut() async {
    _session = null;
    try {
      await Hive.box(_box).delete(_sessionKey);
    } catch (_) {/* нечего удалять */}
    revision.value++;
  }

  /// Забыть вход при закрытии программы — «запомнить меня» снята.
  ///
  /// Стирается только копия на диске; сессия в памяти остаётся, и до выхода
  /// из программы всё работает. Выкидывать человека из уже выполненного
  /// входа было бы странным прочтением «не запоминай».
  static Future<void> forgetOnExit() async {
    try {
      await Hive.box(_box).delete(_sessionKey);
    } catch (_) {/* нечего удалять */}
  }

  /// Вход по почте и паролю.
  ///
  /// Учётная запись заводится в консоли Firebase (Authentication → Users).
  /// Регистрации из приложения намеренно нет: иначе любой, у кого есть
  /// сборка, завёл бы себе аккаунт в вашем проекте.
  static Future<FirebaseFailure?> signIn(String email, String password) async {
    if (!FirebaseProject.isConfigured) {
      return const FirebaseFailure('NOT_CONFIGURED', 'Проект не настроен');
    }
    final json = await _post(
      Uri.https(_authHost, '/v1/accounts:signInWithPassword',
          {'key': FirebaseProject.apiKey}),
      {
        'email': email,
        'password': password,
        'returnSecureToken': true,
      },
    );
    if (json == null) {
      return const FirebaseFailure('NETWORK', 'Нет связи с Firebase');
    }
    final error = json['error'];
    if (error is Map) {
      return FirebaseFailure(
        error['message']?.toString().split(' ').first ?? 'UNKNOWN',
        error['message']?.toString() ?? 'Неизвестная ошибка',
      );
    }

    final expiresIn = int.tryParse('${json['expiresIn']}') ?? 3600;
    await _saveSession(FirebaseSession(
      idToken: '${json['idToken']}',
      refreshToken: '${json['refreshToken']}',
      uid: '${json['localId']}',
      email: '${json['email']}',
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    ));
    return null;
  }

  /// Продлевает сессию. Токен Firebase живёт час — без этого пришлось бы
  /// вводить пароль по несколько раз за день.
  static Future<bool> _refresh() async {
    final current = session;
    if (current == null) return false;
    final json = await _postForm(
      Uri.https(_tokenHost, '/v1/token', {'key': FirebaseProject.apiKey}),
      {
        'grant_type': 'refresh_token',
        'refresh_token': current.refreshToken,
      },
    );
    final idToken = json?['id_token'];
    if (idToken is! String) return false;

    final expiresIn = int.tryParse('${json!['expires_in']}') ?? 3600;
    await _saveSession(FirebaseSession(
      idToken: idToken,
      refreshToken: '${json['refresh_token'] ?? current.refreshToken}',
      uid: current.uid,
      email: current.email,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    ));
    return true;
  }

  /// Годный к работе токен: при необходимости молча продлевает.
  static Future<String?> validToken() async {
    final current = session;
    if (current == null) return null;
    if (!current.isExpired) return current.idToken;
    if (await _refresh()) return session?.idToken;
    return null;
  }

  // ---------------------------------------------------------------- Firestore

  static Uri _docUri(String path) => Uri.https(
        _firestoreHost,
        '/v1/projects/${FirebaseProject.projectId}/databases/(default)/documents/$path',
      );

  /// Есть ли у текущего аккаунта право видеть ключи.
  ///
  /// Спрашивается у Firestore, а не решается в приложении: клиентская
  /// проверка убрала бы кнопку с экрана, но не закрыла бы данные.
  static Future<bool> isAdmin() async {
    final current = session;
    if (current == null) return false;
    final doc = await getDocument('admins/${current.uid}');
    return doc != null;
  }

  /// Читает документ. null — нет документа, нет прав или нет связи.
  static Future<Map<String, String>?> getDocument(String path) async {
    final token = await validToken();
    if (token == null) return null;
    final json = await _get(_docUri(path), token);
    if (json == null || json['fields'] is! Map) return null;
    return _decodeFields(json['fields'] as Map);
  }

  /// Перезаписывает документ целиком.
  static Future<FirebaseFailure?> setDocument(
    String path,
    Map<String, String> values,
  ) async {
    final token = await validToken();
    if (token == null) {
      return const FirebaseFailure('NETWORK', 'Сессия недействительна');
    }
    final json = await _patch(
      _docUri(path),
      token,
      {
        'fields': {
          for (final e in values.entries)
            e.key: {'stringValue': e.value},
        },
      },
    );
    if (json == null) {
      return const FirebaseFailure('NETWORK', 'Нет связи с Firebase');
    }
    final error = json['error'];
    if (error is Map) {
      return FirebaseFailure(
        '${error['status'] ?? 'UNKNOWN'}',
        '${error['message'] ?? 'Неизвестная ошибка'}',
      );
    }
    return null;
  }

  /// Firestore возвращает значения в обёртках по типам. Нас интересуют
  /// только строки: ключи и токены — всегда строки, а тащить сюда полный
  /// разбор типов значило бы писать половину клиента Firestore.
  static Map<String, String> _decodeFields(Map fields) {
    final out = <String, String>{};
    fields.forEach((key, value) {
      if (value is Map && value['stringValue'] is String) {
        out['$key'] = value['stringValue'] as String;
      }
    });
    return out;
  }

  // ------------------------------------------------------------------- HTTP

  static Future<Map<String, dynamic>?> _get(Uri uri, String token) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return null;
      final json = jsonDecode(body);
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>?> _patch(
    Uri uri,
    String token,
    Map<String, dynamic> body,
  ) async {
    final client = HttpClient();
    try {
      final req = await client.patchUrl(uri);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      final json = jsonDecode(text);
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>?> _post(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      final json = jsonDecode(text);
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>?> _postForm(
    Uri uri,
    Map<String, String> fields,
  ) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.write(fields.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&'));
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      final json = jsonDecode(text);
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
