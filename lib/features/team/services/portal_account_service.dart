import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/sync/sync_endpoint.dart';
import '../models/employee_model.dart';
import '../models/team_permissions.dart';

class PortalCredentialResult {
  final bool ok;
  final String message;
  final int? statusCode;

  const PortalCredentialResult._(
    this.ok,
    this.message, {
    this.statusCode,
  });

  const PortalCredentialResult.success([String message = ''])
      : this._(true, message);

  const PortalCredentialResult.failure(
    String message, {
    int? statusCode,
  }) : this._(false, message, statusCode: statusCode);
}

/// Подтверждённая сервером личность для текущей установки WesiOS.
///
/// Эти поля нельзя строить из локального Hive: на чистой установке Hive пуст,
/// а подмена локальной карточки не должна давать дополнительных прав.
class PortalAppIdentity {
  final String employeeId;
  final String login;
  final String fullName;
  final String nickname;
  final String position;
  final String email;
  final int avatarIndex;
  final DateTime createdAt;
  final bool isOwner;
  final TeamPermissions permissions;

  const PortalAppIdentity({
    required this.employeeId,
    required this.login,
    required this.fullName,
    required this.nickname,
    required this.position,
    required this.email,
    required this.avatarIndex,
    required this.createdAt,
    required this.isOwner,
    required this.permissions,
  });

  static PortalAppIdentity? tryParse(Map<String, dynamic> json) {
    final employeeId = json['employeeId'];
    final login = json['login'];
    final permissions = json['permissions'];
    if (employeeId is! String ||
        employeeId.isEmpty ||
        login is! String ||
        login.isEmpty ||
        permissions is! Map) {
      return null;
    }
    return PortalAppIdentity(
      employeeId: employeeId,
      login: login,
      fullName: '${json['fullName'] ?? ''}',
      nickname: '${json['nickname'] ?? ''}',
      position: '${json['position'] ?? ''}',
      email: '${json['email'] ?? ''}',
      avatarIndex: json['avatarIndex'] is num
          ? (json['avatarIndex'] as num).toInt()
          : int.tryParse('${json['avatarIndex']}') ?? 0,
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      isOwner: json['owner'] == true,
      permissions: TeamPermissions.fromJson(
        Map<String, dynamic>.from(permissions),
      ),
    );
  }
}

class PortalLoginResult {
  final PortalAppIdentity? identity;
  final String? error;
  final int? statusCode;

  const PortalLoginResult.success(this.identity)
      : error = null,
        statusCode = null;

  const PortalLoginResult.failure(this.error, {this.statusCode})
      : identity = null;

  bool get ok => identity != null && error == null;
}

/// Связывает профили WesiOS с auth-записями PocketBase.
///
/// Источник истины для входа теперь один: тот же PocketBase аккаунт работает
/// на сайте и в приложении. Firebase и локальный PBKDF2 больше не решают,
/// кому можно открыть интерфейс.
class PortalAccountService {
  const PortalAccountService._();

  static String get _base => SyncEndpoint.url;

  static String _identityForLogin(String value) {
    final entered = value.trim().toLowerCase();
    return entered.contains('@') ? entered : '$entered@wesi.local';
  }

