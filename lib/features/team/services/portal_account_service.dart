import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/security/session_service.dart';
import '../../../core/sync/sync_endpoint.dart';
import '../models/employee_model.dart';
import '../models/team_permissions.dart';

class PortalCredentialResult {
  final bool ok;
  final String message;
  final int? statusCode;

  const PortalCredentialResult._(this.ok, this.message, {this.statusCode});
  const PortalCredentialResult.success([String message = '']) : this._(true, message);
  const PortalCredentialResult.failure(String message, {int? statusCode})
      : this._(false, message, statusCode: statusCode);
}

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
    if (employeeId is! String || employeeId.isEmpty ||
        login is! String || login.isEmpty || permissions is! Map) return null;
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
      permissions: TeamPermissions.fromJson(Map<String, dynamic>.from(permissions)),
    );
  }
}

class PortalChallengeResult {
  final String? challengeId;
  final String? maskedEmail;
  final bool emailSetupRequired;
  final int expiresInSeconds;
  final String? error;
  final int? statusCode;

  const PortalChallengeResult.success({
    required this.challengeId,
    this.maskedEmail,
    this.emailSetupRequired = false,
    required this.expiresInSeconds,
  })  : error = null,
        statusCode = null;

  const PortalChallengeResult.failure(this.error, {this.statusCode})
      : challengeId = null,
        maskedEmail = null,
        emailSetupRequired = false,
        expiresInSeconds = 0;

  bool get ok => challengeId != null && error == null;
}

class PortalLoginResult {
  final PortalAppIdentity? identity;
  final String? error;
  final int? statusCode;

  const PortalLoginResult.success(this.identity) : error = null, statusCode = null;
  const PortalLoginResult.failure(this.error, {this.statusCode}) : identity = null;
  bool get ok => identity != null && error == null;
}

class PortalAccountService {
  const PortalAccountService._();

  static String get _base => SyncEndpoint.url;

  static bool validSecurityEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
          .hasMatch(value.trim().toLowerCase()) &&
      !value.trim().toLowerCase().endsWith('@wesi.local');

