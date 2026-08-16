import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
  final List<Map<String, dynamic>> activity;

  const WesiAiReply({
    required this.answer,
    required this.requestId,
    this.blocks = const <WesiAiContentBlock>[],
    this.activity = const <Map<String, dynamic>>[],
  });
}

class WesiAiRequestCancellation {
  bool _cancelled = false;
  void Function()? _cancelTransport;

  bool get isCancelled => _cancelled;

  void bind(void Function() cancelTransport) {
    if (_cancelled) {
      cancelTransport();
      return;
    }
    _cancelTransport = cancelTransport;
  }

  void unbind() => _cancelTransport = null;

  bool cancel() {
    if (_cancelled) return false;
    _cancelled = true;
    final cancelTransport = _cancelTransport;
    _cancelTransport = null;
    cancelTransport?.call();
    return true;
  }
}

class WesiAiApi {
  static const int maxTransportHistoryMessages = 80;

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 30);

  const WesiAiApi();

  static List<Map<String, String>> transportHistory(
      List<WesiAiMessage> history) {
    final messages = history
        .where((m) =>
            m.kind == WesiAiMessageKind.text &&
            m.author != WesiAiMessageAuthor.system)
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
    parts.add(
        'Все чаты с этим projectId относятся к одному рабочему проекту. Учитывай этот контекст в текущем диалоге.');
    return parts.join('\n');
  }

  static String contextPackage(
    WesiAiProject? project, {
    required String conversationSummary,
    required Map<String, dynamic> taskState,
  }) {
    final parts = <String>[];
    final projectText = projectContext(project);
    if (projectText.isNotEmpty) parts.add(projectText);
    final cleanSummary = conversationSummary.trim();
    if (cleanSummary.isNotEmpty) {
      parts.add('[WESI_AI_ROLLING_SUMMARY]\n$cleanSummary');
    }
    if (taskState.isNotEmpty) {
      final encoded = jsonEncode(taskState);
      if (encoded.length <= 12000) {
        parts.add('[WESI_AI_TASK_STATE]\n$encoded');
      }
    }
    return parts.join('\n\n');
  }

  Future<WesiAiReply> send({
    required WesiAiConversation conversation,
    required WesiAiTier tier,
    required String message,
    required List<WesiAiMessage> history,
    required WesiAiMemorySnapshot memory,
    WesiAiProject? project,
    String conversationSummary = '',
    Map<String, dynamic> taskState = const <String, dynamic>{},
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
    void Function(String delta)? onDelta,
    void Function(Map<String, dynamic> event)? onActivity,
    WesiAiRequestCancellation? cancellation,
  }) async {
    WesiAiAttachment.validateBatch(attachments);
    final auth = _auth();
    final base = Uri.parse(SyncEndpoint.url);

    try {
      final transportAttachments = await _prepareTransportAttachments(
        base: base,
        auth: auth,
        attachments: attachments,
      );
      final uri = base.replace(path: '/api/wesi/ai/chat');
      final body = <String, dynamic>{
        'persona': conversation.persona.name,
        'tier': tier.name,
        'lobbyMode': conversation.lobbyMode.name,
        'message': message,
        'summary': conversationSummary.trim(),
        'projectContext': projectContext(project),
        if (taskState.isNotEmpty) 'taskState': taskState,
        'conversationId': conversation.id,
        if (conversation.projectId != null) 'projectId': conversation.projectId,
        'activeOrganizationId': OrganizationContext.currentOrganizationId,
        'memory': memory.toJson(),
        'messages': transportHistory(history),
        if (transportAttachments.isNotEmpty)
          'attachments': transportAttachments,
      };

      if (conversation.persona != WesiAiPersona.lobby) {
        final streamed = await _sendStream(
          base: base,
          auth: auth,
          body: body,
          onDelta: onDelta,
          onActivity: onActivity,
          cancellation: cancellation,
        );
        if (streamed != null) return streamed;
        onActivity?.call(<String, dynamic>{
          'type': 'activity',
          'kind': 'status',
          'label': 'Переключаюсь на основной маршрут Wesi AI',
          'detail':
              'Streaming transport недоступен; продолжаю через защищённый WesiOS Main.',
          'phase': 'done',
        });
      }

      onActivity?.call(<String, dynamic>{
        'type': 'activity',
        'kind': 'status',
        'label': 'Ожидаю проверенный ответ',
        'detail': 'Запрос отправлен в WesiOS Main.',
        'phase': 'start',
      });
      final request = await _http.postUrl(uri);
      cancellation?.bind(() => request.abort());
      _applyAuth(request, auth);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response =
          await request.close().timeout(const Duration(seconds: 185));
      final json = await _readJson(response);
      cancellation?.unbind();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = '${json['code'] ?? 'WAI_REQUEST_FAILED'}';
        throw WesiAiApiException(code, _messageFor(code));
      }
      onActivity?.call(<String, dynamic>{
        'type': 'activity',
        'kind': 'status',
        'label': 'Ответ проверен сервером',
        'phase': 'done',
      });
      return _replyFromPayload(json);
    } on WesiAiApiException {
      rethrow;
    } on SocketException {
      throw const WesiAiApiException('NETWORK', 'Нет связи с сервером WesiOS');
    } on HttpException {
      throw const WesiAiApiException(
          'NETWORK', 'Ошибка связи с сервером WesiOS');
    } on TimeoutException {
      throw const WesiAiApiException(
          'NETWORK', 'Wesi AI не успел обработать запрос');
    } on FormatException catch (e) {
      throw WesiAiApiException('WAI_ATTACHMENT_INVALID', e.message);
    }
  }

  Future<WesiAiReply?> _sendStream({
    required Uri base,
    required ({String token, String sessionId}) auth,
    required Map<String, dynamic> body,
    required void Function(String delta)? onDelta,
    required void Function(Map<String, dynamic> event)? onActivity,
    required WesiAiRequestCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled == true) {
      throw const WesiAiApiException(
          'WAI_CANCELLED', 'Запрос Wesi AI остановлен');
    }
    final uri = base.replace(path: '/api/wesi/ai/chat/stream');
    final request = await _http.postUrl(uri);
    _applyAuth(request, auth);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/x-ndjson');
    cancellation?.bind(() => request.abort());
    request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final json = await _readJson(response);
      cancellation?.unbind();
      final code = '${json['code'] ?? ''}';
      if (const <int>{404, 405, 501, 502}.contains(response.statusCode) &&
          (code.isEmpty || code == 'WAI_STREAM_GATEWAY_NOT_CONFIGURED')) {
        return null;
      }
      final resolved = code.isEmpty ? 'WAI_STREAM_FAILED' : code;
      throw WesiAiApiException(resolved, _messageFor(resolved));
    }

    final done = Completer<Map<String, dynamic>>();
    StreamSubscription<String>? subscription;
    subscription =
        utf8.decoder.bind(response).transform(const LineSplitter()).listen(
      (line) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || done.isCompleted) return;
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is! Map) return;
          final event = Map<String, dynamic>.from(decoded);
          switch ('${event['type'] ?? ''}') {
            case 'delta':
              final delta = '${event['text'] ?? ''}';
              if (delta.isNotEmpty) onDelta?.call(delta);
              break;
            case 'done':
              done.complete(event);
              break;
            case 'error':
              final code = '${event['code'] ?? 'WAI_STREAM_FAILED'}';
              done.completeError(WesiAiApiException(code, _messageFor(code)));
              break;
            case 'meta':
            case 'tool':
            case 'agent':
            case 'activity':
              onActivity?.call(event);
              break;
            case 'heartbeat':
              break;
          }
        } on FormatException {
          if (!done.isCompleted) {
            done.completeError(const WesiAiApiException(
              'WAI_STREAM_BAD_EVENT',
              'Wesi AI вернул повреждённый поток ответа',
            ));
          }
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      },
      onDone: () {
        if (!done.isCompleted) {
          done.completeError(const WesiAiApiException(
            'WAI_STREAM_EOF',
            'Поток Wesi AI завершился раньше ответа',
          ));
        }
      },
      cancelOnError: false,
    );
    cancellation?.bind(() {
      subscription?.cancel();
      if (!done.isCompleted) {
        done.completeError(const WesiAiApiException(
          'WAI_CANCELLED',
          'Запрос Wesi AI остановлен',
        ));
      }
    });
    try {
      final event = await done.future.timeout(const Duration(minutes: 7));
      return _replyFromPayload(event);
    } finally {
      cancellation?.unbind();
      await subscription.cancel();
    }
  }

  static WesiAiReply _replyFromPayload(Map<String, dynamic> json) {
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
      blocks:
          blocks.take(WesiAiContentParser.maxBlocks).toList(growable: false),
      activity: toolActivityFromResults(json['toolResults']),
    );
  }

  static String toolResultDetail(Map<dynamic, dynamic> raw) {
    final code = '${raw['code'] ?? ''}'.trim();
    final message = '${raw['message'] ?? ''}'.trim();
    if (code.isEmpty) return message;
    if (message.isEmpty || message == code) return code;
    return '$code · $message';
  }

  static List<Map<String, dynamic>> toolActivityFromResults(dynamic raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    final result = <Map<String, dynamic>>[];
    for (var index = 0; index < raw.length && index < 80; index++) {
      final item = raw[index];
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final payloadRaw = map['result'];
      final payload = payloadRaw is Map
          ? Map<String, dynamic>.from(payloadRaw)
          : const <String, dynamic>{};
      int count(Object? value) {
        final parsed =
            value is num ? value.toInt() : int.tryParse('$value') ?? 0;
        return parsed < 0 ? 0 : parsed;
      }

      final tool = '${map['tool'] ?? map['name'] ?? ''}'.trim();
      final detail = toolResultDetail(map);
      final filesRaw = payload['files'] ?? map['files'];
      final files = filesRaw is List
          ? filesRaw.take(40).map((value) => '$value').toList(growable: false)
          : const <String>[];
      result.add(<String, dynamic>{
        'id': 'tool_result_$index',
        'kind': 'tool',
        'sourceName': tool,
        'label': tool.isEmpty ? 'Инструмент' : 'Инструмент · $tool',
        'status': 'result',
        'additions': count(payload['additions'] ?? map['additions']),
        'deletions': count(payload['deletions'] ?? map['deletions']),
        if (files.isNotEmpty) 'files': files,
        if (detail.isNotEmpty) 'detail': detail,
      });
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> _prepareTransportAttachments({
    required Uri base,
    required ({String token, String sessionId}) auth,
    required List<WesiAiAttachment> attachments,
  }) async {
    if (attachments.isEmpty) return const <Map<String, dynamic>>[];
    if (!WesiAiAttachment.requiresStagedUpload(attachments)) {
      final result = <Map<String, dynamic>>[];
      for (final attachment in attachments) {
        result.add(await attachment.toInlineTransportJson());
      }
      return result;
    }

    // Если batch уже вышел за inline envelope, staging используем для всего
    // batch. Так обычный chat JSON остаётся маленьким и предсказуемым.
    final result = <Map<String, dynamic>>[];
    for (final attachment in attachments) {
      result.add(await _stageAttachment(base, auth, attachment));
    }
    return result;
  }

  Future<Map<String, dynamic>> _stageAttachment(
    Uri base,
    ({String token, String sessionId}) auth,
    WesiAiAttachment attachment,
  ) async {
    String? uploadId;
    try {
      final startUri = base.replace(path: '/api/wesi/ai/uploads');
      final startRequest = await _http.postUrl(startUri);
      _applyAuth(startRequest, auth);
      startRequest.headers.contentType = ContentType.json;
      startRequest.write(jsonEncode(<String, dynamic>{
        'name': attachment.name,
        'mimeType': attachment.mimeType,
        'byteSize': attachment.byteSize,
      }));
      final startResponse =
          await startRequest.close().timeout(const Duration(seconds: 45));
      final startJson = await _readJson(startResponse);
      _throwForUploadResponse(startResponse.statusCode, startJson);
      uploadId = '${startJson['uploadId'] ?? ''}'.trim();
      final chunkSize = int.tryParse('${startJson['chunkSize'] ?? ''}') ??
          WesiAiAttachment.stagedChunkBytes;
      final chunkCount = int.tryParse('${startJson['chunkCount'] ?? ''}') ??
          attachment.chunkCount;
      if (!RegExp(r'^[A-Za-z0-9_-]{20,96}$').hasMatch(uploadId) ||
          chunkSize <= 0 ||
          chunkSize > 2 * 1024 * 1024 ||
          chunkCount <= 0 ||
          chunkCount > 1024) {
        throw const WesiAiApiException('WAI_UPLOAD_BAD_RESPONSE',
            'Сервер вернул некорректную сессию загрузки');
      }

      for (var index = 0; index < chunkCount; index++) {
        final offset = index * chunkSize;
        final expected = math.min(chunkSize, attachment.byteSize - offset);
        if (expected <= 0) {
          throw const WesiAiApiException(
              'WAI_UPLOAD_BAD_RESPONSE', 'Некорректный план загрузки файла');
        }
        final bytes = await attachment.readChunk(offset, expected);
        if (bytes.lengthInBytes != expected) {
          throw const WesiAiApiException(
              'WAI_UPLOAD_FILE_CHANGED', 'Файл изменился во время загрузки');
        }
        final chunkUri =
            base.replace(path: '/api/wesi/ai/uploads/$uploadId/chunks/$index');
        final chunkRequest = await _http.putUrl(chunkUri);
        _applyAuth(chunkRequest, auth);
        chunkRequest.headers.contentType = ContentType.binary;
        chunkRequest.contentLength = bytes.lengthInBytes;
        chunkRequest.add(bytes);
        final chunkResponse =
            await chunkRequest.close().timeout(const Duration(seconds: 75));
        final chunkJson = await _readJson(chunkResponse);
        _throwForUploadResponse(chunkResponse.statusCode, chunkJson);
      }

      final completeUri =
          base.replace(path: '/api/wesi/ai/uploads/$uploadId/complete');
      final completeRequest = await _http.postUrl(completeUri);
      _applyAuth(completeRequest, auth);
      completeRequest.headers.contentType = ContentType.json;
      completeRequest.write('{}');
      final completeResponse =
          await completeRequest.close().timeout(const Duration(seconds: 75));
      final completeJson = await _readJson(completeResponse);
      _throwForUploadResponse(completeResponse.statusCode, completeJson);
      final rawTransport = completeJson['transportAttachment'];
      if (rawTransport is! Map) {
        throw const WesiAiApiException(
            'WAI_UPLOAD_BAD_RESPONSE', 'Сервер не подтвердил загруженный файл');
      }
      final transport = Map<String, dynamic>.from(rawTransport);
      if ('${transport['dataBase64'] ?? ''}'.isEmpty ||
          '${transport['mimeType'] ?? ''}' != 'application/x-wesi-upload-ref') {
        throw const WesiAiApiException('WAI_UPLOAD_BAD_RESPONSE',
            'Сервер вернул некорректную ссылку на файл');
      }
      uploadId =
          null; // complete владеет lifecycle на Relay; cancel больше не нужен.
      return transport;
    } on WesiAiApiException {
      rethrow;
    } finally {
      final pendingId = uploadId;
      if (pendingId != null) {
        unawaited(_cancelUpload(base, auth, pendingId));
      }
    }
  }

  Future<void> _cancelUpload(
    Uri base,
    ({String token, String sessionId}) auth,
    String uploadId,
  ) async {
    try {
      final uri = base.replace(path: '/api/wesi/ai/uploads/$uploadId');
      final request = await _http.deleteUrl(uri);
      _applyAuth(request, auth);
      final response =
          await request.close().timeout(const Duration(seconds: 12));
      await response.drain<void>();
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> _readJson(
      HttpClientResponse response) async {
    final raw = await utf8.decoder.bind(response).join();
    if (raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  static void _throwForUploadResponse(int status, Map<String, dynamic> json) {
    if (status >= 200 && status < 300 && json['ok'] != false) return;
    final code = '${json['code'] ?? 'WAI_UPLOAD_FAILED'}';
    throw WesiAiApiException(code, _messageFor(code));
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
      final mediaRequest =
          _sanitizeLocalMediaRequest(Map<String, dynamic>.from(requestRaw));
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

  static Map<String, dynamic>? _sanitizeLocalMediaRequest(
      Map<String, dynamic> raw) {
    final type = '${raw['mediaType'] ?? ''}'.trim().toLowerCase();
    if (!const {'image', 'music', 'video'}.contains(type)) return null;
    final prompt = '${raw['prompt'] ?? ''}'.trim();
    if (prompt.isEmpty || prompt.length > 12000) return null;
    final titleRaw = '${raw['title'] ?? ''}'.trim();
    final title =
        titleRaw.length <= 240 ? titleRaw : titleRaw.substring(0, 240);
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
      final response =
          await request.close().timeout(const Duration(seconds: 40));
      final raw = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          raw.isEmpty) return null;
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
          'NOT_SIGNED_IN', 'Войдите в WesiOS, чтобы использовать Wesi AI');
    }
    return (token: token, sessionId: sessionId);
  }

  static void _applyAuth(
      HttpClientRequest request, ({String token, String sessionId}) auth) {
    request.headers.set(HttpHeaders.authorizationHeader, auth.token);
    request.headers.set('X-WesiOS-Session', auth.sessionId);
  }

  static String _messageFor(String code) => switch (code) {
        'WAI_RELAY_NOT_CONFIGURED' =>
          'Wesi AI ещё не подключён к серверу моделей',
        'WAI_PERSONA_ENGINE_NOT_READY' =>
          'Профиль Wesi AI ещё не готов на сервере',
        'WAI_RELAY_UNAVAILABLE' => 'Сервис Wesi AI временно недоступен',
        'WAI_RELAY_BAD_RESPONSE' => 'Сервис Wesi AI вернул ошибку',
        'WAI_STREAM_FAILED' ||
        'WAI_STREAM_RELAY_REJECTED' ||
        'WAI_STREAM_MAIN_REJECTED' =>
          'Не удалось открыть поток Wesi AI',
        'WAI_STREAM_BAD_EVENT' ||
        'WAI_STREAM_EOF' ||
        'WAI_STREAM_RELAY_EOF' =>
          'Поток Wesi AI оборвался',
        'WAI_CANCELLED' => 'Запрос Wesi AI остановлен',
        'WAI_EMPTY_RESPONSE' => 'Wesi AI вернул пустой ответ',
        'WAI_ATTACHMENT_COUNT' => 'Можно прикрепить не больше 4 файлов',
        'WAI_ATTACHMENT_TOO_LARGE' => 'Один из файлов слишком большой',
        'WAI_ATTACHMENTS_TOO_LARGE' =>
          'Суммарный размер вложений слишком большой',
        'WAI_ATTACHMENT_BAD_BASE64' ||
        'WAI_ATTACHMENT_INVALID' ||
        'WAI_ATTACHMENT_SIZE_MISMATCH' =>
          'Не удалось прочитать вложение',
        'WAI_ATTACHMENT_PROVIDER_REJECTED' =>
          'Модель не смогла обработать этот формат файла',
        'WAI_UPLOAD_TOO_LARGE' => 'Файл слишком большой для поэтапной загрузки',
        'WAI_UPLOAD_BATCH_TOO_LARGE' =>
          'Суммарный размер файлов слишком большой',
        'WAI_UPLOAD_BAD_CHUNK' ||
        'WAI_UPLOAD_CHUNK_MISMATCH' =>
          'Не удалось передать часть файла',
        'WAI_UPLOAD_EXPIRED' =>
          'Сессия загрузки файла истекла. Отправьте сообщение ещё раз',
        'WAI_UPLOAD_FILE_CHANGED' =>
          'Файл изменился во время загрузки. Прикрепите его заново',
        'WAI_UPLOAD_BAD_RESPONSE' =>
          'Сервер вернул некорректный ответ при загрузке файла',
        'WAI_UPLOAD_FAILED' => 'Не удалось загрузить файл',
        _ => 'Не удалось получить ответ Wesi AI',
      };
}
