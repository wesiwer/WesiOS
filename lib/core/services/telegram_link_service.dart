import 'dart:convert';
import 'dart:io';

import '../sync/sync_endpoint.dart';
import '../../features/organizations/services/organization_context.dart';

class TelegramLinkTicket {
  const TelegramLinkTicket({
    required this.code,
    required this.deepLink,
    required this.botUsername,
    required this.expiresAt,
    required this.activeOrganizationId,
  });

  final String code;
  final Uri deepLink;
  final String botUsername;
  final DateTime expiresAt;
  final String activeOrganizationId;
}

class TelegramNotificationPrefs {
  const TelegramNotificationPrefs({
    this.risk = true,
    this.overdue = true,
    this.quietFromHour = 23,
    this.quietToHour = 8,
    this.timezoneOffsetMinutes = 0,
  });

  final bool risk;
  final bool overdue;
  final int quietFromHour;
  final int quietToHour;
  final int timezoneOffsetMinutes;

  factory TelegramNotificationPrefs.fromJson(Map<String, dynamic>? json) {
    final source = json ?? const <String, dynamic>{};
    return TelegramNotificationPrefs(
      risk: source['risk'] != false,
      overdue: source['overdue'] != false,
      quietFromHour: _hour(source['quietFromHour'], 23),
      quietToHour: _hour(source['quietToHour'], 8),
      timezoneOffsetMinutes: _offset(source['timezoneOffsetMinutes']),
    );
  }

  static int _hour(Object? value, int fallback) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    if (parsed == null) return fallback;
    return parsed.clamp(0, 23);
  }

  static int _offset(Object? value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return (parsed ?? 0).clamp(-840, 840);
  }
}

class TelegramLinkStatus {
  const TelegramLinkStatus({
    required this.linked,
    this.telegramUsername = '',
    this.telegramFirstName = '',
    this.linkedAt,
    this.activeOrganizationId = '',
    this.activeOrganizationName = '',
    this.prefs = const TelegramNotificationPrefs(),
  });

  final bool linked;
  final String telegramUsername;
  final String telegramFirstName;
  final DateTime? linkedAt;
  final String activeOrganizationId;
  final String activeOrganizationName;
  final TelegramNotificationPrefs prefs;

  factory TelegramLinkStatus.fromJson(Map<String, dynamic> json) =>
      TelegramLinkStatus(
        linked: json['linked'] == true,
        telegramUsername: '${json['telegramUsername'] ?? ''}',
        telegramFirstName: '${json['telegramFirstName'] ?? ''}',
        linkedAt: DateTime.tryParse('${json['linkedAt'] ?? ''}'),
        activeOrganizationId: '${json['activeOrganizationId'] ?? ''}',
        activeOrganizationName: '${json['activeOrganizationName'] ?? ''}',
        prefs: TelegramNotificationPrefs.fromJson(
          json['notificationPrefs'] is Map
              ? Map<String, dynamic>.from(json['notificationPrefs'] as Map)
              : null,
        ),
      );
}

class TelegramLinkResult<T> {
  const TelegramLinkResult.ok(this.value)
      : errorCode = null,
        message = null;

  const TelegramLinkResult.fail(this.errorCode, this.message) : value = null;

  final T? value;
  final String? errorCode;
  final String? message;

  bool get ok => errorCode == null;
}

