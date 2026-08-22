import 'dart:async';
import 'dart:io';

class TunnelHealthResult {
  const TunnelHealthResult({
    required this.ok,
    required this.reason,
    this.rttMs,
  });

  final bool ok;
  final String reason;
  final int? rttMs;

  Map<String, Object?> toJson() => {
        'ok': ok,
        'reason': reason,
        'rttMs': rttMs,
        'tunnelStarted': true,
        'egressOk': ok,
      };
}

class TunnelHealthService {
  const TunnelHealthService();

  static final List<Uri> _targets = [
    Uri.parse('https://www.gstatic.com/generate_204'),
    Uri.parse('https://cp.cloudflare.com/generate_204'),
  ];

  Future<TunnelHealthResult> probe() async {
    Object? lastError;
    for (final target in _targets) {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final stopwatch = Stopwatch()..start();
      try {
        final request = await client.headUrl(target).timeout(const Duration(seconds: 3));
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        final response = await request.close().timeout(const Duration(seconds: 3));
        await response.drain<void>();
        stopwatch.stop();
        if (response.statusCode >= 200 && response.statusCode < 400) {
          final elapsed = stopwatch.elapsedMilliseconds;
          return TunnelHealthResult(
            ok: true,
            reason: 'HEALTHY',
            rttMs: elapsed < 1 ? 1 : (elapsed > 60000 ? 60000 : elapsed),
          );
        }
        lastError = 'HTTP_${response.statusCode}';
      } on SocketException catch (error) {
        lastError = error;
      } on TimeoutException catch (error) {
        lastError = error;
      } finally {
        client.close(force: true);
      }
    }
    return TunnelHealthResult(
      ok: false,
      reason: lastError is SocketException
          ? 'TUNNEL_EGRESS_FAILED'
          : 'PROTOCOL_BLOCKED_OR_BROKEN',
    );
  }
}
