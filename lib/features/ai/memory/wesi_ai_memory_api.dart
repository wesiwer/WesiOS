import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/sync/sync_endpoint.dart';
import '../models/wesi_ai_chat_models.dart';
import '../wesi_ai_api.dart';
import 'wesi_ai_memory_models.dart';

class WesiAiMemoryApi {
  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 30);

  const WesiAiMemoryApi();

  Future<WesiAiMemoryProcessResult> process({
    required WesiAiConversation conversation,
    required List<WesiAiMessage> recentMessages,
    required String previousSummary,
    required Map<String, dynamic> taskState,
    required WesiAiMemorySnapshot memory,
    WesiAiProject? project,
  }) async {
    final auth = _auth();
    final base = Uri.parse(SyncEndpoint.url);
    final uri = base.replace(path: '/api/wesi/ai/memory/process');
    final messages = recentMessages
        .where((message) =>
            message.kind == WesiAiMessageKind.text &&
            (message.author == WesiAiMessageAuthor.user ||
                message.author == WesiAiMessageAuthor.zane ||
                message.author == WesiAiMessageAuthor.nirvana))
        .toList(growable: false);
    final bounded = messages.length <= 24
        ? messages
        : messages.sublist(messages.length - 24);
    final body = <String, dynamic>{
      'persona': conversation.persona.name,
      'conversationId': conversation.id,
      if (conversation.projectId != null) 'projectId': conversation.projectId,
      'previousSummary': previousSummary,
      'taskState': taskState,
      'recentMessages': bounded
          .map((message) => <String, dynamic>{
                'author': message.author.name,
                'text': message.text.length <= 8000
                    ? message.text
                    : message.text.substring(message.text.length - 8000),
              })
          .toList(growable: false),
      'memory': memory.toJson(),
      if (project != null)
        'project': <String, dynamic>{
          'id': project.id,
          'title': project.title,
          'description': project.description,
          'instructions': project.instructions,
        },
    };

    try {
      final request = await _http.postUrl(uri);
      _applyAuth(request, auth);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response =
          await request.close().timeout(const Duration(seconds: 95));
      final raw = await utf8.decoder.bind(response).join();
      Map<String, dynamic> json = <String, dynamic>{};
      if (raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) json = Map<String, dynamic>.from(decoded);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = '${json['code'] ?? 'WAI_MEMORY_FAILED'}';
        throw WesiAiApiException(code, _messageFor(code));
      }
      if (json['ok'] != true) {
        throw const WesiAiApiException(
          'WAI_MEMORY_BAD_RESPONSE',
          'Wesi AI не смог обновить память',
        );
      }
      final summary = '${json['summary'] ?? ''}'.trim();
      final taskRaw = json['taskState'];
      final task = taskRaw is Map
          ? Map<String, dynamic>.from(taskRaw)
          : <String, dynamic>{};
      final candidates = <WesiAiMemoryCandidate>[];
      final rawMemories = json['memories'];
      if (rawMemories is List) {
        for (final rawMemory in rawMemories.take(8)) {
          if (rawMemory is! Map) continue;
          final map = Map<String, dynamic>.from(rawMemory);
          WesiAiMemoryScope? scope;
          final rawScope = '${map['scope'] ?? ''}';
          for (final candidate in WesiAiMemoryScope.values) {
            if (candidate.name == rawScope) {
              scope = candidate;
              break;
            }
          }
          final text = '${map['text'] ?? ''}'.trim();
          final importanceRaw = map['importance'];
          if (scope == null || text.isEmpty || text.length > 2000) continue;
          candidates.add(WesiAiMemoryCandidate(
            scope: scope,
            text: text,
            importance: importanceRaw is num
                ? importanceRaw.toDouble().clamp(0.0, 1.0).toDouble()
                : 0.5,
          ));
        }
      }
      return WesiAiMemoryProcessResult(
        summary: summary,
        taskState: task,
        memories: List<WesiAiMemoryCandidate>.unmodifiable(candidates),
      );
    } on WesiAiApiException {
      rethrow;
    } on SocketException {
      throw const WesiAiApiException(
        'NETWORK',
        'Нет связи с сервером WesiOS',
      );
    } on HttpException {
      throw const WesiAiApiException(
        'NETWORK',
        'Ошибка связи с сервером WesiOS',
      );
    } on TimeoutException {
      throw const WesiAiApiException(
        'WAI_MEMORY_TIMEOUT',
        'Обновление памяти Wesi AI не успело завершиться',
      );
    } on FormatException {
      throw const WesiAiApiException(
        'WAI_MEMORY_BAD_RESPONSE',
        'Wesi AI вернул повреждённое обновление памяти',
      );
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
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${auth.token}');
    request.headers.set('X-WesiOS-Session', auth.sessionId);
  }

  static String _messageFor(String code) => switch (code) {
        'WAI_RELAY_NOT_CONFIGURED' || 'WAI_RELAY_UNAVAILABLE' =>
          'Сервис памяти Wesi AI временно недоступен',
        'WAI_MEMORY_BAD_RESPONSE' => 'Wesi AI не смог обновить память',
        'WAI_MEMORY_TIMEOUT' => 'Обновление памяти Wesi AI заняло слишком много времени',
        'NOT_SIGNED_IN' => 'Войдите в WesiOS, чтобы использовать Wesi AI',
        _ => 'Не удалось обновить память Wesi AI',
      };
}
