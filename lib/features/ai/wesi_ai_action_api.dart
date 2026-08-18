import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/sync/sync_endpoint.dart';

class WesiAiActionConfirmationResult {
  final bool ok;
  final String tool;
  final String? code;
  final String? message;
  final Map<String, dynamic>? result;

  const WesiAiActionConfirmationResult({
    required this.ok,
    required this.tool,
    this.code,
    this.message,
    this.result,
  });
}

/// Explicit user-side confirmation transport for DESTRUCTIVE Wesi AI actions.
///
/// The model never receives a way to mint `confirmed=true`. It can only cause
/// the server to issue a short-lived confirmation ticket. This client then
/// sends that ticket back from the currently authenticated WesiOS session.
class WesiAiActionApi {
  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 20);

  const WesiAiActionApi();

  Future<WesiAiActionConfirmationResult> confirm(String confirmationId) async {
    final id = confirmationId.trim();
    if (!RegExp(r'^wai_confirm_[A-Za-z0-9_-]{16,180}$').hasMatch(id)) {
      return const WesiAiActionConfirmationResult(
        ok: false,
        tool: 'confirmed_action',
        code: 'CONFIRMATION_INVALID',
        message: 'Некорректное подтверждение Wesi AI',
      );
    }

    final session = SyncEndpoint.session;
    final token = session?['token'];
    final sessionId = SyncEndpoint.sessionId;
    if (!SyncEndpoint.isConnected ||
        token is! String ||
        token.isEmpty ||
        sessionId == null ||
        sessionId.isEmpty) {
      return const WesiAiActionConfirmationResult(
        ok: false,
        tool: 'confirmed_action',
        code: 'NOT_SIGNED_IN',
        message: 'Войдите в WesiOS, чтобы подтвердить действие',
      );
    }

    try {
      final base = Uri.parse(SyncEndpoint.url);
      final uri = base.replace(path: '/api/wesi/ai/action/confirm');
      final request = await _http.postUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, token);
      request.headers.set('X-WesiOS-Session', sessionId);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(<String, dynamic>{'confirmationId': id}));
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      final raw = await utf8.decoder.bind(response).join();
      Map<String, dynamic> body = const <String, dynamic>{};
      if (raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) body = Map<String, dynamic>.from(decoded);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return WesiAiActionConfirmationResult(
          ok: false,
          tool: 'confirmed_action',
          code: '${body['code'] ?? 'WAI_CONFIRMATION_FAILED'}',
          message: '${body['message'] ?? 'Не удалось подтвердить действие'}',
        );
      }
      final rawToolResult = body['toolResult'];
      if (rawToolResult is! Map) {
        return const WesiAiActionConfirmationResult(
          ok: false,
          tool: 'confirmed_action',
          code: 'WAI_CONFIRMATION_BAD_RESPONSE',
          message: 'Сервер вернул некорректный результат подтверждения',
        );
      }
      final toolResult = Map<String, dynamic>.from(rawToolResult);
      final rawResult = toolResult['result'];
      return WesiAiActionConfirmationResult(
        ok: toolResult['ok'] == true,
        tool: '${toolResult['tool'] ?? 'confirmed_action'}',
        code: toolResult['code'] == null ? null : '${toolResult['code']}',
        message:
            toolResult['message'] == null ? null : '${toolResult['message']}',
        result: rawResult is Map ? Map<String, dynamic>.from(rawResult) : null,
      );
    } on SocketException {
      return const WesiAiActionConfirmationResult(
        ok: false,
        tool: 'confirmed_action',
        code: 'NETWORK',
        message: 'Нет связи с сервером WesiOS',
      );
    } on HttpException {
      return const WesiAiActionConfirmationResult(
        ok: false,
        tool: 'confirmed_action',
        code: 'NETWORK',
        message: 'Ошибка связи с сервером WesiOS',
      );
    } on TimeoutException {
      return const WesiAiActionConfirmationResult(
        ok: false,
        tool: 'confirmed_action',
        code: 'NETWORK',
        message: 'Сервер не успел подтвердить действие',
      );
    } on FormatException {
      return const WesiAiActionConfirmationResult(
        ok: false,
        tool: 'confirmed_action',
        code: 'WAI_CONFIRMATION_BAD_RESPONSE',
        message: 'Сервер вернул повреждённый ответ подтверждения',
      );
    }
  }
}