  /// Вход в само приложение: auth PocketBase -> защищённый bootstrap прав.
  static Future<PortalLoginResult> signIn({
    required String login,
    required String password,
  }) async {
    final entered = login.trim().toLowerCase();
    if (entered.isEmpty || password.isEmpty) {
      return const PortalLoginResult.failure('Введите логин и пароль.');
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final auth = await client.postUrl(
        Uri.parse('$_base/api/collections/users/auth-with-password'),
      );
      auth.headers.contentType = ContentType.json;
      auth.write(jsonEncode({
        'identity': _identityForLogin(entered),
        'password': password,
      }));
      final authResponse = await auth.close().timeout(const Duration(seconds: 18));
      final authText = await utf8.decoder.bind(authResponse).join();
      if (authResponse.statusCode != 200) {
        return const PortalLoginResult.failure(
          'Неверный логин или пароль.',
          statusCode: 401,
        );
      }

      final decoded = jsonDecode(authText);
      if (decoded is! Map ||
          decoded['token'] is! String ||
          decoded['record'] is! Map ||
          (decoded['record'] as Map)['id'] is! String) {
        return const PortalLoginResult.failure(
          'Сервер вернул неполный ответ авторизации.',
        );
      }

      final token = decoded['token'] as String;
      final userId = (decoded['record'] as Map)['id'] as String;

      final bootstrap = await client.getUrl(
        Uri.parse('$_base/api/wesi/app/bootstrap'),
      );
      bootstrap.headers.set(HttpHeaders.authorizationHeader, token);
      final bootstrapResponse =
          await bootstrap.close().timeout(const Duration(seconds: 18));
      final bootstrapText = await utf8.decoder.bind(bootstrapResponse).join();
      if (bootstrapResponse.statusCode != 200) {
        return PortalLoginResult.failure(
          messageForResponse(
            bootstrapResponse.statusCode,
            bootstrapText,
            fallback:
                'Учётная запись существует, но не привязана к сотруднику WesiOS.',
          ),
          statusCode: bootstrapResponse.statusCode,
        );
      }

      final bootstrapJson = jsonDecode(bootstrapText);
      if (bootstrapJson is! Map) {
        return const PortalLoginResult.failure(
          'Сервер вернул непонятные данные профиля.',
        );
      }
      final identity = PortalAppIdentity.tryParse(
        Map<String, dynamic>.from(bootstrapJson),
      );
      if (identity == null) {
        return const PortalLoginResult.failure(
          'Сервер не вернул роль и права пользователя.',
        );
      }

      await SyncEndpoint.configure(login: identity.login);
      await SyncEndpoint.saveSession(
        token: token,
        userId: userId,
        expiresAt: DateTime.now().add(const Duration(days: 13)),
      );
      await SyncEndpoint.setEnabled(true);
      return PortalLoginResult.success(identity);
    } on TimeoutException {
      return const PortalLoginResult.failure(
        'Сервер WesiOS не ответил вовремя. Повторите попытку.',
      );
    } on SocketException {
      return const PortalLoginResult.failure('Нет связи с сервером WesiOS.');
    } on HandshakeException {
      return const PortalLoginResult.failure(
        'Не удалось проверить сертификат сервера WesiOS.',
      );
    } on FormatException {
      return const PortalLoginResult.failure('Сервер вернул непонятный ответ.');
    } catch (_) {
      return const PortalLoginResult.failure('Не удалось выполнить вход.');
    } finally {
      client.close(force: true);
    }
  }