  static Future<PortalChallengeResult> beginSignIn({
    required String login,
    required String password,
    String purpose = 'app',
  }) async {
    final entered = login.trim().toLowerCase();
    if (entered.isEmpty || password.isEmpty) {
      return const PortalChallengeResult.failure('Введите логин и пароль.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(Uri.parse('$_base/api/wesi/auth/start-v2'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'login': entered, 'password': password, 'purpose': purpose}));
      final response = await request.close().timeout(const Duration(seconds: 20));
      final text = await utf8.decoder.bind(response).join();
      final decoded = _map(text);
      if (response.statusCode != 200) {
        return PortalChallengeResult.failure(
          messageForResponse(response.statusCode, text,
              fallback: response.statusCode == 401
                  ? 'Неверный логин или пароль.'
                  : 'Не удалось отправить код безопасности.'),
          statusCode: response.statusCode,
        );
      }
      final challengeId = decoded?['challengeId'];
      if (challengeId is! String || challengeId.isEmpty) {
        return const PortalChallengeResult.failure('Сервер не создал проверку входа.');
      }
      final setupRequired = decoded?['emailSetupRequired'] == true;
      final masked = decoded?['maskedEmail'];
      if (!setupRequired && (masked is! String || masked.isEmpty)) {
        return const PortalChallengeResult.failure('Сервер не вернул адрес для кода.');
      }
      return PortalChallengeResult.success(
        challengeId: challengeId,
        maskedEmail: masked is String ? masked : null,
        emailSetupRequired: setupRequired,
        expiresInSeconds: (decoded?['expiresInSeconds'] as num?)?.toInt() ?? 600,
      );
    } on TimeoutException {
      return const PortalChallengeResult.failure('Сервер WesiOS не ответил вовремя. Повторите попытку.');
    } on SocketException {
      return const PortalChallengeResult.failure('Нет связи с сервером WesiOS.');
    } on HandshakeException {
      return const PortalChallengeResult.failure('Не удалось проверить сертификат сервера WesiOS.');
    } catch (_) {
      return const PortalChallengeResult.failure('Не удалось начать вход.');
    } finally {
      client.close(force: true);
    }
  }

  /// First-time owner migration. The password was already validated when the
  /// setup challenge was created. This call sends a code to the proposed
  /// address; the address is committed only after the code succeeds.
  static Future<PortalChallengeResult> setupOwnerEmail({
    required String challengeId,
    required String email,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (!validSecurityEmail(normalized)) {
      return const PortalChallengeResult.failure('Укажите действующую электронную почту.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(Uri.parse('$_base/api/wesi/auth/setup-email'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'challengeId': challengeId, 'email': normalized}));
      final response = await request.close().timeout(const Duration(seconds: 20));
      final text = await utf8.decoder.bind(response).join();
      final decoded = _map(text);
      if (response.statusCode != 200) {
        return PortalChallengeResult.failure(
          messageForResponse(response.statusCode, text,
              fallback: 'Не удалось подтвердить эту почту.'),
          statusCode: response.statusCode,
        );
      }
      final id = decoded?['challengeId'];
      final masked = decoded?['maskedEmail'];
      if (id is! String || masked is! String || id.isEmpty || masked.isEmpty) {
        return const PortalChallengeResult.failure('Сервер не вернул данные отправленного кода.');
      }
      return PortalChallengeResult.success(
        challengeId: id,
        maskedEmail: masked,
        expiresInSeconds: (decoded?['expiresInSeconds'] as num?)?.toInt() ?? 600,
      );
    } on TimeoutException {
      return const PortalChallengeResult.failure('Сервер не ответил вовремя.');
    } on SocketException {
      return const PortalChallengeResult.failure('Нет связи с сервером WesiOS.');
    } catch (_) {
      return const PortalChallengeResult.failure('Не удалось отправить код на эту почту.');
    } finally {
      client.close(force: true);
    }
  }

  static Future<PortalLoginResult> verifySignIn({
    required String challengeId,
    required String code,
    required bool remember,
  }) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      return const PortalLoginResult.failure('Введите шестизначный код.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final device = await SessionService.deviceMetadata();
      final verify = await client.postUrl(Uri.parse('$_base/api/wesi/auth/verify'));
      verify.headers.contentType = ContentType.json;
      verify.write(jsonEncode({
        'challengeId': challengeId,
        'code': code.trim(),
        'remember': remember,
        'device': device,
      }));
      final verifyResponse = await verify.close().timeout(const Duration(seconds: 20));
      final verifyText = await utf8.decoder.bind(verifyResponse).join();
      final verifyJson = _map(verifyText);
      if (verifyResponse.statusCode != 200) {
        return PortalLoginResult.failure(
          messageForResponse(verifyResponse.statusCode, verifyText,
              fallback: 'Неверный или просроченный код.'),
          statusCode: verifyResponse.statusCode,
        );
      }

      final token = verifyJson?['token'];
      final userId = verifyJson?['userId'];
      final sessionId = verifyJson?['sessionId'];
      final expiresAt = DateTime.tryParse('${verifyJson?['expiresAt'] ?? ''}');
      if (token is! String || token.isEmpty || userId is! String || userId.isEmpty ||
          sessionId is! String || sessionId.isEmpty || expiresAt == null) {
        return const PortalLoginResult.failure('Сервер вернул неполный подтверждённый сеанс.');
      }

      final bootstrap = await client.getUrl(Uri.parse('$_base/api/wesi/app/bootstrap'));
      bootstrap.headers.set(HttpHeaders.authorizationHeader, token);
      bootstrap.headers.set('X-WesiOS-Session', sessionId);
      final bootstrapResponse = await bootstrap.close().timeout(const Duration(seconds: 18));
      final bootstrapText = await utf8.decoder.bind(bootstrapResponse).join();
      if (bootstrapResponse.statusCode != 200) {
        return PortalLoginResult.failure(
          messageForResponse(bootstrapResponse.statusCode, bootstrapText,
              fallback: 'Учётная запись не привязана к активному профилю WesiOS.'),
          statusCode: bootstrapResponse.statusCode,
        );
      }
      final bootstrapJson = _map(bootstrapText);
    final verifiedRecord = verifyJson?['record'];
    if (bootstrapJson != null &&
        bootstrapJson['owner'] == true &&
        verifiedRecord is Map) {
      final verifiedEmail = '${verifiedRecord['email'] ?? ''}'.trim().toLowerCase();
      if (validSecurityEmail(verifiedEmail)) {
        bootstrapJson['email'] = verifiedEmail;
      }
    }
    final identity = bootstrapJson == null
        ? null
        : PortalAppIdentity.tryParse(bootstrapJson);
      if (identity == null) {
        return const PortalLoginResult.failure('Сервер не вернул роль и права пользователя.');
      }

      await SyncEndpoint.configure(login: identity.login);
      await SyncEndpoint.saveSession(
        token: token,
        userId: userId,
        sessionId: sessionId,
        expiresAt: expiresAt,
      );
      await SyncEndpoint.setEnabled(true);

      // Idempotent for an already configured owner. In the migration case it
      // commits the email only after the code delivered to it was verified.
      if (identity.isOwner) {
        try {
          final confirm = await client.postUrl(
              Uri.parse('$_base/api/wesi/security/confirm-owner-email'));
          confirm.headers.set(HttpHeaders.authorizationHeader, token);
          confirm.headers.set('X-WesiOS-Session', sessionId);
          final response = await confirm.close().timeout(const Duration(seconds: 10));
          await response.drain<void>();
        } catch (_) {}
      }
      return PortalLoginResult.success(identity);
    } on TimeoutException {
      return const PortalLoginResult.failure('Сервер WesiOS не ответил вовремя. Повторите попытку.');
    } on SocketException {
      return const PortalLoginResult.failure('Нет связи с сервером WesiOS.');
    } on HandshakeException {
      return const PortalLoginResult.failure('Не удалось проверить сертификат сервера WesiOS.');
    } catch (_) {
      return const PortalLoginResult.failure('Не удалось подтвердить вход.');
    } finally {
      client.close(force: true);
    }
  }

  static Future<PortalCredentialResult> configureCurrentProfile({
    required EmployeeModel employee,
    required String login,
    required String password,
  }) async {
    final token = SyncEndpoint.session?['token'];
    final sid = SyncEndpoint.sessionId;
    if (token is! String || token.isEmpty || sid == null) {
      return const PortalCredentialResult.failure('Сначала войдите в WesiOS.', statusCode: 401);
    }
    if (!validSecurityEmail(employee.email)) {
      return const PortalCredentialResult.failure('Сначала укажите действующую электронную почту профиля.');
    }
    final normalized = login.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,31}$').hasMatch(normalized)) {
      return const PortalCredentialResult.failure('Логин: 3–32 латинских символа, цифры, точка, дефис или подчёркивание.');
    }
    if (password.length < 8 || password.length > 128) {
      return const PortalCredentialResult.failure('Пароль должен содержать от 8 до 128 символов.');
    }
    return _postOwner(
      '/api/wesi/portal/profile/credentials',
      {
        'login': normalized,
        'password': password,
        'name': employee.displayName,
        'email': employee.email.trim().toLowerCase(),
      },
      success: 'Данные входа сохранены. При следующем входе потребуется код из почты.',
      fallback: 'Сервер не принял новые данные.',
    );
  }

