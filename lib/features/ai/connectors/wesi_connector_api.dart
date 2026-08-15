import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/sync/sync_endpoint.dart';

class WesiConnectorApiException implements Exception {
  final String code;
  final String message;
  const WesiConnectorApiException(this.code, this.message);
  @override
  String toString() => message;
}

class WesiConnectorCredential {
  final String credentialId;
  final String provider;
  final String accountLogin;
  final String accountId;
  final List<String> scopes;
  final String status;

  const WesiConnectorCredential(
      {required this.credentialId,
      required this.provider,
      required this.accountLogin,
      required this.accountId,
      required this.scopes,
      required this.status});

  factory WesiConnectorCredential.fromJson(Map<String, dynamic> json) =>
      WesiConnectorCredential(
        credentialId: '${json['credentialId'] ?? ''}',
        provider: '${json['provider'] ?? ''}',
        accountLogin: '${json['accountLogin'] ?? ''}',
        accountId: '${json['accountId'] ?? ''}',
        scopes: (json['scopes'] is List
            ? (json['scopes'] as List)
                .map((e) => '$e')
                .take(32)
                .toList(growable: false)
            : const <String>[]),
        status: '${json['status'] ?? 'invalid'}',
      );
}

class WesiConnectorProvider {
  final String id;
  final String title;
  final bool available;
  final bool connected;
  final List<WesiConnectorCredential> accounts;
  const WesiConnectorProvider(
      {required this.id,
      required this.title,
      required this.available,
      required this.connected,
      required this.accounts});
  factory WesiConnectorProvider.fromJson(Map<String, dynamic> json) {
    final raw = json['accounts'];
    return WesiConnectorProvider(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        available: json['available'] == true,
        connected: json['connected'] == true,
        accounts: raw is List
            ? raw
                .whereType<Map>()
                .map((e) => WesiConnectorCredential.fromJson(
                    Map<String, dynamic>.from(e)))
                .toList(growable: false)
            : const <WesiConnectorCredential>[]);
  }
}

class WesiGithubDeviceFlow {
  final String flowId;
  final String userCode;
  final Uri verificationUri;
  final DateTime expiresAt;
  final int intervalSeconds;
  const WesiGithubDeviceFlow(
      {required this.flowId,
      required this.userCode,
      required this.verificationUri,
      required this.expiresAt,
      required this.intervalSeconds});
  factory WesiGithubDeviceFlow.fromJson(Map<String, dynamic> json) {
    final flowId = '${json['flowId'] ?? ''}',
        code = '${json['userCode'] ?? ''}',
        uri = Uri.tryParse('${json['verificationUri'] ?? ''}'),
        expires = DateTime.tryParse('${json['expiresAt'] ?? ''}'),
        interval = (json['interval'] as num?)?.toInt() ?? 5;
    if (!RegExp(r'^wai_conn_flow_[A-Za-z0-9_-]{20,80}$').hasMatch(flowId) ||
        code.isEmpty ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        expires == null)
      throw const FormatException('Invalid GitHub device flow');
    return WesiGithubDeviceFlow(
        flowId: flowId,
        userCode: code,
        verificationUri: uri,
        expiresAt: expires.toUtc(),
        intervalSeconds: interval.clamp(5, 60));
  }
}

class WesiGithubPollResult {
  final bool connected;
  final int retryAfterSeconds;
  final WesiConnectorCredential? credential;
  const WesiGithubPollResult(
      {required this.connected, this.retryAfterSeconds = 5, this.credential});
}

class WesiConnectorApi {
  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 20);
  const WesiConnectorApi();

  Future<List<WesiConnectorProvider>> listProviders() async {
    final body = await _request('GET', '/api/wesi/ai/connectors');
    final raw = body['providers'];
    return raw is List
        ? raw
            .whereType<Map>()
            .map((e) =>
                WesiConnectorProvider.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false)
        : const <WesiConnectorProvider>[];
  }

  Future<WesiGithubDeviceFlow> startGithub() async {
    final body =
        await _request('POST', '/api/wesi/ai/connectors/github/device/start');
    final raw = body['flow'];
    if (raw is! Map)
      throw const WesiConnectorApiException(
          'CONNECTOR_BAD_RESPONSE', 'Сервер вернул некорректный Device Flow');
    return WesiGithubDeviceFlow.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<WesiGithubPollResult> pollGithub(String flowId) async {
    final body = await _request(
        'POST', '/api/wesi/ai/connectors/github/device/poll',
        payload: <String, dynamic>{'flowId': flowId});
    if ('${body['state']}' == 'connected') {
      final raw = body['credential'];
      if (raw is! Map)
        throw const WesiConnectorApiException('CONNECTOR_BAD_RESPONSE',
            'GitHub подключён, но credential metadata повреждена');
      return WesiGithubPollResult(
          connected: true,
          credential:
              WesiConnectorCredential.fromJson(Map<String, dynamic>.from(raw)));
    }
    return WesiGithubPollResult(
        connected: false,
        retryAfterSeconds:
            ((body['retryAfterSeconds'] as num?)?.toInt() ?? 5).clamp(1, 60));
  }

  Future<void> disconnect(WesiConnectorCredential credential) async {
    await _request('POST', '/api/wesi/ai/connectors/disconnect',
        payload: <String, dynamic>{
          'provider': credential.provider,
          'credentialId': credential.credentialId
        });
  }

  Future<Map<String, dynamic>> _request(String method, String path,
      {Map<String, dynamic>? payload}) async {
    final session = SyncEndpoint.session,
        token = session?['token'],
        sessionId = SyncEndpoint.sessionId;
    if (!SyncEndpoint.isConnected ||
        token is! String ||
        token.isEmpty ||
        sessionId == null ||
        sessionId.isEmpty)
      throw const WesiConnectorApiException(
          'NOT_SIGNED_IN', 'Войдите в WesiOS, чтобы управлять коннекторами');
    try {
      final base = Uri.parse(SyncEndpoint.url), uri = base.replace(path: path);
      final request =
          method == 'GET' ? await _http.getUrl(uri) : await _http.postUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, token);
      request.headers.set('X-WesiOS-Session', sessionId);
      request.headers.contentType = ContentType.json;
      if (payload != null) request.write(jsonEncode(payload));
      final response =
              await request.close().timeout(const Duration(seconds: 30)),
          raw = await utf8.decoder.bind(response).join();
      Map<String, dynamic> body = <String, dynamic>{};
      if (raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) body = Map<String, dynamic>.from(decoded);
      }
      if (response.statusCode < 200 || response.statusCode >= 300)
        throw WesiConnectorApiException(
            '${body['code'] ?? 'CONNECTOR_REQUEST_FAILED'}',
            '${body['message'] ?? 'Не удалось выполнить запрос коннектора'}');
      return body;
    } on WesiConnectorApiException {
      rethrow;
    } on TimeoutException {
      throw const WesiConnectorApiException(
          'NETWORK', 'Сервер коннекторов не ответил вовремя');
    } on SocketException {
      throw const WesiConnectorApiException(
          'NETWORK', 'Нет связи с сервером WesiOS');
    } on HttpException {
      throw const WesiConnectorApiException(
          'NETWORK', 'Ошибка связи с сервером WesiOS');
    } on FormatException {
      throw const WesiConnectorApiException(
          'CONNECTOR_BAD_RESPONSE', 'Сервер вернул повреждённый ответ');
    }
  }
}
