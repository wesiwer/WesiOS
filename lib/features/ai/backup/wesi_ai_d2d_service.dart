import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../storage/wesi_ai_local_store.dart';
import 'wesi_ai_backup_crypto.dart';
import 'wesi_ai_backup_service.dart';

enum WesiAiD2DStatus {
  ready,
  transferring,
  completed,
  expired,
  stopped,
  failed
}

class WesiAiD2DDescriptor {
  final String host;
  final int port;
  final String sessionId;
  final Uint8List key;
  final String fingerprint;
  final DateTime expiresAt;

  const WesiAiD2DDescriptor({
    required this.host,
    required this.port,
    required this.sessionId,
    required this.key,
    required this.fingerprint,
    required this.expiresAt,
  });

  String encode() {
    final payload = utf8.encode(jsonEncode(<String, dynamic>{
      'version': 1,
      'host': host,
      'port': port,
      'sessionId': sessionId,
      'key': base64UrlEncode(key).replaceAll('=', ''),
      'fingerprint': fingerprint,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
    }));
    return 'WESI-D2D1:${base64UrlEncode(payload).replaceAll('=', '')}';
  }

  factory WesiAiD2DDescriptor.decode(String raw) {
    final clean = raw.trim();
    if (!clean.startsWith('WESI-D2D1:')) {
      throw const FormatException('Некорректный Wesi AI D2D descriptor');
    }
    try {
      var encoded = clean.substring('WESI-D2D1:'.length);
      while (encoded.length % 4 != 0) {
        encoded += '=';
      }
      final decoded = jsonDecode(utf8.decode(base64Url.decode(encoded)));
      if (decoded is! Map) throw const FormatException();
      final map = Map<String, dynamic>.from(decoded);
      if (map['version'] != 1) throw const FormatException();
      final host = '${map['host'] ?? ''}'.trim();
      final port = (map['port'] as num?)?.toInt() ?? 0;
      final sessionId = '${map['sessionId'] ?? ''}'.trim();
      var keyRaw = '${map['key'] ?? ''}'.trim();
      while (keyRaw.length % 4 != 0) {
        keyRaw += '=';
      }
      final key = Uint8List.fromList(base64Url.decode(keyRaw));
      final fingerprint = '${map['fingerprint'] ?? ''}'.trim().toUpperCase();
      final expiresAt = DateTime.tryParse('${map['expiresAt'] ?? ''}');
      final address = InternetAddress.tryParse(host);
      if (address == null ||
          !_isPrivateOrLoopback(address) ||
          port <= 0 ||
          port > 65535 ||
          !RegExp(r'^[A-Za-z0-9_-]{16,180}$').hasMatch(sessionId) ||
          key.lengthInBytes != 32 ||
          expiresAt == null ||
          fingerprint != WesiAiBackupCrypto.fingerprint(key)) {
        throw const FormatException();
      }
      final now = DateTime.now().toUtc();
      final expiry = expiresAt.toUtc();
      if (!expiry.isAfter(now) ||
          expiry.difference(now) > const Duration(minutes: 10)) {
        throw const FormatException();
      }
      return WesiAiD2DDescriptor(
        host: address.address,
        port: port,
        sessionId: sessionId,
        key: key,
        fingerprint: fingerprint,
        expiresAt: expiry,
      );
    } catch (_) {
      throw const FormatException('Некорректный или истёкший D2D descriptor');
    }
  }

  static bool _isPrivateOrLoopback(InternetAddress address) =>
      WesiAiD2DService.isPrivateOrLoopback(address);
}

class WesiAiD2DTransferSession {
  final WesiAiD2DDescriptor descriptor;
  final ValueNotifier<WesiAiD2DStatus> status;
  final HttpServer _server;
  final Timer _expiryTimer;
  bool _used = false;

  WesiAiD2DTransferSession._({
    required this.descriptor,
    required this.status,
    required HttpServer server,
    required Timer expiryTimer,
  })  : _server = server,
        _expiryTimer = expiryTimer;

  String get transferCode => descriptor.encode();

  Future<void> stop() async {
    if (status.value == WesiAiD2DStatus.completed ||
        status.value == WesiAiD2DStatus.expired ||
        status.value == WesiAiD2DStatus.stopped) {
      return;
    }
    status.value = WesiAiD2DStatus.stopped;
    _expiryTimer.cancel();
    await _server.close(force: true);
  }
}

class WesiAiD2DService {
  static const Duration sessionTtl = Duration(minutes: 10);
  static const String _authHeader = 'x-wesi-transfer-auth';

  const WesiAiD2DService._();

  static Future<WesiAiD2DTransferSession> startSender(
    WesiAiLocalState state, {
    Duration ttl = sessionTtl,
    InternetAddress? hostOverride,
  }) async {
    if (ttl <= Duration.zero || ttl > sessionTtl) {
      throw const FormatException('Некорректный D2D TTL');
    }
    final build = await WesiAiBackupService.buildImportantPackage(state);
    final key = WesiAiBackupCrypto.randomSessionKey();
    final encrypted =
        WesiAiBackupCrypto.encryptTransfer(build.packageBytes, key);
    final host = hostOverride ?? await _privateHost();
    final sessionId = _randomId();
    final server =
        await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: false);
    final expiresAt = DateTime.now().toUtc().add(ttl);
    final descriptor = WesiAiD2DDescriptor(
      host: host.address,
      port: server.port,
      sessionId: sessionId,
      key: key,
      fingerprint: WesiAiBackupCrypto.fingerprint(key),
      expiresAt: expiresAt,
    );
    final status = ValueNotifier<WesiAiD2DStatus>(WesiAiD2DStatus.ready);
    late final WesiAiD2DTransferSession session;
    final expiryTimer = Timer(ttl, () async {
      if (status.value == WesiAiD2DStatus.completed ||
          status.value == WesiAiD2DStatus.stopped) {
        return;
      }
      status.value = WesiAiD2DStatus.expired;
      await server.close(force: true);
    });
    session = WesiAiD2DTransferSession._(
      descriptor: descriptor,
      status: status,
      server: server,
      expiryTimer: expiryTimer,
    );