  static Future<PortalCredentialResult> provisionDetailed({
    required EmployeeModel employee,
    required String password,
  }) async {
    if (!validSecurityEmail(employee.email)) {
      return const PortalCredentialResult.failure('Для сотрудника обязательна действующая электронная почта.');
    }
    if (employee.isOwner) {
      return configureCurrentProfile(employee: employee, login: employee.login, password: password);
    }
    return _postOwner(
      '/api/wesi/portal/employees/provision',
      _employeeAccessBody(employee)..['password'] = password,
      success: 'Учётная запись сотрудника создана. Вход защищён кодом из почты.',
      fallback: 'Сервер не создал учётную запись сотрудника.',
      acceptCreated: true,
    );
  }

  static Future<PortalCredentialResult> updateAccess(EmployeeModel employee) {
    if (!employee.isOwner && !validSecurityEmail(employee.email)) {
      return Future.value(const PortalCredentialResult.failure('Для сотрудника обязательна действующая электронная почта.'));
    }
    return _postOwner(
      '/api/wesi/portal/employees/access',
      _employeeAccessBody(employee),
      fallback: 'Не удалось обновить данные и права сотрудника на сервере.',
    );
  }

  static Future<PortalCredentialResult> revoke(EmployeeModel employee) => _postOwner(
        '/api/wesi/portal/employees/revoke',
        {'login': employee.login.toLowerCase()},
        fallback: 'Не удалось закрыть серверный вход сотрудника.',
      );

