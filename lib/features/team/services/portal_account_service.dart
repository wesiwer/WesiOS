import 'dart:convert';
import 'dart:io';

import '../../../core/sync/sync_endpoint.dart';
import '../models/employee_model.dart';

class PortalCredentialResult {
  final bool ok;
  final String message;

  const PortalCredentialResult._(this.ok, this.message);

  const PortalCredentialResult.success([String message = ''])
      : this._(true, message);

  const PortalCredentialResult.failure(String message)
      : this._(false, message);
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

  /// Установить владельцу короткий логин и пароль для сайта и будущего
  /// стартового окна WesiOS. Нужна уже существующая серверная сессия:
  /// неизвестный локальный пользователь не может сам назначить себя
  /// владельцем сервера.
  static Future<PortalCredentialResult> configureCurrentProfile({
    required EmployeeModel employee,
    required String login,
    required String password,
  }) async {
    final session = SyncEndpoint.session;
    final token = session?['token'];
    if (token is! String || token.isEmpty) {
      return const PortalCredentialResult.failure(
        'Сначала войдите в раздел «Синхронизация» своей текущей серверной учётной записью.',
      );
    }

    final normalized = login.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,31}$').hasMatch(normalized)) {
      return const PortalCredentialResult.failure(
        'Логин: 3–32 латинских символа, цифры, точка, дефис или подчёркивание.',
      );
    }
    if (password.length < 8) {
      return const PortalCredentialResult.failure(
        'Пароль должен содержать минимум 8 символов.',
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

      final response = await request.close().timeout(const Duration(seconds: 18));
      final responseText = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        return PortalCredentialResult.failure(
          _messageFrom(responseText,
              fallback: 'Сервер не принял новые данные.'),
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
        return const PortalCredentialResult.failure(
          'Данные сохранены, но контрольный вход не прошёл. Повторите отправку.',
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
  /// локальной карточкой. Для владельца это обновление его текущей auth-
  /// записи, а не создание второго «сотрудника» с тем же логином.
  static Future<bool> provision({
    required EmployeeModel employee,
    required String password,
  }) async {
    if (employee.isOwner) {
      final result = await configureCurrentProfile(
        employee: employee,
        login: employee.login,
        password: password,
      );
      return result.ok;
    }

    final session = SyncEndpoint.session;
    final ownerToken = session?['token'];
    if (ownerToken is! String || ownerToken.isEmpty) return false;

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(
        Uri.parse('$_base/api/wesi/portal/employees/provision'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, ownerToken);
      request.write(jsonEncode({
        'login': employee.login,
        'name': employee.displayName,
        'password': password,
      }));

      final response = await request.close().timeout(const Duration(seconds: 15));
      await response.drain<void>();
      if (response.statusCode != 200 && response.statusCode != 201) {
        return false;
      }

      final auth = await client.postUrl(
        Uri.parse('$_base/api/collections/users/auth-with-password'),
      );
      auth.headers.contentType = ContentType.json;
      auth.write(jsonEncode({
        'identity': '${employee.login.toLowerCase()}@wesi.local',
        'password': password,
      }));
      final authResponse = await auth.close().timeout(const Duration(seconds: 15));
      await authResponse.drain<void>();
      return authResponse.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static String _messageFrom(String raw, {required String fallback}) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['message'] is String) {
        final message = (decoded['message'] as String).trim();
        if (message.isNotEmpty) return message;
      }
    } catch (_) {}
    return fallback;
  }
}
