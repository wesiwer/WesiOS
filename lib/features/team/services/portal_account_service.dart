import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/sync/sync_endpoint.dart';
import '../models/employee_model.dart';

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

/// Связывает локальные профили WesiOS с auth-записями PocketBase.
///
/// Пароль передаётся только по HTTPS в момент создания/изменения и сразу
/// хешируется PocketBase. После каждого изменения выполняется настоящий
/// контрольный вход теми же данными — код 200 от служебного endpoint сам по
/// себе ещё не считается доказательством, что пользователь сможет войти.
class PortalAccountService {
  const PortalAccountService._();

  static String get _base => SyncEndpoint.url;

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
        'Сначала войдите в разделе «Синхронизация» своей текущей серверной учётной записью.',
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

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
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

      final response =
          await request.close().timeout(const Duration(seconds: 18));
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
      final authResponse =
          await auth.close().timeout(const Duration(seconds: 18));
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
      return const PortalCredentialResult.failure(
        'Нет связи с сервером WesiOS.',
      );
    } on HandshakeException {
      return const PortalCredentialResult.failure(
        'Не удалось проверить сертификат сервера.',
      );
    } on FormatException {
      return const PortalCredentialResult.failure(
        'Сервер вернул непонятный ответ.',
      );
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
        'Сначала войдите в синхронизацию под учётной записью владельца.',
        statusCode: 401,
      );
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(
        Uri.parse('$_base/api/wesi/portal/employees/provision'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, ownerToken);
      request.write(jsonEncode({
        'login': employee.login.toLowerCase(),
        'name': employee.displayName,
        'password': password,
      }));

      final response =
          await request.close().timeout(const Duration(seconds: 18));
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
      final authResponse =
          await auth.close().timeout(const Duration(seconds: 18));
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
      return const PortalCredentialResult.failure(
        'Сервер вернул непонятный ответ.',
      );
    } catch (_) {
      return const PortalCredentialResult.failure(
        'Не удалось активировать сотрудника на сервере.',
      );
    } finally {
      client.close(force: true);
    }
  }

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
  /// Оставлено публичным, чтобы точное поведение можно было проверять тестом.
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
      401 => 'Серверная сессия истекла. Войдите в синхронизацию заново.',
      403 => 'Сервер не подтвердил права владельца.',
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
