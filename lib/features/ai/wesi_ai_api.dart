import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/sync/sync_endpoint.dart';
import '../organizations/services/organization_context.dart';
import 'models/wesi_ai_chat_models.dart';
import 'models/wesi_ai_content_blocks.dart';
import 'models/wesi_ai_emotions.dart';
import 'models/wesi_ai_limits.dart';

class WesiAiApiException implements Exception {
  final String code;
  final String message;
  const WesiAiApiException(this.code, this.message);
  @override
  String toString() => message;
}

class WesiAiReply {
  final String answer;
  final String requestId;
  final List<WesiAiContentBlock> blocks;
  final Map<String, dynamic> route;
  final WesiAiEmotionSnapshot? emotions;

  const WesiAiReply({
    required this.answer,
    required this.requestId,
    this.blocks = const <WesiAiContentBlock>[],
    this.route = const <String, dynamic>{},
    this.emotions,
  });
}

class WesiAiContextCompaction {
  final String summary;
  final int compactedCount;

  const WesiAiContextCompaction({
    required this.summary,
    required this.compactedCount,
  });
}

class WesiAiApi {
  static const int maxTransportHistoryMessages = 80;

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 30);

  const WesiAiApi();

  static List<Map<String, String>> transportHistory(
    List<WesiAiMessage> history, {
    int skip = 0,
  }) {
    final messages = history
        .where((m) =>
            m.kind == WesiAiMessageKind.text &&
            m.author != WesiAiMessageAuthor.system &&
            m.author != WesiAiMessageAuthor.tool)
        .map((m) => {'author': m.author.name, 'text': m.text})
        .toList(growable: false);
    final start = skip.clamp(0, messages.length);
    final visible = messages.sublist(start);
    if (visible.length <= maxTransportHistoryMessages) return visible;
    return visible.sublist(visible.length - maxTransportHistoryMessages);
  }

  Future<WesiAiContextCompaction> compactContext({
    required WesiAiConversation conversation,
    required List<WesiAiMessage> messages,
    required int compactedCount,
  }) async {
    final auth = _auth();
    final base = Uri.parse(SyncEndpoint.url);
    final uri = base.replace(path: '/api/wesi/ai/context/compact');
    final body = <String, dynamic>{
      'conversationId': conversation.id,
      'persona': conversation.persona.name,
      'existingSummary': conversation.contextSummary,
      'alreadyCompactedCount': compactedCount,
      'messages': transportHistory(messages, skip: compactedCount),
    };

    try {
      final request = await _http.postUrl(uri);
      _applyAuth(request, auth);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 90));
      final raw = await utf8.decoder.bind(response).join();
      final decoded = raw.isEmpty ? const <String, dynamic>{} : jsonDecode(raw);
      final json = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : const <String, dynamic>{};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = '${json['code'] ?? 'WAI_CONTEXT_COMPACTION_FAILED'}';
        throw WesiAiApiException(code, _messageFor(code));
      }
      final summary = '${json['summary'] ?? ''}'.trim();
      final count = json['compactedCount'] is num
          ? (json['compactedCount'] as num).toInt()
          : 0;
      if (summary.isEmpty || count <= 0) {
        throw const WesiAiApiException(
          'WAI_CONTEXT_COMPACTION_FAILED',
          'Не удалось оптимизировать контекст диалога',
        );
      }
      return WesiAiContextCompaction(
        summary: summary,
        compactedCount: count,
      );
    } on WesiAiApiException {
      rethrow;
    } on SocketException {
      throw const WesiAiApiException('NETWORK', 'Нет связи с сервером WesiOS');
    } on HttpException {
      throw const WesiAiApiException('NETWORK', 'Ошибка связи с сервером WesiOS');
    } on TimeoutException {
      throw const WesiAiApiException(
        'NETWORK',
        'Оптимизация контекста не успела завершиться',
      );
    } on FormatException {
      throw const WesiAiApiException(
        'NOT_WESIOS',
        'Сервер вернул некорректный результат оптимизации контекста',
      );
    }
  }

  Future<WesiAiReply> send({
    required WesiAiConversation conversation,
    required WesiAiTier tier,
    required String message,
    required List<WesiAiMessage> history,
    required WesiAiMemorySnapshot memory,
    required WesiAiEmotionSnapshot emotions,
  }) async {
    final auth = _auth();
    final base = Uri.parse(SyncEndpoint.url);
    final uri = base.replace(path: '/api/wesi/ai/chat');
    final body = <String, dynamic>{
      'persona': conversation.persona.name,
      'tier': tier.name,
      'lobbyMode': conversation.lobbyMode.name,
      'message': message,
      'summary': conversation.contextSummary,
      'conversationId': conversation.id,
      'activeOrganizationId': OrganizationContext.currentOrganizationId,
      'memory': memory.toJson(),
      'emotions': emotions.toJson(),
      'messages': transportHistory(
        history,
        skip: conversation.contextCompactedMessageCount,
      ),
    };

    try {
      final request = await _http.postUrl(uri);
      _applyAuth(request, auth);
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
      final parsed = WesiAiContentParser.parse(
        answer: '${json['answer'] ?? ''}'.trim(),
        toolResults: json['toolResults'],
      );
      if (parsed.text.isEmpty && parsed.blocks.isEmpty) {
        throw const WesiAiApiException(
          'WAI_EMPTY_RESPONSE',
          'Wesi AI вернул пустой ответ',
        );
      }
      return WesiAiReply(
        answer: parsed.text,
        requestId: '${json['requestId'] ?? ''}',
        blocks: parsed.blocks,
        route: json['route'] is Map
            ? Map<String, dynamic>.from(json['route'] as Map)
            : const <String, dynamic>{},
        emotions: json['emotions'] is Map
            ? WesiAiEmotionSnapshot.fromJson(json['emotions'])
            : null,
      );
    } on WesiAiApiException {
      rethrow;
    } on SocketException {
      throw const WesiAiApiException('NETWORK', 'Нет связи с сервером WesiOS');
    } on HttpException {
      throw const WesiAiApiException('NETWORK', 'Ошибка связи с сервером WesiOS');
    } on TimeoutException {
      throw const WesiAiApiException('NETWORK', 'Wesi AI не успел ответить вовремя');
    } on FormatException {
      throw const WesiAiApiException(
        'NOT_WESIOS',
        'Сервер WesiOS вернул некорректный ответ',
      );
    }
  }

  Future<WesiAiLimits> limits() async {
    final auth = _auth();
    final base = Uri.parse(SyncEndpoint.url);
    final uri = base.replace(path: '/api/wesi/ai/limits');
    try {
      final request = await _http.getUrl(uri);
      _applyAuth(request, auth);
      final response = await request.close().timeout(const Duration(seconds: 35));
      final raw = await utf8.decoder.bind(response).join();
      if (raw.isEmpty) return const WesiAiLimits({});
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const WesiAiLimits({});
      final json = Map<String, dynamic>.from(decoded);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = '${json['code'] ?? 'WAI_REQUEST_FAILED'}';
        throw WesiAiApiException(code, _messageFor(code));
      }
      return WesiAiLimits.fromJson(json['limits']);
    } on WesiAiApiException {
      rethrow;
    } on SocketException {
      throw const WesiAiApiException('NETWORK', 'Нет связи с сервером WesiOS');
    } on HttpException {
      throw const WesiAiApiException('NETWORK', 'Ошибка связи с сервером WesiOS');
    } on TimeoutException {
      throw const WesiAiApiException('NETWORK', 'Не удалось получить лимиты вовремя');
    } on FormatException {
      throw const WesiAiApiException(
        'NOT_WESIOS',
        'Сервер WesiOS вернул некорректные лимиты',
      );
    }
  }

  Future<WesiAiContentBlock?> mediaJob(String rawStatusUrl) async {
    final base = Uri.parse(SyncEndpoint.url);
    final uri = Uri.tryParse(rawStatusUrl.trim());
    if (uri == null ||
        uri.scheme != base.scheme ||
        uri.host != base.host ||
        uri.port != base.port ||
        !uri.path.startsWith('/api/wesi/ai/media/jobs/')) {
      return null;
    }
    final auth = _auth();
    try {
      final request = await _http.getUrl(uri);
      _applyAuth(request, auth);
      final response = await request.close().timeout(const Duration(seconds: 40));
      final raw = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300 || raw.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['ok'] != true) return null;
      return WesiAiContentBlock.fromJson(map['contentBlock']);
    } on SocketException {
      return null;
    } on HttpException {
      return null;
    } on TimeoutException {
      return null;
    } on FormatException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static ({String token, String sessionId}) _auth() {
    final session = SyncEndpoint.session;
    final token = session?['token'];
    final sessionId = SyncEndpoint.sessionId;
    if (!SyncEndpoint.isConnected ||
        token is! String ||
        token.isEmpty ||
        sessionId == null) {
      throw const WesiAiApiException(
        'NOT_SIGNED_IN',
        'Войдите в WesiOS, чтобы использовать Wesi AI',
      );
    }
    return (token: token, sessionId: sessionId);
  }

  static void _applyAuth(
    HttpClientRequest request,
    ({String token, String sessionId}) auth,
  ) {
    request.headers.set(HttpHeaders.authorizationHeader, auth.token);
    request.headers.set('X-WesiOS-Session', auth.sessionId);
  }

  static String _messageFor(String code) => switch (code) {
        'WAI_RELAY_NOT_CONFIGURED' =>
          'Wesi AI ещё не подключён к серверу моделей',
        'WAI_PERSONA_ENGINE_NOT_READY' =>
          'Профиль Wesi AI ещё не готов на сервере',
        'WAI_PROVIDER_NOT_CONFIGURED' =>
          'Выбранный провайдер Wesi AI ещё не настроен',
        'WAI_PROVIDER_RATE_LIMIT' => 'Лимит выбранной модели временно исчерпан',
        'WAI_CONTEXT_COMPACTION_FAILED' =>
          'Не удалось оптимизировать контекст диалога',
        'WAI_RELAY_UNAVAILABLE' => 'Сервис Wesi AI временно недоступен',
        'WAI_RELAY_BAD_RESPONSE' => 'Сервис Wesi AI вернул ошибку',
        'WAI_EMPTY_RESPONSE' => 'Wesi AI вернул пустой ответ',
        _ => 'Не удалось получить ответ Wesi AI',
      };
}