class TelegramLinkService {
  TelegramLinkService._();

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 20);

  static Future<TelegramLinkResult<TelegramLinkStatus>> status() async {
    final response = await _send('GET', '/api/wesi/telegram/status');
    if (!response.ok) {
      return TelegramLinkResult.fail(response.code, response.message);
    }
    return TelegramLinkResult.ok(
      TelegramLinkStatus.fromJson(response.json!),
    );
  }

  static Future<TelegramLinkResult<TelegramLinkTicket>> createLink() async {
    final response = await _send(
      'POST',
      '/api/wesi/telegram/link/create',
      body: {
        'activeOrganizationId': OrganizationContext.currentOrganizationId,
        'timezoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      },
    );
    if (!response.ok) {
      return TelegramLinkResult.fail(response.code, response.message);
    }
    final json = response.json!;
    final deepLink = Uri.tryParse('${json['deepLink'] ?? ''}');
    final expiresAt = DateTime.tryParse('${json['expiresAt'] ?? ''}');
    final code = '${json['code'] ?? ''}';
    if (deepLink == null || expiresAt == null || code.isEmpty) {
      return const TelegramLinkResult.fail(
        'INVALID_RESPONSE',
        'Сервер вернул некорректную привязку Telegram',
      );
    }
    return TelegramLinkResult.ok(
      TelegramLinkTicket(
        code: code,
        deepLink: deepLink,
        botUsername: '${json['botUsername'] ?? 'WesiOSBot'}',
        expiresAt: expiresAt,
        activeOrganizationId: '${json['activeOrganizationId'] ?? ''}',
      ),
    );
  }

  static Future<TelegramLinkResult<TelegramLinkStatus>> revoke() async {
    final response = await _send('POST', '/api/wesi/telegram/revoke');
    if (!response.ok) {
      return TelegramLinkResult.fail(response.code, response.message);
    }
    return const TelegramLinkResult.ok(TelegramLinkStatus(linked: false));
  }

  static Future<TelegramLinkResult<void>> syncOrganization() async {
    final response = await _send(
      'POST',
      '/api/wesi/telegram/context',
      body: {'activeOrganizationId': OrganizationContext.currentOrganizationId},
    );
    if (!response.ok) {
      return TelegramLinkResult.fail(response.code, response.message);
    }
    return const TelegramLinkResult.ok(null);
  }

  static Future<TelegramLinkResult<TelegramNotificationPrefs>> updatePrefs({
    bool? risk,
    bool? overdue,
    int? quietFromHour,
    int? quietToHour,
  }) async {
    final body = <String, dynamic>{
      'timezoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      if (risk != null) 'risk': risk,
      if (overdue != null) 'overdue': overdue,
      if (quietFromHour != null) 'quietFromHour': quietFromHour,
      if (quietToHour != null) 'quietToHour': quietToHour,
    };
    final response = await _send(
      'POST',
      '/api/wesi/telegram/preferences',
      body: body,
    );
    if (!response.ok) {
      return TelegramLinkResult.fail(response.code, response.message);
    }
    final prefs = response.json!['notificationPrefs'];
    return TelegramLinkResult.ok(
      TelegramNotificationPrefs.fromJson(
        prefs is Map ? Map<String, dynamic>.from(prefs) : null,
      ),
    );
  }

  static Future<_TelegramApiResponse> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final session = SyncEndpoint.session;
    final token = session?['token'];
    final sessionId = session?['sessionId'];
    if (!SyncEndpoint.isConnected ||
        token is! String ||
        token.isEmpty ||
        sessionId is! String ||
        sessionId.isEmpty) {
      return const _TelegramApiResponse.fail(
        'NOT_SIGNED_IN',
        'Войдите в WesiOS заново',
      );
    }

    final base = Uri.tryParse(SyncEndpoint.url);
    if (base == null || base.host.isEmpty) {
      return const _TelegramApiResponse.fail(
        'BAD_ADDRESS',
        'Некорректный адрес Wesi server',
      );
    }
    final uri = base.replace(path: path);

    try {
      final request = await _http.openUrl(method, uri);
      request.headers.set(HttpHeaders.authorizationHeader, token);
      request.headers.set('X-WesiOS-Session', sessionId);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      final raw = await response.transform(utf8.decoder).join();
      Map<String, dynamic>? json;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) json = Map<String, dynamic>.from(decoded);
      } catch (_) {}

      if (response.statusCode >= 200 && response.statusCode < 300 && json != null) {
        return _TelegramApiResponse.ok(json);
      }
      final code = '${json?['code'] ?? 'HTTP_${response.statusCode}'}';
      final message = '${json?['message'] ?? json?['error'] ?? _fallback(response.statusCode)}';
      return _TelegramApiResponse.fail(code, message);
    } on SocketException {
      return const _TelegramApiResponse.fail(
        'NETWORK',
        'Нет связи с Wesi server',
      );
    } on HandshakeException {
      return const _TelegramApiResponse.fail(
        'NETWORK',
        'Сертификат Wesi server не принят',
      );
    } catch (_) {
      return const _TelegramApiResponse.fail(
        'NETWORK',
        'Wesi server временно недоступен',
      );
    }
  }

  static String _fallback(int status) {
    if (status == 401) return 'Сеанс WesiOS завершён';
    if (status == 403) return 'Нет доступа';
    if (status == 409) return 'Telegram уже привязан';
    if (status == 503) return 'Telegram на сервере ещё не настроен';
    return 'Ошибка Wesi server';
  }
}

class _TelegramApiResponse {
  const _TelegramApiResponse.ok(this.json)
      : code = null,
        message = null;

  const _TelegramApiResponse.fail(this.code, this.message) : json = null;

  final Map<String, dynamic>? json;
  final String? code;
  final String? message;

  bool get ok => code == null;
}