  static Future<PortalCredentialResult> _postOwner(
    String path,
    Map<String, dynamic> body, {
    String success = '',
    required String fallback,
    bool acceptCreated = false,
  }) async {
    final token = SyncEndpoint.session?['token'];
    final sid = SyncEndpoint.sessionId;
    if (token is! String || token.isEmpty || sid == null) {
      return const PortalCredentialResult.failure('Нет подтверждённой серверной сессии владельца.', statusCode: 401);
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(Uri.parse('$_base$path'));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, token);
      request.headers.set('X-WesiOS-Session', sid);
      request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 18));
      final text = await utf8.decoder.bind(response).join();
      final ok = response.statusCode == 200 || (acceptCreated && response.statusCode == 201);
      if (!ok) {
        return PortalCredentialResult.failure(
          messageForResponse(response.statusCode, text, fallback: fallback),
          statusCode: response.statusCode,
        );
      }
      return PortalCredentialResult.success(success);
    } on TimeoutException {
      return const PortalCredentialResult.failure('Сервер не ответил вовремя.');
    } on SocketException {
      return const PortalCredentialResult.failure('Нет связи с сервером WesiOS.');
    } on HandshakeException {
      return const PortalCredentialResult.failure('Не удалось проверить сертификат сервера.');
    } catch (_) {
      return PortalCredentialResult.failure(fallback);
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
        'email': employee.email.trim().toLowerCase(),
        'avatarIndex': employee.avatarIndex,
        'createdAt': employee.createdAt.toUtc().toIso8601String(),
        'permissions': employee.permissions.toJson(),
      };

  static Future<bool> provision({required EmployeeModel employee, required String password}) async =>
      (await provisionDetailed(employee: employee, password: password)).ok;

  static String messageForResponse(int statusCode, String raw, {required String fallback}) {
    final extracted = _messageFrom(raw);
    if (extracted != null && !_isGenericServerMessage(extracted)) return extracted;
    return switch (statusCode) {
      400 => fallback,
      401 => 'Сеанс или данные входа недействительны.',
      403 => 'Сервер не подтвердил доступ для этой операции.',
      404 => 'Серверный модуль безопасности не установлен или не обновлён.',
      429 => 'Слишком много попыток. Подождите и повторите.',
      >= 500 => 'Серверный модуль входа временно недоступен.',
      _ => fallback,
    };
  }

  static Map<String, dynamic>? _map(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) { return null; }
  }

  static String? _messageFrom(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final direct = decoded['message'];
        if (direct is String && direct.trim().isNotEmpty) return direct.trim();
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
