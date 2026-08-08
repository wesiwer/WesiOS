import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/security/session_service.dart';
import '../../core/sync/sync_endpoint.dart';
import '../team/services/portal_account_service.dart';

/// Temporary owner-only recovery bridge.
///
/// This exists only for the recovery build while outbound mail is unavailable.
/// The server still requires a short-lived root-created recovery flag and
/// consumes it after the first challenge, so this cannot become a permanent
/// passwordless login path by itself.
class OwnerRecoveryResult {
  final PortalAppIdentity? identity;
  final String? error;

  const OwnerRecoveryResult.success(this.identity) : error = null;
  const OwnerRecoveryResult.failure(this.error) : identity = null;

  bool get ok => identity != null && error == null;
}

class OwnerRecoveryService {
  OwnerRecoveryService._();

  // TEMPORARY. Remove together with the recovery button after owner access is
  // restored and permanent credentials/email are configured in WesiOS.
  static const String _login = 'WesiOff';
  static const String _password = 'WesiTemp-8264-K7mQ';
  static const String _recoveryCode = '734821';

  static Future<OwnerRecoveryResult> recover() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final start = await client.postUrl(
        Uri.parse('${SyncEndpoint.url}/api/wesi/auth/start-v2'),
      );
      start.headers.contentType = ContentType.json;
      start.write(jsonEncode({
        'login': _login,
        'password': _password,
        'purpose': 'app',
      }));
      final startResponse = await start.close().timeout(const Duration(seconds: 20));
      final startText = await utf8.decoder.bind(startResponse).join();
      final startJson = _map(startText);
      if (startResponse.statusCode != 200) {
        return OwnerRecoveryResult.failure(
          PortalAccountService.messageForResponse(
            startResponse.statusCode,
            startText,
            fallback: 'Временный вход владельца не активирован на сервере.',
          ),
        );
      }

      final challengeId = startJson?['challengeId'];
      if (challengeId is! String || challengeId.isEmpty) {
        return const OwnerRecoveryResult.failure(
          'Сервер не создал временную проверку владельца.',
        );
      }

      final device = await SessionService.deviceMetadata();
      final verify = await client.postUrl(
        Uri.parse('${SyncEndpoint.url}/api/wesi/auth/verify'),
      );
      verify.headers.contentType = ContentType.json;
      verify.write(jsonEncode({
        'challengeId': challengeId,
        'code': _recoveryCode,
        'remember': true,
        'device': device,
      }));
      final verifyResponse = await verify.close().timeout(const Duration(seconds: 20));
      final verifyText = await utf8.decoder.bind(verifyResponse).join();
      final verifyJson = _map(verifyText);
      if (verifyResponse.statusCode != 200) {
        return OwnerRecoveryResult.failure(
          PortalAccountService.messageForResponse(
            verifyResponse.statusCode,
            verifyText,
            fallback: 'Временный код владельца не подтверждён.',
          ),
        );
      }

      final token = verifyJson?['token'];
      final userId = verifyJson?['userId'];
      final sessionId = verifyJson?['sessionId'];
      final expiresAt = DateTime.tryParse('${verifyJson?['expiresAt'] ?? ''}');
      if (token is! String ||
          token.isEmpty ||
          userId is! String ||
          userId.isEmpty ||
          sessionId is! String ||
          sessionId.isEmpty ||
          expiresAt == null) {
        return const OwnerRecoveryResult.failure(
          'Сервер вернул неполную временную сессию владельца.',
        );
      }

      final bootstrap = await client.getUrl(
        Uri.parse('${SyncEndpoint.url}/api/wesi/app/bootstrap'),
      );
      bootstrap.headers.set(HttpHeaders.authorizationHeader, token);
      bootstrap.headers.set('X-WesiOS-Session', sessionId);
      final bootstrapResponse =
          await bootstrap.close().timeout(const Duration(seconds: 18));
      final bootstrapText = await utf8.decoder.bind(bootstrapResponse).join();
      if (bootstrapResponse.statusCode != 200) {
        return OwnerRecoveryResult.failure(
          PortalAccountService.messageForResponse(
            bootstrapResponse.statusCode,
            bootstrapText,
            fallback: 'Сервер не подтвердил профиль владельца.',
          ),
        );
      }

      final bootstrapJson = _map(bootstrapText);
      final identity = bootstrapJson == null
          ? null
          : PortalAppIdentity.tryParse(bootstrapJson);
      if (identity == null || !identity.isOwner) {
        return const OwnerRecoveryResult.failure(
          'Временный вход не получил профиль владельца.',
        );
      }

      await SyncEndpoint.configure(login: identity.login);
      await SyncEndpoint.saveSession(
        token: token,
        userId: userId,
        sessionId: sessionId,
        expiresAt: expiresAt,
      );
      await SyncEndpoint.setEnabled(true);
      return OwnerRecoveryResult.success(identity);
    } on TimeoutException {
      return const OwnerRecoveryResult.failure(
        'Сервер WesiOS не ответил вовремя.',
      );
    } on SocketException {
      return const OwnerRecoveryResult.failure('Нет связи с сервером WesiOS.');
    } on HandshakeException {
      return const OwnerRecoveryResult.failure(
        'Не удалось проверить сертификат сервера WesiOS.',
      );
    } catch (_) {
      return const OwnerRecoveryResult.failure(
        'Не удалось выполнить временный вход владельца.',
      );
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, dynamic>? _map(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }
}