  /// Установить владельцу короткий логин и пароль для сайта и WesiOS.
  static Future<PortalCredentialResult> configureCurrentProfile({
    required EmployeeModel employee,
    required String login,
    required String password,
  }) async {
    final session = SyncEndpoint.session;
    final token = session?['token'];
    if (token is! String || token.isEmpty) {
      return const PortalCredentialResult.failure(
        'Сначала войдите в WesiOS под текущей серверной учётной записью.',
        statusCode: 401,
      );
    }

    final normalized = login.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,31}$').hasMatch(normalized)) {
      return const PortalCredentialResult.failure(
        'Логин: 3–32 латинских символа, цифры, точка, дефис или подчёркивание.',
      );
    }
    if (password.length < 8 || password.length > 128) {
      return const PortalCredentialResult.failure(
        'Пароль должен содержать от 8 до 128 символов.',
      );
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(
        Uri.parse('$_base/api/wesi/portal/profile/credentials'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, token);
      request.write(jsonEncode({
        'login': normalized,
        'password': password,
        'name': employee.displayName,
      }));

      final response = await request.close().timeout(const Duration(seconds: 18));
      final responseText = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        return PortalCredentialResult.failure(
          messageForResponse(
            response.statusCode,
            responseText,
            fallback: 'Сервер не принял новые данные.',
          ),
          statusCode: response.statusCode,
        );
      }

      final auth = await client.postUrl(
        Uri.parse('$_base/api/collections/users/auth-with-password'),
      );
      auth.headers.contentType = ContentType.json;
      auth.write(jsonEncode({
        'identity': '$normalized@wesi.local',
        'password': password,
      }));
      final authResponse = await auth.close().timeout(const Duration(seconds: 18));
      final authText = await utf8.decoder.bind(authResponse).join();
      if (authResponse.statusCode != 200) {
        return PortalCredentialResult.failure(
          messageForResponse(
            authResponse.statusCode,
            authText,
            fallback:
                'Данные сохранены, но контрольный вход не прошёл. Повторите отправку.',
          ),
          statusCode: authResponse.statusCode,
        );
      }

      final decoded = jsonDecode(authText);
      if (decoded is! Map ||
          decoded['token'] is! String ||
          decoded['record'] is! Map ||
          (decoded['record'] as Map)['id'] is! String) {
        return const PortalCredentialResult.failure(
          'Сервер вернул неполный ответ авторизации.',
        );
      }

      await SyncEndpoint.configure(login: normalized);
      await SyncEndpoint.saveSession(
        token: decoded['token'] as String,
        userId: (decoded['record'] as Map)['id'] as String,
        expiresAt: DateTime.now().add(const Duration(days: 13)),
      );
      await SyncEndpoint.setEnabled(true);
      return const PortalCredentialResult.success(
        'Профиль отправлен на сервер и проверен контрольным входом.',
      );
    } on TimeoutException {
      return const PortalCredentialResult.failure(
        'Сервер WesiOS не ответил вовремя. Повторите попытку.',
      );
    } on SocketException {
      return const PortalCredentialResult.failure('Нет связи с сервером WesiOS.');
    } on HandshakeException {
      return const PortalCredentialResult.failure(
        'Не удалось проверить сертификат сервера.',
      );
    } on FormatException {
      return const PortalCredentialResult.failure('Сервер вернул непонятный ответ.');
    } catch (_) {
      return const PortalCredentialResult.failure(
        'Не удалось отправить профиль на сервер.',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Создать или обновить серверный аккаунт сотрудника одновременно с его
  /// локальной карточкой и вернуть понятную причину результата.
  static Future<PortalCredentialResult> provisionDetailed({
    required EmployeeModel employee,
    required String password,
  }) async {
    if (employee.isOwner) {
      return configureCurrentProfile(
        employee: employee,
        login: employee.login,
        password: password,
      );
    }

    final session = SyncEndpoint.session;
    final ownerToken = session?['token'];
    if (ownerToken is! String || ownerToken.isEmpty) {
      return const PortalCredentialResult.failure(
        'Сначала войдите в WesiOS под учётной записью владельца.',
        statusCode: 401,
      );
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(
        Uri.parse('$_base/api/wesi/portal/employees/provision'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, ownerToken);
      request.write(jsonEncode(_employeeAccessBody(employee)
        ..['password'] = password));

      final response = await request.close().timeout(const Duration(seconds: 18));
      final responseText = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200 && response.statusCode != 201) {
        return PortalCredentialResult.failure(
          messageForResponse(
            response.statusCode,
            responseText,
            fallback: 'Сервер не создал учётную запись сотрудника.',
          ),
          statusCode: response.statusCode,
        );
      }

      final auth = await client.postUrl(
        Uri.parse('$_base/api/collections/users/auth-with-password'),
      );
      auth.headers.contentType = ContentType.json;
      auth.write(jsonEncode({
        'identity': '${employee.login.toLowerCase()}@wesi.local',
        'password': password,
      }));
      final authResponse = await auth.close().timeout(const Duration(seconds: 18));
      final authText = await utf8.decoder.bind(authResponse).join();
      if (authResponse.statusCode != 200) {
        return PortalCredentialResult.failure(
          messageForResponse(
            authResponse.statusCode,
            authText,
            fallback:
                'Учётная запись создана, но контрольный вход сотрудника не прошёл.',
          ),
          statusCode: authResponse.statusCode,
        );
      }

      return const PortalCredentialResult.success(
        'Учётная запись сотрудника создана и проверена.',
      );
    } on TimeoutException {
      return const PortalCredentialResult.failure(
        'Сервер WesiOS не ответил вовремя. Активацию можно повторить.',
      );
    } on SocketException {
      return const PortalCredentialResult.failure(
        'Нет связи с сервером WesiOS. Активацию можно повторить.',
      );
    } on HandshakeException {
      return const PortalCredentialResult.failure(
        'Не удалось проверить сертификат сервера.',
      );
    } on FormatException {
      return const PortalCredentialResult.failure('Сервер вернул непонятный ответ.');
    } catch (_) {
      return const PortalCredentialResult.failure(
        'Не удалось активировать сотрудника на сервере.',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Немедленно обновляет серверный снимок прав без смены пароля.
  static Future<PortalCredentialResult> updateAccess(
    EmployeeModel employee,
  ) async {
    final token = SyncEndpoint.session?['token'];
    if (token is! String || token.isEmpty) {
      return const PortalCredentialResult.failure(
        'Нет серверной сессии владельца.',
        statusCode: 401,
      );
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(
        Uri.parse('$_base/api/wesi/portal/employees/access'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, token);
      request.write(jsonEncode(_employeeAccessBody(employee)));
      final response = await request.close().timeout(const Duration(seconds: 18));
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        return PortalCredentialResult.failure(
          messageForResponse(
            response.statusCode,
            text,
            fallback: 'Не удалось обновить права сотрудника на сервере.',
          ),
          statusCode: response.statusCode,
        );
      }
      return const PortalCredentialResult.success();
    } on TimeoutException {
      return const PortalCredentialResult.failure('Сервер не ответил вовремя.');
    } on SocketException {
      return const PortalCredentialResult.failure('Нет связи с сервером WesiOS.');
    } catch (_) {
      return const PortalCredentialResult.failure(
        'Не удалось обновить права сотрудника на сервере.',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Закрывает серверный вход сотруднику при удалении из команды.
  static Future<PortalCredentialResult> revoke(EmployeeModel employee) async {
    final token = SyncEndpoint.session?['token'];
    if (token is! String || token.isEmpty) {
      return const PortalCredentialResult.failure(
        'Нет серверной сессии владельца.',
        statusCode: 401,
      );
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(
        Uri.parse('$_base/api/wesi/portal/employees/revoke'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, token);
      request.write(jsonEncode({'login': employee.login.toLowerCase()}));
      final response = await request.close().timeout(const Duration(seconds: 18));
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        return PortalCredentialResult.failure(
          messageForResponse(
            response.statusCode,
            text,
            fallback: 'Не удалось закрыть серверный вход сотрудника.',
          ),
          statusCode: response.statusCode,
        );
      }
      return const PortalCredentialResult.success();
    } on TimeoutException {
      return const PortalCredentialResult.failure('Сервер не ответил вовремя.');
    } on SocketException {
      return const PortalCredentialResult.failure('Нет связи с сервером WesiOS.');
    } catch (_) {
      return const PortalCredentialResult.failure(
        'Не удалось закрыть серверный вход сотрудника.',
      );
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, dynamic> _employeeAccessBody(EmployeeModel employee) => {
        'employeeId': employee.id,
        'login': employee.login.toLowerCase(),
        'name': employee.displayName,
        'fullName': employee.fullName,
        'nickname': employee.nickname,
        'position': employee.position,
        'email': employee.email,
        'avatarIndex': employee.avatarIndex,
        'createdAt': employee.createdAt.toUtc().toIso8601String(),
        'permissions': employee.permissions.toJson(),
      };

  /// Совместимость со старым кодом, которому достаточно только результата.
  static Future<bool> provision({
    required EmployeeModel employee,
    required String password,
  }) async {
    final result = await provisionDetailed(
      employee: employee,
      password: password,
    );
    return result.ok;
  }

  /// Переводит служебные ответы PocketBase в сообщение, полезное человеку.
  static String messageForResponse(
    int statusCode,
    String raw, {
    required String fallback,
  }) {
    final extracted = _messageFrom(raw);
    if (extracted != null && !_isGenericServerMessage(extracted)) {
      return extracted;
    }

    return switch (statusCode) {
      400 => fallback,
      401 => 'Серверная сессия истекла. Войдите заново.',
      403 => 'Сервер не подтвердил права для этой операции.',
      404 =>
        'Серверный модуль входа не установлен или не обновлён. Повторите после обновления сервера.',
      >= 500 => 'Серверный модуль входа временно недоступен.',
      _ => fallback,
    };
  }

  static String? _messageFrom(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final direct = decoded['message'];
        if (direct is String && direct.trim().isNotEmpty) {
          return direct.trim();
        }
        final data = decoded['data'];
        if (data is Map) {
          for (final value in data.values) {
            if (value is Map && value['message'] is String) {
              final message = (value['message'] as String).trim();
              if (message.isNotEmpty) return message;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static bool _isGenericServerMessage(String message) {
    final normalized = message.trim().toLowerCase();
    return normalized == 'something went wrong while processing your request.' ||
        normalized == 'something went wrong while processing your request' ||
        normalized == 'an error occurred while processing your request.' ||
        normalized == 'an error occurred while processing your request' ||
        normalized == 'failed to process the request.' ||
        normalized == 'failed to process the request';
  }
}