    unawaited(() async {
      try {
        await for (final request in server) {
          if (session._used || DateTime.now().toUtc().isAfter(expiresAt)) {
            request.response.statusCode = HttpStatus.gone;
            await request.response.close();
            continue;
          }
          if (!isPrivateOrLoopback(request.connectionInfo?.remoteAddress)) {
            request.response.statusCode = HttpStatus.forbidden;
            await request.response.close();
            continue;
          }
          final expectedPath = '/v1/wesi-ai-transfer/$sessionId';
          if (request.method != 'GET' || request.uri.path != expectedPath) {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
            continue;
          }
          final expectedAuth =
              WesiAiBackupCrypto.transferAuthToken(sessionId, key);
          final providedAuth = request.headers.value(_authHeader) ?? '';
          if (!WesiAiBackupCrypto.constantTimeEquals(
              expectedAuth, providedAuth)) {
            request.response.statusCode = HttpStatus.unauthorized;
            await request.response.close();
            continue;
          }
          session._used = true;
          status.value = WesiAiD2DStatus.transferring;
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.binary;
          request.response.headers.contentLength = encrypted.lengthInBytes;
          request.response.headers.set('cache-control', 'no-store');
          request.response.add(encrypted);
          await request.response.close();
          status.value = WesiAiD2DStatus.completed;
          expiryTimer.cancel();
          await server.close(force: true);
          break;
        }
      } catch (_) {
        if (status.value != WesiAiD2DStatus.completed &&
            status.value != WesiAiD2DStatus.stopped &&
            status.value != WesiAiD2DStatus.expired) {
          status.value = WesiAiD2DStatus.failed;
          expiryTimer.cancel();
          await server.close(force: true);
        }
      }
    }());
    return session;
  }

  static Future<WesiAiBackupImportResult> receive({
    required String transferCode,
    required WesiAiLocalState current,
  }) async {
    final descriptor = WesiAiD2DDescriptor.decode(transferCode);
    final address = InternetAddress.tryParse(descriptor.host);
    if (!isPrivateOrLoopback(address)) {
      throw const FormatException('D2D sender находится вне локальной сети');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri(
        scheme: 'http',
        host: descriptor.host,
        port: descriptor.port,
        path: '/v1/wesi-ai-transfer/${descriptor.sessionId}',
      );
      final request = await client.getUrl(uri);
      request.headers.set(
        _authHeader,
        WesiAiBackupCrypto.transferAuthToken(
          descriptor.sessionId,
          descriptor.key,
        ),
      );
      request.headers.set('cache-control', 'no-store');
      final response =
          await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode != HttpStatus.ok) {
        throw FormatException(
            'D2D sender отклонил запрос (${response.statusCode})');
      }
      final declared = response.contentLength;
      if (declared > WesiAiBackupService.maxPackageBytes + 1024 * 1024) {
        throw const FormatException('D2D пакет превышает допустимый размер');
      }
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in response) {
        received += chunk.length;
        if (received > WesiAiBackupService.maxPackageBytes + 1024 * 1024) {
          throw const FormatException('D2D пакет превышает допустимый размер');
        }
        builder.add(chunk);
      }
      final encrypted = builder.takeBytes();
      final package = WesiAiBackupCrypto.decryptTransfer(
        encrypted,
        descriptor.key,
      );
      return WesiAiBackupService.importPackage(
        package: package,
        current: current,
      );
    } on SocketException {
      throw const FormatException(
          'Не удалось подключиться к устройству в LAN/Wi‑Fi');
    } on TimeoutException {
      throw const FormatException('D2D соединение истекло по таймауту');
    } finally {
      client.close(force: true);
    }
  }

  static bool isPrivateOrLoopback(InternetAddress? address) {
    if (address == null) return false;
    if (address.isLoopback) return true;
    if (address.type == InternetAddressType.IPv4) {
      final parts = address.address.split('.').map(int.tryParse).toList();
      if (parts.length != 4 || parts.any((value) => value == null))
        return false;
      final a = parts[0]!;
      final b = parts[1]!;
      return a == 10 ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) ||
          (a == 169 && b == 254);
    }
    final lower = address.address.toLowerCase();
    return lower.startsWith('fc') ||
        lower.startsWith('fd') ||
        lower.startsWith('fe8') ||
        lower.startsWith('fe9') ||
        lower.startsWith('fea') ||
        lower.startsWith('feb');
  }

  static Future<InternetAddress> _privateHost() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (isPrivateOrLoopback(address) && !address.isLoopback) return address;
      }
    }
    throw const FormatException('Не найден приватный LAN/Wi‑Fi IPv4 адрес');
  }

  static String _randomId() {
    final key = WesiAiBackupCrypto.randomSessionKey();
    return base64UrlEncode(key).replaceAll('=', '').substring(0, 32);
  }
}
