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
          !WesiAiD2DService.isPrivateOrLoopback(address) ||
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
}

class WesiAiD2DTransferSession {
  final WesiAiD2DDescriptor descriptor;
  final ValueNotifier<WesiAiD2DStatus> status;
  final ServerSocket _server;
  final Timer _expiryTimer;
  bool _used = false;

  WesiAiD2DTransferSession._({
    required this.descriptor,
    required this.status,
    required ServerSocket server,
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
    await _server.close();
  }
}

class WesiAiD2DService {
  static const Duration sessionTtl = Duration(minutes: 10);
  static const Duration _connectTimeout = Duration(seconds: 8);
  static const Duration _frameTimeout = Duration(seconds: 12);
  static const int _maxControlLineBytes = 1024;

  const WesiAiD2DService._();

  static Future<WesiAiD2DTransferSession> startSender(
    WesiAiLocalState state, {
    Duration ttl = sessionTtl,
    InternetAddress? hostOverride,
  }) async {
    if (ttl <= Duration.zero || ttl > sessionTtl) {
      throw const FormatException('Некорректный D2D TTL');
    }
    final build = await WesiAiBackupService.buildFullTransferPackage(state);
    final key = WesiAiBackupCrypto.randomSessionKey();
    final encrypted =
        WesiAiBackupCrypto.encryptTransfer(build.packageBytes, key);
    final host = hostOverride ?? await _privateHost();
    if (!isPrivateOrLoopback(host)) {
      throw const FormatException('D2D host находится вне локальной сети');
    }
    final sessionId = _randomId();
    final server = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      0,
      shared: false,
    );
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
      await server.close();
    });
    session = WesiAiD2DTransferSession._(
      descriptor: descriptor,
      status: status,
      server: server,
      expiryTimer: expiryTimer,
    );

    unawaited(() async {
      try {
        await for (final socket in server) {
          try {
            if (session._used || DateTime.now().toUtc().isAfter(expiresAt)) {
              await _sendControl(socket, 'ERR GONE');
              continue;
            }
            if (!isPrivateOrLoopback(socket.remoteAddress)) {
              await _sendControl(socket, 'ERR FORBIDDEN');
              continue;
            }
            final request = await _readControlLine(socket);
            final parts = request.split(' ');
            if (parts.length != 3 ||
                parts[0] != 'WESI1' ||
                parts[1] != sessionId) {
              await _sendControl(socket, 'ERR REQUEST');
              continue;
            }
            final expectedAuth =
                WesiAiBackupCrypto.transferAuthToken(sessionId, key);
            if (!WesiAiBackupCrypto.constantTimeEquals(
              expectedAuth,
              parts[2],
            )) {
              await _sendControl(socket, 'ERR AUTH');
              continue;
            }
            session._used = true;
            status.value = WesiAiD2DStatus.transferring;
            socket.add(utf8.encode('OK ${encrypted.lengthInBytes}\n'));
            socket.add(encrypted);
            await socket.flush();
            await socket.close();
            status.value = WesiAiD2DStatus.completed;
            expiryTimer.cancel();
            await server.close();
            break;
          } catch (_) {
            try {
              await socket.close();
            } catch (_) {}
            if (session._used) rethrow;
          }
        }
      } catch (_) {
        if (status.value != WesiAiD2DStatus.completed &&
            status.value != WesiAiD2DStatus.stopped &&
            status.value != WesiAiD2DStatus.expired) {
          status.value = WesiAiD2DStatus.failed;
          expiryTimer.cancel();
          await server.close();
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
    Socket? socket;
    try {
      socket = await Socket.connect(
        descriptor.host,
        descriptor.port,
        timeout: _connectTimeout,
      );
      final auth = WesiAiBackupCrypto.transferAuthToken(
        descriptor.sessionId,
        descriptor.key,
      );
      socket.write('WESI1 ${descriptor.sessionId} $auth\n');
      await socket.flush();
      final encrypted = await _readPayload(socket);
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
        'Не удалось подключиться к устройству в LAN/Wi‑Fi',
      );
    } on TimeoutException {
      throw const FormatException('D2D соединение истекло по таймауту');
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  static Future<String> _readControlLine(Socket socket) async {
    final completer = Completer<String>();
    final buffer = <int>[];
    late StreamSubscription<Uint8List> subscription;
    subscription = socket.listen(
      (chunk) {
        if (completer.isCompleted) return;
        for (final byte in chunk) {
          if (byte == 10) {
            try {
              completer.complete(utf8.decode(buffer).trim());
            } catch (error, stack) {
              completer.completeError(error, stack);
            }
            subscription.pause();
            return;
          }
          if (byte == 13) continue;
          buffer.add(byte);
          if (buffer.length > _maxControlLineBytes) {
            completer.completeError(
              const FormatException('D2D control frame слишком большой'),
            );
            subscription.pause();
            return;
          }
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(
            const FormatException('D2D control frame оборван'),
          );
        }
      },
      cancelOnError: false,
    );
    try {
      return await completer.future.timeout(_frameTimeout);
    } finally {
      await subscription.cancel();
    }
  }

  static Future<Uint8List> _readPayload(Socket socket) async {
    final completer = Completer<Uint8List>();
    final header = <int>[];
    final body = BytesBuilder(copy: false);
    int? expectedLength;
    late StreamSubscription<Uint8List> subscription;

    void fail(Object error, [StackTrace? stack]) {
      if (completer.isCompleted) return;
      if (stack == null) {
        completer.completeError(error);
      } else {
        completer.completeError(error, stack);
      }
      subscription.pause();
    }

    subscription = socket.listen(
      (chunk) {
        if (completer.isCompleted) return;
        var index = 0;
        while (index < chunk.length) {
          if (expectedLength == null) {
            final byte = chunk[index++];
            if (byte == 10) {
              String line;
              try {
                line = utf8.decode(header).trim();
              } catch (error, stack) {
                fail(error, stack);
                return;
              }
              if (line.startsWith('ERR ')) {
                fail(FormatException('D2D sender отклонил запрос: $line'));
                return;
              }
              final match = RegExp(r'^OK ([0-9]{1,12})$').firstMatch(line);
              final parsed =
                  match == null ? null : int.tryParse(match.group(1)!);
              if (parsed == null ||
                  parsed <= 0 ||
                  parsed > WesiAiBackupService.maxPackageBytes + 1024 * 1024) {
                fail(const FormatException('Некорректный D2D payload header'));
                return;
              }
              expectedLength = parsed;
              continue;
            }
            if (byte != 13) header.add(byte);
            if (header.length > _maxControlLineBytes) {
              fail(
                  const FormatException('D2D response header слишком большой'));
              return;
            }
            continue;
          }
          final expected = expectedLength!;
          final remaining = expected - body.length;
          final take = (chunk.length - index) < remaining
              ? chunk.length - index
              : remaining;
          if (take > 0) {
            body.add(Uint8List.sublistView(chunk, index, index + take));
            index += take;
          }
          if (body.length == expected) {
            if (index != chunk.length) {
              fail(const FormatException('D2D payload содержит лишние байты'));
              return;
            }
            completer.complete(body.takeBytes());
            subscription.pause();
            return;
          }
        }
      },
      onError: (Object error, StackTrace stack) => fail(error, stack),
      onDone: () {
        if (!completer.isCompleted) {
          fail(const FormatException('D2D payload оборван'));
        }
      },
      cancelOnError: false,
    );
    try {
      return await completer.future.timeout(_frameTimeout);
    } finally {
      await subscription.cancel();
    }
  }

  static Future<void> _sendControl(Socket socket, String line) async {
    socket.add(utf8.encode('$line\n'));
    await socket.flush();
    await socket.close();
  }

  static bool isPrivateOrLoopback(InternetAddress? address) {
    if (address == null) return false;
    if (address.isLoopback) return true;
    if (address.type == InternetAddressType.IPv4) {
      final parts = address.address.split('.').map(int.tryParse).toList();
      if (parts.length != 4 || parts.any((value) => value == null)) {
        return false;
      }
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
