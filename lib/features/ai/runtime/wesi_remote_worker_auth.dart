import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'wesi_remote_worker_models.dart';

class WesiRemoteWorkerSignedRequest {
  final String credentialId;
  final String workerId;
  final int timestampMs;
  final String nonce;
  final String bodySha256;
  final String signature;

  const WesiRemoteWorkerSignedRequest({
    required this.credentialId,
    required this.workerId,
    required this.timestampMs,
    required this.nonce,
    required this.bodySha256,
    required this.signature,
  });

  Map<String, String> toHeaders() => <String, String>{
        'X-Wesi-Worker-Credential': credentialId,
        'X-Wesi-Worker-Id': workerId,
        'X-Wesi-Worker-Timestamp': '$timestampMs',
        'X-Wesi-Worker-Nonce': nonce,
        'X-Wesi-Worker-Body-Sha256': bodySha256,
        'X-Wesi-Worker-Signature': signature,
      };
}

class WesiRemoteWorkerRequestSigner {
  static const protocol = 'wesi-worker-hmac-v1';
  final Random _random;

  WesiRemoteWorkerRequestSigner({Random? random})
      : _random = random ?? Random.secure();

  WesiRemoteWorkerSignedRequest sign({
    required WesiWorkerCredential credential,
    required String method,
    required String path,
    required List<int> body,
    DateTime? now,
  }) {
    final current = (now ?? DateTime.now()).toUtc();
    if (credential.expiredAt(current)) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_CREDENTIAL_EXPIRED',
        'Worker credential expired',
      );
    }
    _validateMethodAndPath(method, path);
    final nonce = _randomId(24);
    final bodySha = sha256.convert(body).toString();
    final timestamp = current.millisecondsSinceEpoch;
    final canonical = canonicalRequest(
      credentialId: credential.credentialId,
      workerId: credential.workerId,
      timestampMs: timestamp,
      nonce: nonce,
      method: method,
      path: path,
      bodySha256: bodySha,
    );
    final digest = Hmac(sha256, utf8.encode(credential.secret))
        .convert(utf8.encode(canonical))
        .toString();
    return WesiRemoteWorkerSignedRequest(
      credentialId: credential.credentialId,
      workerId: credential.workerId,
      timestampMs: timestamp,
      nonce: nonce,
      bodySha256: bodySha,
      signature: digest,
    );
  }

  static bool verify({
    required WesiRemoteWorkerSignedRequest request,
    required String secret,
    required String method,
    required String path,
    required List<int> body,
    DateTime? now,
    Duration maxSkew = const Duration(seconds: 90),
  }) {
    _validateMethodAndPath(method, path);
    if (!RegExp(r'^[A-Za-z0-9_-]{20,96}$').hasMatch(request.credentialId) ||
        !RegExp(r'^[A-Za-z0-9_-]{20,96}$').hasMatch(request.workerId) ||
        !RegExp(r'^[A-Za-z0-9_-]{20,96}$').hasMatch(request.nonce) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(request.bodySha256) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(request.signature)) {
      return false;
    }
    final current = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    if ((current - request.timestampMs).abs() > maxSkew.inMilliseconds) {
      return false;
    }
    final actualBody = sha256.convert(body).toString();
    if (!_constantTimeEquals(actualBody, request.bodySha256)) return false;
    final canonical = canonicalRequest(
      credentialId: request.credentialId,
      workerId: request.workerId,
      timestampMs: request.timestampMs,
      nonce: request.nonce,
      method: method,
      path: path,
      bodySha256: request.bodySha256,
    );
    final expected = Hmac(sha256, utf8.encode(secret))
        .convert(utf8.encode(canonical))
        .toString();
    return _constantTimeEquals(expected, request.signature);
  }

  static String canonicalRequest({
    required String credentialId,
    required String workerId,
    required int timestampMs,
    required String nonce,
    required String method,
    required String path,
    required String bodySha256,
  }) =>
      '$protocol\n$credentialId\n$workerId\n$timestampMs\n$nonce\n${method.toUpperCase()}\n$path\n$bodySha256';

  String _randomId(int bytes) {
    final data = Uint8List(bytes);
    for (var i = 0; i < data.length; i++) {
      data[i] = _random.nextInt(256);
    }
    return base64Url.encode(data).replaceAll('=', '');
  }

  static void _validateMethodAndPath(String method, String path) {
    if (!RegExp(r'^[A-Z]{3,8}$').hasMatch(method.toUpperCase()) ||
        !path.startsWith('/api/wesi/ai/workers/') ||
        path.length > 240 ||
        path.contains('\\') ||
        path.contains('..')) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_REQUEST_TARGET',
        'Remote worker request target is invalid',
      );
    }
  }

  static bool _constantTimeEquals(String a, String b) {
    final left = utf8.encode(a);
    final right = utf8.encode(b);
    var diff = left.length ^ right.length;
    final maxLength = max(left.length, right.length);
    for (var i = 0; i < maxLength; i++) {
      diff |= (i < left.length ? left[i] : 0) ^
          (i < right.length ? right[i] : 0);
    }
    return diff == 0;
  }
}

class WesiWorkerReplayGuard {
  final Duration ttl;
  final int maxEntries;
  final Map<String, DateTime> _seen = <String, DateTime>{};

  WesiWorkerReplayGuard({
    this.ttl = const Duration(minutes: 3),
    this.maxEntries = 2048,
  });

  bool accept(String credentialId, String nonce, {DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    _seen.removeWhere((_, at) => current.difference(at) > ttl);
    final key = '$credentialId:$nonce';
    if (_seen.containsKey(key)) return false;
    if (_seen.length >= maxEntries) {
      final oldest = _seen.entries.reduce(
        (a, b) => a.value.isBefore(b.value) ? a : b,
      );
      _seen.remove(oldest.key);
    }
    _seen[key] = current;
    return true;
  }
}
