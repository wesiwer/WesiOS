import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/sync/sync_endpoint.dart';

/// Ответ сервера на выполненную команду.
class RemoteShellResult {
  final bool ok;
  final int exitCode;
  final String output;
  final bool timedOut;
  final bool truncated;
  final int durationMs;

  /// Заполнено, когда команда не дошла до выполнения: нет сессии, нет связи,
  /// сервер отказал. Это не то же самое, что команда с ненулевым кодом.
  final String error;

  const RemoteShellResult({
    required this.ok,
    this.exitCode = -1,
    this.output = '',
    this.timedOut = false,
    this.truncated = false,
    this.durationMs = 0,
    this.error = '',
  });

  const RemoteShellResult.failure(this.error)
      : ok = false,
        exitCode = -1,
        output = '',
        timedOut = false,
        truncated = false,
        durationMs = 0;

  /// Команда дошла до сервера и была выполнена — независимо от кода возврата.
  bool get executed => error.isEmpty;
}

/// Что сервер умеет. Спрашивается один раз перед первой командой.
class RemoteShellCapability {
  final bool available;
  final int defaultTimeoutSeconds;
  final int maxTimeoutSeconds;
  final String reason;

  const RemoteShellCapability({
    required this.available,
    this.defaultTimeoutSeconds = 30,
    this.maxTimeoutSeconds = 300,
    this.reason = '',
  });
}

/// Выполнение команд на сервере WesiOS.
///
/// Ходит тем же путём, что и остальные действия владельца: подтверждённая
/// серверная сессия плюс её идентификатор в заголовке. Ключей SSH в
/// приложении по-прежнему нет и не появляется — команду выполняет сам
/// сервер, а приложение только показывает результат.
class RemoteShellService {
  RemoteShellService._();

  static String get _base => SyncEndpoint.url;

  static RemoteShellCapability? _cached;

  /// Сбросить запомненный ответ о возможностях — например, после смены
  /// адреса сервера или повторного входа.
  static void forgetCapability() => _cached = null;

  static Future<RemoteShellCapability> capability({bool refresh = false}) async {
    if (!refresh && _cached != null) return _cached!;
    final headers = _ownerHeaders();
    if (headers == null) {
      return const RemoteShellCapability(
        available: false,
        reason: 'Нет подтверждённой серверной сессии владельца.',
      );
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request =
          await client.getUrl(Uri.parse('$_base/api/wesi/sysadmin/version'));
      headers.forEach(request.headers.set);
      final response =
          await request.close().timeout(const Duration(seconds: 15));
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode == 404) {
        return _remember(const RemoteShellCapability(
          available: false,
          reason: 'Сервер обновлён не полностью: обработчик команд не найден.',
        ));
      }
      if (response.statusCode != 200) {
        return RemoteShellCapability(
          available: false,
          reason: 'Сервер ответил ${response.statusCode}.',
        );
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return const RemoteShellCapability(
          available: false,
          reason: 'Сервер вернул непонятный ответ.',
        );
      }
      final shell = decoded['shell'] == true;
      return _remember(RemoteShellCapability(
        available: shell,
        defaultTimeoutSeconds: _int(decoded['defaultTimeoutSeconds'], 30),
        maxTimeoutSeconds: _int(decoded['maxTimeoutSeconds'], 300),
        reason: shell
            ? ''
            : 'Сервер не может запускать команды: '
                '${decoded['detail'] ?? 'оболочка недоступна'}',
      ));
    } on TimeoutException {
      return const RemoteShellCapability(
        available: false,
        reason: 'Сервер не ответил вовремя.',
      );
    } on SocketException {
      return const RemoteShellCapability(
        available: false,
        reason: 'Нет связи с сервером WesiOS.',
      );
    } catch (error) {
      return RemoteShellCapability(available: false, reason: '$error');
    } finally {
      client.close(force: true);
    }
  }

  static RemoteShellCapability _remember(RemoteShellCapability value) {
    _cached = value;
    return value;
  }

  static Future<RemoteShellResult> run(
    String command, {
    String? cwd,
    int? timeoutSeconds,
  }) async {
    final trimmed = command.trim();
    if (trimmed.isEmpty) {
      return const RemoteShellResult.failure('Пустая команда.');
    }
    final headers = _ownerHeaders();
    if (headers == null) {
      return const RemoteShellResult.failure(
        'Нет подтверждённой серверной сессии владельца. Войдите заново.',
      );
    }

    // Ждём дольше, чем сам сервер держит команду: иначе при команде, честно
    // работающей 30 секунд, приложение сдалось бы раньше и человек решил бы,
    // что она не выполнилась. Она бы выполнилась — просто без ответа.
    final serverLimit = timeoutSeconds ?? 30;
    final waitFor = Duration(seconds: serverLimit + 15);

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request =
          await client.postUrl(Uri.parse('$_base/api/wesi/sysadmin/exec'));
      request.headers.contentType = ContentType.json;
      headers.forEach(request.headers.set);
      request.write(jsonEncode({
        'command': trimmed,
        if (cwd != null && cwd.trim().isNotEmpty) 'cwd': cwd.trim(),
        'timeoutSeconds': serverLimit,
      }));
      final response = await request.close().timeout(waitFor);
      final text = await utf8.decoder.bind(response).join();

      if (response.statusCode == 401) {
        return const RemoteShellResult.failure(
          'Сессия не подтверждена. Войдите заново.',
        );
      }
      if (response.statusCode == 403) {
        return const RemoteShellResult.failure(
          'Выполнять команды на сервере может только владелец.',
        );
      }
      if (response.statusCode == 404) {
        return const RemoteShellResult.failure(
          'Сервер обновлён не полностью: обработчик команд не найден.',
        );
      }
      if (response.statusCode != 200) {
        return RemoteShellResult.failure(
          'Сервер ответил ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return const RemoteShellResult.failure(
          'Сервер вернул непонятный ответ.',
        );
      }
      final serverError = '${decoded['error'] ?? ''}';
      if (serverError.isNotEmpty) {
        return RemoteShellResult.failure(serverError);
      }
      return RemoteShellResult(
        ok: decoded['ok'] == true,
        exitCode: _int(decoded['exitCode'], -1),
        output: '${decoded['output'] ?? ''}',
        timedOut: decoded['timedOut'] == true,
        truncated: decoded['truncated'] == true,
        durationMs: _int(decoded['durationMs'], 0),
      );
    } on TimeoutException {
      // Важное различие: команда, скорее всего, выполняется до сих пор.
      // Сказать «не выполнилась» было бы неправдой, а по такой неправде
      // человек запустит её второй раз.
      return const RemoteShellResult.failure(
        'Сервер не ответил вовремя. Команда могла выполниться — проверьте '
        'результат отдельно, прежде чем запускать её снова.',
      );
    } on SocketException {
      return const RemoteShellResult.failure('Нет связи с сервером WesiOS.');
    } on HandshakeException {
      return const RemoteShellResult.failure(
        'Не удалось проверить сертификат сервера.',
      );
    } catch (error) {
      return RemoteShellResult.failure('$error');
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, String>? _ownerHeaders() {
    final token = SyncEndpoint.session?['token'];
    final sid = SyncEndpoint.sessionId;
    if (token is! String || token.isEmpty || sid == null) return null;
    return {
      HttpHeaders.authorizationHeader: token,
      'X-WesiOS-Session': sid,
    };
  }

  static int _int(dynamic value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }
}
