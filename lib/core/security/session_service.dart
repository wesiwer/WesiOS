import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../sync/sync_endpoint.dart';

class WesiSessionInfo {
  final String id;
  final bool current;
  final String purpose;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;
  final DateTime? expiresAt;
  final bool remember;
  final String ip;
  final String platform;
  final String deviceName;
  final String timezone;
  final String country;
  final String userAgent;

  const WesiSessionInfo({
    required this.id,
    required this.current,
    required this.purpose,
    required this.createdAt,
    required this.lastSeenAt,
    required this.expiresAt,
    required this.remember,
    required this.ip,
    required this.platform,
    required this.deviceName,
    required this.timezone,
    required this.country,
    required this.userAgent,
  });

  static WesiSessionInfo? tryParse(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return WesiSessionInfo(
      id: id,
      current: json['current'] == true,
      purpose: '${json['purpose'] ?? ''}',
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
      lastSeenAt: DateTime.tryParse('${json['lastSeenAt'] ?? ''}'),
      expiresAt: DateTime.tryParse('${json['expiresAt'] ?? ''}'),
      remember: json['remember'] == true,
      ip: '${json['ip'] ?? ''}',
      platform: '${json['platform'] ?? ''}',
      deviceName: '${json['deviceName'] ?? ''}',
      timezone: '${json['timezone'] ?? ''}',
      country: '${json['country'] ?? ''}',
      userAgent: '${json['userAgent'] ?? ''}',
    );
  }
}

class SessionService {
  SessionService._();

  static const heartbeatEvery = Duration(seconds: 5);
  static Timer? _heartbeat;
  static bool _pingBusy = false;

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<Map<String, dynamic>> deviceMetadata() async {
    var deviceName = '';
    var platform = kIsWeb ? 'web' : Platform.operatingSystem;
    try {
      final info = await DeviceInfoPlugin().deviceInfo;
      final data = info.data;
      final values = [
        data['computerName'],
        data['model'],
        data['productName'],
        data['device'],
        data['name'],
      ];
      for (final value in values) {
        final text = '${value ?? ''}'.trim();
        if (text.isNotEmpty && text != 'null') {
          deviceName = text;
          break;
        }
      }
      final os = '${data['osName'] ?? data['systemName'] ?? ''}'.trim();
      if (os.isNotEmpty && os != 'null') platform = os;
    } catch (_) {}

    final now = DateTime.now();
    return {
      'platform': platform,
      'deviceName': deviceName.isEmpty ? platform : deviceName,
      'timezone': '${now.timeZoneName} UTC${_offset(now.timeZoneOffset)}',
    };
  }

  static String _offset(Duration value) {
    final sign = value.isNegative ? '-' : '+';
    final total = value.inMinutes.abs();
    final hours = (total ~/ 60).toString().padLeft(2, '0');
    final minutes = (total % 60).toString().padLeft(2, '0');
    return '$sign$hours:$minutes';
  }

  static void startHeartbeat() {
    stopHeartbeat();
    if (!SyncEndpoint.isConnected) return;
    _heartbeat = Timer.periodic(
      heartbeatEvery,
      (_) => unawaited(ping()),
    );
    unawaited(ping());
  }

  static void stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _pingBusy = false;
  }

  static Future<bool> ping() async {
    if (_pingBusy || !SyncEndpoint.isConnected) return SyncEndpoint.isConnected;
    _pingBusy = true;
    try {
      final response = await _request('GET', '/api/wesi/security/session/ping');
      return response != null;
    } finally {
      _pingBusy = false;
    }
  }

  static Future<List<WesiSessionInfo>> list() async {
    final body = await _request('GET', '/api/wesi/security/sessions');
    final raw = body?['items'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          WesiSessionInfo.tryParse(Map<String, dynamic>.from(item)),
    ].whereType<WesiSessionInfo>().toList();
  }

  static Future<bool> revoke(String sessionId) async {
    final body = await _request(
      'POST',
      '/api/wesi/security/sessions/revoke',
      body: {'sessionId': sessionId},
    );
    if (body == null) return false;
    revision.value++;
    if (sessionId == SyncEndpoint.sessionId) {
      stopHeartbeat();
      await SyncEndpoint.clearSession();
    }
    return body['ok'] == true;
  }

  static Future<void> revokeCurrent() async {
    final id = SyncEndpoint.sessionId;
    if (id == null || id.isEmpty) return;
    await revoke(id);
  }

  static Future<Map<String, dynamic>?> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final session = SyncEndpoint.session;
    final token = session?['token'];
    final sessionId = SyncEndpoint.sessionId;
    if (token is! String || token.isEmpty || sessionId == null || sessionId.isEmpty) {
      return null;
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.parse('${SyncEndpoint.url}$path');
      final request = await client.openUrl(method, uri);
      request.headers.set(HttpHeaders.authorizationHeader, token);
      request.headers.set('X-WesiOS-Session', sessionId);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(const Duration(seconds: 15));
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode == 401 || response.statusCode == 403) {
        stopHeartbeat();
        await SyncEndpoint.clearSession();
        revision.value++;
        return null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      if (text.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(text);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } on TimeoutException {
      return null;
    } on SocketException {
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
