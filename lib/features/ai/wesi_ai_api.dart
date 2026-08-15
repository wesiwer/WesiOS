import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/sync/sync_endpoint.dart';
import '../organizations/services/organization_context.dart';
import 'models/wesi_ai_attachment.dart';
import 'models/wesi_ai_chat_models.dart';
import 'models/wesi_ai_content_blocks.dart';

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

  const WesiAiReply({
    required this.answer,
    required this.requestId,
    this.blocks = const <WesiAiContentBlock>[],
  });
}

class WesiAiApi {
  static const int maxTransportHistoryMessages = 80;

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 30);

  const WesiAiApi();

  static List<Map<String, String>> transportHistory(List<WesiAiMessage> history) {
    final messages = history
        .where((m) => m.kind == WesiAiMessageKind.text && m.author != WesiAiMessageAuthor.system)
        .map((m) => {'author': m.author.name, 'text': m.text})
        .toList(growable: false);
    if (messages.length <= maxTransportHistoryMessages) return messages;
    return messages.sublist(messages.length - maxTransportHistoryMessages);
  }

  static String projectContext(WesiAiProject? project) {
    if (project == null) return '';
    final parts = <String>['[WESI_AI_PROJECT]', 'Название: ${project.title}'];
    if (project.description.trim().isNotEmpty) {
      parts.add('Описание: ${project.description.trim()}');
    }
    if (project.instructions.trim().isNotEmpty) {
      parts.add('Инструкции проекта:\n${project.instructions.trim()}');
    }
    parts.add('Все чаты с этим projectId относятся к одному рабочему проекту. Учитывай этот контекст в текущем диалоге.');
    return parts.join('\n');
  }

  Future<WesiAiReply> send({
    required WesiAiConversation conversation,
    required WesiAiTier tier,
    required String message,
    required List<WesiAiMessage> history,
    required WesiAiMemorySnapshot memory,
    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
  }) async {
    WesiAiAttachment.validateBatch(attachments);
    final auth = _auth();
    final base = Uri.parse(SyncEndpoint.url);
    final uri = base.replace(path: '/api/wesi/ai/chat');
    final body = <String, dynamic>{
      'persona': conversation.persona.name,
      'tier': tier.name,
      'lobbyMode': conversation.lobbyMode.name,
      'message': message,
      'summary': projectContext(project),
      'conversationId': conversation.id,
      if (conversation.projectId != null) 'projectId': conversation.projectId,
      'activeOrganizationId': OrganizationContext.currentOrganizationId,
      'memory': memory.toJson(),
      'messages': transportHistory(history),
      if (attachments.isNotEmpty)
        'attachments': attachments
            .map((attachment) => attachment.toTransportJson())
            .toList(growable: false),
    };

    try {
      final request = await _http.postUrl(uri);
      _applyAuth(request, auth);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 185));
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
      final blocks = <WesiAiContentBlock>[...parsed.blocks];
      blocks.addAll(_verifiedLocalMediaRequests(json['toolResults']));
      if (parsed.text.isEmpty && blocks.isEmpty) {
        throw const WesiAiApiException(
          'WAI_EMPTY_RESPONSE',
          'Wesi AI вернул пустой ответ',
        );
      }
      return WesiAiReply(
        answer: parsed.text,
        requestId: '${json['requestId'] ?? ''}',
        blocks: blocks.take(WesiAiContentParser.maxBlocks).toList(growable: false),
      );
    } on WesiAiApiException {
      rethrow;
    } on SocketException {
      throw const WesiAiApiException('NETWORK', 'Нет связи с сервером WesiOS');
    } on HttpException {
      throw const WesiAiApiException('NETWORK', 'Ошибка связи с сервером WesiOS');
    } on TimeoutException {
      throw const WesiAiApiException('NETWORK', 'Wesi AI не успел обработать вложение');
    } on FormatException catch (e) {
      throw WesiAiApiException('WAI_ATTACHMENT_INVALID', e.message);
    }
  }

  static List<WesiAiContentBlock> _verifiedLocalMediaRequests(Object? raw) {
    if (raw is! List) return const <WesiAiContentBlock>[];
    final blocks = <WesiAiContentBlock>[];
    for (final itemRaw in raw) {
      if (itemRaw is! Map) continue;
      final item = Map<String, dynamic>.from(itemRaw);
      if (item['verified'] != true || item['ok'] != true) continue;
      final resultRaw = item['result'];
      if (resultRaw is! Map) continue;
      final result = Map<String, dynamic>.from(resultRaw);
      final requestRaw = result['localMediaRequest'];
      if (requestRaw is! Map) continue;
      final mediaRequest = _sanitizeLocalMediaRequest(Map<String, dynamic>.from(requestRaw));
      if (mediaRequest == null) continue;
      blocks.add(WesiAiContentBlock(
        type: WesiAiContentBlockType.media,
        data: <String, dynamic>{
          'mediaType': mediaRequest['mediaType'],
          'title': mediaRequest['title'],
          'prompt': mediaRequest['prompt'],
          'status': 'pending',
          'localRequest': mediaRequest,
        },
      ));
    }
    return blocks;
  }

  static Map<String, dynamic>? _sanitizeLocalMediaRequest(Map<String, dynamic> raw) {
    final type = '${raw['mediaType'] ?? ''}'.trim().toLowerCase();
    if (!const {'image', 'music', 'video'}.contains(type)) return null;
    final prompt = '${raw['prompt'] ?? ''}'.trim();
    if (prompt.isEmpty || prompt.length > 12000) return null;
    final titleRaw = '${raw['title'] ?? ''}'.trim();
    final title = titleRaw.length <= 240 ? titleRaw : titleRaw.substring(0, 240);
    final optionsRaw = raw['options'];
    final options = <String, dynamic>{};
    if (optionsRaw is Map) {
      for (final entry in optionsRaw.entries.take(12)) {
        final key = '${entry.key}'.trim();
        final value = entry.value;
        if (!RegExp(r'^[A-Za-z][A-Za-z0-9]{0,39}$').hasMatch(key)) continue;
        if (value is String && value.length <= 80) options[key] = value;
        if (value is num || value is bool) options[key] = value;
      }
    }
    return <String, dynamic>{
      'mediaType': type,
      'title': title,
      'prompt': prompt,
      'options': options,
    };
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
      if (response.statusCode < 200 || response.statusCode >= 300 || raw.isEmpty) return null;
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
    if (!SyncEndpoint.isConnected || token is! String || token.isEmpty || sessionId == null) {
      throw const WesiAiApiException('NOT_SIGNED_IN', 'Войдите в WesiOS, чтобы использовать Wesi AI');
    }
    return (token: token, sessionId: sessionId);
  }

  static void _applyAuth(HttpClientRequest request, ({String token, String sessionId}) auth) {
    request.headers.set(HttpHeaders.authorizationHeader, auth.token);
    request.headers.set('X-WesiOS-Session', auth.sessionId);
  }

  static String _messageFor(String code) => switch (code) {
        'WAI_RELAY_NOT_CONFIGURED' => 'Wesi AI ещё не подключён к серверу моделей',
        'WAI_PERSONA_ENGINE_NOT_READY' => 'Профиль Wesi AI ещё не готов на сервере',
        'WAI_RELAY_UNAVAILABLE' => 'Сервис Wesi AI временно недоступен',
        'WAI_RELAY_BAD_RESPONSE' => 'Сервис Wesi AI вернул ошибку',
        'WAI_EMPTY_RESPONSE' => 'Wesi AI вернул пустой ответ',
        'WAI_ATTACHMENT_COUNT' => 'Можно прикрепить не больше 4 файлов',
        'WAI_ATTACHMENT_TOO_LARGE' => 'Один из файлов слишком большой',
        'WAI_ATTACHMENTS_TOO_LARGE' => 'Суммарный размер вложений слишком большой',
        'WAI_ATTACHMENT_BAD_BASE64' || 'WAI_ATTACHMENT_INVALID' || 'WAI_ATTACHMENT_SIZE_MISMATCH' =>
          'Не удалось прочитать вложение',
        'WAI_ATTACHMENT_PROVIDER_REJECTED' => 'Модель не смогла обработать этот формат файла',
        _ => 'Не удалось получить ответ Wesi AI',
      };
}
