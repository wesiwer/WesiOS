import 'dart:convert';
import 'dart:io';

import '../../core/sync/sync_endpoint.dart';
import '../organizations/services/organization_context.dart';
import 'models/wesi_ai_chat_models.dart';
import 'wesi_ai_api.dart';

class WesiAiLobbyApi extends WesiAiApi {
  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 30);

  const WesiAiLobbyApi();

  @override
  Future<WesiAiReply> send({
    required WesiAiConversation conversation,
    required WesiAiTier tier,
    required String message,
    required List<WesiAiMessage> history,
    required WesiAiMemorySnapshot memory,
  }) async {
    if (conversation.persona != WesiAiPersona.lobby) {
      return super.send(
        conversation: conversation,
        tier: tier,
        message: message,
        history: history,
        memory: memory,
      );
    }

    final session = SyncEndpoint.session;
    final token = session?['token'];
    final sessionId = SyncEndpoint.sessionId;
    if (!SyncEndpoint.isConnected || token is! String || token.isEmpty || sessionId == null) {
      throw const WesiAiApiException('NOT_SIGNED_IN', 'Войдите в WesiOS, чтобы использовать Wesi AI');
    }

    final base = Uri.parse(SyncEndpoint.url);
    final uri = base.replace(path: '/api/wesi/ai/lobby');
    final body = <String, dynamic>{
      'persona': WesiAiPersona.lobby.name,
      'tier': tier.name,
      'lobbyMode': conversation.lobbyMode.name,
      'message': message,
      'summary': '',
      'conversationId': conversation.id,
      'activeOrganizationId': OrganizationContext.currentOrganizationId,
      'memory': memory.toJson(),
      'messages': history
          .where((m) => m.kind == WesiAiMessageKind.text && m.author != WesiAiMessageAuthor.system)
          .map((m) => {'author': m.author.name, 'text': m.text})
          .toList(),
    };

    try {
      final request = await _http.postUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, token);
      request.headers.set('X-WesiOS-Session', sessionId);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 125));
      final raw = await utf8.decoder.bind(response).join();
      Map<String, dynamic> json = const {};
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) json = Map<String, dynamic>.from(decoded);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = '${json['code'] ?? 'WAI_REQUEST_FAILED'}';
        throw WesiAiApiException(code, _messageFor(code));
      }
      final answer = '${json['answer'] ?? ''}'.trim();
      if (answer.isEmpty) throw const WesiAiApiException('WAI_EMPTY_RESPONSE', 'Wesi AI вернул пустой ответ');
      return WesiAiReply(answer: answer, requestId: '${json['requestId'] ?? ''}');
    } on WesiAiApiException {
      rethrow;
    } on SocketException {
      throw const WesiAiApiException('NETWORK', 'Нет связи с сервером WesiOS');
    } on HttpException {
      throw const WesiAiApiException('NETWORK', 'Ошибка связи с сервером WesiOS');
    } on FormatException {
      throw const WesiAiApiException('NOT_WESIOS', 'Сервер WesiOS вернул некорректный ответ');
    }
  }

  static String _messageFor(String code) => switch (code) {
        'WAI_RELAY_NOT_CONFIGURED' => 'Wesi AI ещё не подключён к серверу моделей',
        'WAI_PERSONA_ENGINE_NOT_READY' => 'Профиль Wesi AI ещё не готов на сервере',
        'WAI_RELAY_UNAVAILABLE' => 'Сервис Wesi AI временно недоступен',
        'WAI_RELAY_BAD_RESPONSE' => 'Сервис Wesi AI вернул ошибку',
        'WAI_EMPTY_RESPONSE' => 'Wesi AI вернул пустой ответ',
        _ => 'Не удалось получить ответ Wesi AI',
      };
}
