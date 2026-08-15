import 'dart:async';
import 'dart:io';

import 'wesi_local_runtime_policy.dart';

/// Creates an HttpClient whose TCP connection is pinned to an IP address that
/// has already passed WesiOS SSRF policy. HTTPS still validates the original
/// hostname through TLS SNI/certificate checks, but no second DNS lookup can
/// redirect the socket to localhost/private metadata after validation.
class WesiPinnedHttpClient {
  WesiPinnedHttpClient._();

  static Future<HttpClient> create(Uri uri) async {
    List<InternetAddress> addresses;
    try {
      addresses = await InternetAddress.lookup(uri.host);
    } on SocketException {
      throw const WesiLocalRuntimePolicyException(
        'WLR_DNS_FAILED',
        'Не удалось разрешить HTTP hostname',
      );
    }
    if (addresses.isEmpty ||
        addresses.any(WesiLocalRuntimePolicy.isPrivateOrSpecialAddress)) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_SSRF_BLOCKED',
        'HTTP-назначение попадает в private/internal/special network',
      );
    }

    // We intentionally pin one already-validated address for this request.
    // A redirect creates a fresh client and repeats DNS validation for the new
    // hostname instead of reusing the old host/IP decision.
    final pinned = addresses.first;
    final expectedScheme = uri.scheme.toLowerCase();
    final expectedHost = uri.host.toLowerCase();
    final expectedPort = _effectivePort(uri);

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 20)
      ..findProxy = (_) => 'DIRECT';

    client.connectionFactory = (
      Uri target,
      String? proxyHost,
      int? proxyPort,
    ) async {
      final targetScheme = target.scheme.toLowerCase();
      final targetPort = _effectivePort(target);
      if (proxyHost != null ||
          proxyPort != null ||
          targetScheme != expectedScheme ||
          target.host.toLowerCase() != expectedHost ||
          targetPort != expectedPort) {
        throw const SocketException(
          'Blocked local runtime connection target mismatch',
        );
      }

      final rawTask = await Socket.startConnect(pinned, targetPort);
      Future<Socket> socket = rawTask.socket;
      if (targetScheme == 'https') {
        socket = socket.then<Socket>(
          (plain) => SecureSocket.secure(plain, host: target.host),
        );
      }
      return ConnectionTask.fromSocket<Socket>(socket, rawTask.cancel);
    };

    return client;
  }

  static int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
  }
}
