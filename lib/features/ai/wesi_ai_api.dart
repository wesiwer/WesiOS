import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../../core/sync/sync_endpoint.dart';
import '../organizations/services/organization_context.dart';
import 'media_engines/wesi_media_local_request.dart';
import 'models/wesi_ai_attachment.dart';
import 'models/wesi_ai_chat_models.dart';
import 'models/wesi_ai_content_blocks.dart';

class WesiAiApiException implements Exception {
  final String code;
  final String message;
  final String requestId;
  final String stage;
  final String component;
  final String operation;
  final int? httpStatus;
  final String lastSuccess;
  final int? durationMs;
  final String detail;

  const WesiAiApiException(
    this.code,
    this.message, {
    this.requestId = '',
    this.stage = '',
    this.component = '',
    this.operation = '',
    this.httpStatus,
    this.lastSuccess = '',
    this.durationMs,
    this.detail = '',
  });

  factory WesiAiApiException.fromPayload(
    String fallbackCode,
    String fallbackMessage,
    Map<String, dynamic> payload, {
    int? httpStatus,
    String stage = '',
    String component = '',
    String operation = '',
    String lastSuccess = '',
    int? durationMs,
  }) {
    final raw = payload['diagnostic'];
    final diagnostic =
        raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    int? intValue(Object? value) =>
        value is num ? value.toInt() : int.tryParse('${value ?? ''}');
    final resolvedCode = '${payload['code'] ?? fallbackCode}'.trim();
    return WesiAiApiException(
      resolvedCode.isEmpty ? fallbackCode : resolvedCode,
      fallbackMessage,
      requestId:
          '${diagnostic['requestId'] ?? payload['requestId'] ?? ''}'.trim(),
      stage: '${diagnostic['stage'] ?? stage}'.trim(),
      component: '${diagnostic['component'] ?? component}'.trim(),
      operation: '${diagnostic['operation'] ?? operation}'.trim(),
      httpStatus: intValue(diagnostic['httpStatus']) ?? httpStatus,
      lastSuccess: '${diagnostic['lastSuccess'] ?? lastSuccess}'.trim(),
      durationMs: intValue(diagnostic['durationMs']) ?? durationMs,
      detail: '${diagnostic['detail'] ?? ''}'.trim(),
    );
  }

  Map<String, dynamic> get diagnostic => <String, dynamic>{
        'code': code,
        if (requestId.isNotEmpty) 'requestId': requestId,
        if (stage.isNotEmpty) 'stage': stage,
        if (component.isNotEmpty) 'component': component,
        if (operation.isNotEmpty) 'operation': operation,
        if (httpStatus != null) 'httpStatus': httpStatus,
        if (lastSuccess.isNotEmpty) 'lastSuccess': lastSuccess,
        if (durationMs != null) 'durationMs': durationMs,
        if (detail.isNotEmpty) 'detail': detail,
      };

  String get technicalDetails => <String>[
        if (stage.isNotEmpty) 'Этап: $stage',
        if (component.isNotEmpty) 'Компонент: $component',
        if (operation.isNotEmpty) 'Операция: $operation',
        'Код: $code',
        if (httpStatus != null) 'HTTP: $httpStatus',
        if (lastSuccess.isNotEmpty) 'Последний успешный этап: $lastSuccess',
        if (requestId.isNotEmpty) 'Request ID: $requestId',
        if (durationMs != null) 'Длительность: ${durationMs} мс',
        if (detail.isNotEmpty) 'Детали: $detail',
      ].join('\n');

  String get displayMessage =>
      '$message\n\nТехнические детали\n$technicalDetails';

  @override
  String toString() => displayMessage;
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
  static const int maxTransportHistoryMessageChars = 24000;
  static const int maxTransportHistoryTotalChars = 180000;
  static const String _historyTruncatedMarker =
      '\n...[WESI_AI_HISTORY_TRUNCATED]...\n';
  static const String streamBaseUrl = String.fromEnvironment(
    'WESI_AI_STREAM_BASE_URL',
    defaultValue: 'https://wesi-ai-178-236-247-194.nip.io',
  );

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 30);

  const WesiAiApi();

  static String _truncateHistoryText(String text, int limit) {
    if (text.length <= limit) return text;
    if (limit <= _historyTruncatedMarker.length) {
      return text.substring(text.length - limit);
    }
    final payload = limit - _historyTruncatedMarker.length;
    final head = (payload * 3) ~/ 5;
    final tail = payload - head;
    return '${text.substring(0, head)}$_historyTruncatedMarker${text.substring(text.length - tail)}';
  }

  static List<Map<String, String>> transportHistory(
      List<WesiAiMessage> history) {
    final eligible = history
        .where((message) =>
            message.kind == WesiAiMessageKind.text &&
            message.author != WesiAiMessageAuthor.system)
        .toList(growable: false);
    final newestFirst = <Map<String, String>>[];
    var totalChars = 0;
    for (var index = eligible.length - 1;
        index >= 0 && newestFirst.length < maxTransportHistoryMessages;
        index--) {
      final message = eligible[index];
      if (message.text.isEmpty) continue;
      final remaining = maxTransportHistoryTotalChars - totalChars;
      if (remaining <= _historyTruncatedMarker.length) break;
      final limit = math.min(maxTransportHistoryMessageChars, remaining);
      final text = _truncateHistoryText(message.text, limit);
      if (text.isEmpty) continue;
      newestFirst.add(<String, String>{
        'author': message.author.name,
        'text': text,
      });
      totalChars += text.length;
    }
    return newestFirst.reversed.toList(growable: false);
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
    bool thinkingMode = true,
  }) async {
    WesiAiAttachment.validateBatch(attachments);
    final auth = _auth();
    final base = Uri.parse(SyncEndpoint.url);
    var activeOrganizationId = OrganizationContext.currentOrganizationId;
    try {
      activeOrganizationId =
          (await OrganizationContext.currentOrganization()).id;
    } catch (_) {
      // The server still enforces organization access. Keep Wesi AI usable
      // during incomplete local bootstrap, but always prefer the initialized
      // organization selected by the user when it is available.
    }

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
        'activeOrganizationId': activeOrganizationId,
        'memory': memory.toJson(),
        'messages': transportHistory(history),
        if (transportAttachments.isNotEmpty)
          'attachments': transportAttachments,
        'thinkingMode': thinkingMode,
      };

      if (thinkingMode && conversation.persona != WesiAiPersona.lobby) {
        try {
          final streamed = await _sendStream(
            base: base,
            auth: auth,
            body: body,
            onDelta: onDelta,
            onActivity: onActivity,
            cancellation: cancellation,
          );
          if (streamed != null) return streamed;
        } on SocketException catch (error) {
          _emitStreamFallback(onActivity, 'STREAM_SOCKET', error.message);
        } on HttpException catch (error) {
          _emitStreamFallback(onActivity, 'STREAM_HTTP', error.message);
        } on TimeoutException catch (error) {
          _emitStreamFallback(onActivity, 'STREAM_TIMEOUT', '$error');
        }
      }

      final request = await _http.postUrl(uri);
      cancellation?.bind(() => request.abort());
      _applyAuth(request, auth);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(jsonEncode(body));
      late HttpClientResponse response;
      late Map<String, dynamic> json;
      try {
        response = await request.close().timeout(const Duration(seconds: 185));
        json = await readJsonResponse(
          response,
          stage: 'MAIN',
          component: 'WesiOS Main',
          operation: 'chat',
          lastSuccess: 'MAIN_RESPONSE_RECEIVED',
        );
      } finally {
        cancellation?.unbind();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code = '${json['code'] ?? 'WAI_REQUEST_FAILED'}';
        throw WesiAiApiException.fromPayload(
          code,
          _messageFor(code),
          json,
          httpStatus: response.statusCode,
          stage: response.statusCode == 401 || response.statusCode == 403
              ? 'AUTH'
              : 'MAIN',
          component: response.statusCode == 401 || response.statusCode == 403
              ? 'WesiOS Auth'
              : 'WesiOS Main',
          operation: 'chat',
          lastSuccess: 'CLIENT',
        );
      }
      return _replyFromPayload(json);
    } on WesiAiApiException {
      rethrow;
    } on SocketException catch (error) {
      throw WesiAiApiException('NETWORK_SOCKET', 'Нет связи с сервером WesiOS',
          stage: 'CLIENT_TRANSPORT',
          component: 'WesiAiApi',
          operation: 'chat',
          lastSuccess: 'REQUEST_PREPARED',
          detail: error.message);
    } on HttpException catch (error) {
      throw WesiAiApiException('NETWORK_HTTP', 'Ошибка связи с сервером WesiOS',
          stage: 'CLIENT_TRANSPORT',
          component: 'WesiAiApi',
          operation: 'chat',
          lastSuccess: 'REQUEST_PREPARED',
          detail: error.message);
    } on TimeoutException catch (error) {
      throw WesiAiApiException(
          'NETWORK_TIMEOUT', 'Wesi AI не успел обработать запрос',
          stage: 'CLIENT_TRANSPORT',
          component: 'WesiAiApi',
          operation: 'chat',
          lastSuccess: 'REQUEST_SENT',
          detail: '$error');
    } on FormatException catch (e) {
      throw WesiAiApiException('WAI_ATTACHMENT_INVALID', e.message);
    }
  }

  static void _emitStreamFallback(
    void Function(Map<String, dynamic> event)? onActivity,
    String code,
    String detail,
  ) {
    final cleanDetail = detail.trim();
    onActivity?.call(<String, dynamic>{
      'type': 'activity',
      'kind': 'status',
      'phase': 'fallback',
      'label': 'Streaming недоступен — переключаюсь на WesiOS Main',
      'detail':
          'Этап: STREAM_GATEWAY · Компонент: Streaming edge · Код: $code${cleanDetail.isEmpty ? '' : ' · $cleanDetail'}',
      'diagnostic': <String, dynamic>{
        'stage': 'STREAM_GATEWAY',
        'component': 'Streaming edge',
        'operation': 'chat.stream',
        'code': code,
        'lastSuccess': 'CLIENT_AUTH',
        if (cleanDetail.isNotEmpty) 'detail': cleanDetail,
      },
    });
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
    final configuredStreamBase = streamBaseUrl.trim();
    final streamBase =
        configuredStreamBase.isEmpty ? base : Uri.parse(configuredStreamBase);
    final uri = streamBase.replace(path: '/api/wesi/ai/chat/stream');
    final request = await _http.postUrl(uri);
    _applyAuth(request, auth);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/x-ndjson');
    cancellation?.bind(() => request.abort());
    request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      late Map<String, dynamic> json;
      try {
        json = await readJsonResponse(
          response,
          stage: 'STREAM_GATEWAY',
          component: 'Streaming edge',
          operation: 'chat.stream error response',
          lastSuccess: 'STREAM_RESPONSE_RECEIVED',
        );
      } on WesiAiApiException catch (error) {
        if (const <int>{404, 405, 501, 502}.contains(response.statusCode) &&
            error.code == 'WAI_BAD_SERVER_RESPONSE') {
          return null;
        }
        rethrow;
      } finally {
        cancellation?.unbind();
      }
      final code = '${json['code'] ?? ''}';
      if (const <int>{404, 405, 501, 502}.contains(response.statusCode) &&
          (code.isEmpty || code == 'WAI_STREAM_GATEWAY_NOT_CONFIGURED')) {
        return null;
      }
      final resolved = code.isEmpty ? 'WAI_STREAM_FAILED' : code;
      throw WesiAiApiException.fromPayload(
        resolved,
        _messageFor(resolved),
        json,
        httpStatus: response.statusCode,
        stage: response.statusCode == 401 || response.statusCode == 403
            ? 'AUTH'
            : 'STREAM_GATEWAY',
        component: response.statusCode == 401 || response.statusCode == 403
            ? 'Streaming Auth'
            : 'Streaming edge',
        operation: 'chat.stream',
        lastSuccess: response.statusCode == 401 || response.statusCode == 403
            ? 'CLIENT'
            : 'CLIENT_AUTH',
      );
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
              done.completeError(WesiAiApiException.fromPayload(
                code,
                _messageFor(code),
                event,
                httpStatus: event['status'] is num
                    ? (event['status'] as num).toInt()
                    : null,
                stage: 'STREAM_GATEWAY',
                component: 'Streaming gateway',
                operation: 'chat.stream',
                lastSuccess: 'STREAM_CONNECTED',
              ));
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
      activity: _activityFromToolResults(json['toolResults']),
    );
  }

  static List<Map<String, dynamic>> _activityFromToolResults(dynamic raw) {
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
      final filesRaw = payload['files'] ?? map['files'];
      final files = filesRaw is List
          ? filesRaw.take(40).map((value) => '$value').toList(growable: false)
          : const <String>[];
      final hasDiffMetadata = payload.containsKey('additions') ||
          payload.containsKey('deletions') ||
          map.containsKey('additions') ||
          map.containsKey('deletions') ||
          files.isNotEmpty;
      final transactionCount = payload['transactionCount'];
      final organizationName = '${payload['organizationName'] ?? ''}'.trim();
      final organizationId = '${payload['organizationId'] ?? ''}'.trim();
      final code = '${map['code'] ?? ''}'.trim();
      final detailParts = <String>[
        if (transactionCount is num) '${transactionCount.toInt()} операций',
        if (organizationName.isNotEmpty) organizationName,
        if (organizationName.isEmpty && organizationId.isNotEmpty)
          organizationId,
        if (code.isNotEmpty) code,
      ];
      result.add(<String, dynamic>{
        'id': 'tool_result_$index',
        'kind': 'tool',
        'sourceName': tool,
        'label': tool.isEmpty ? 'Инструмент' : 'Инструмент · $tool',
        'status': 'result',
        if (hasDiffMetadata)
          'additions': count(payload['additions'] ?? map['additions']),
        if (hasDiffMetadata)
          'deletions': count(payload['deletions'] ?? map['deletions']),
        if (files.isNotEmpty) 'files': files,
        if (detailParts.isNotEmpty) 'detail': detailParts.join(' · '),
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

  static const int maxJsonResponseBytes = 4 * 1024 * 1024;

  static Map<String, dynamic> decodeJsonObjectResponse(
    String raw, {
    int? httpStatus,
    String contentType = '',
    String stage = 'HTTP_RESPONSE',
    String component = 'WesiAiApi',
    String operation = 'decode response',
    String lastSuccess = 'RESPONSE_RECEIVED',
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException catch (error) {
      throw WesiAiApiException(
        'WAI_BAD_SERVER_RESPONSE',
        'Сервер WesiOS вернул некорректный ответ',
        stage: stage,
        component: component,
        operation: operation,
        httpStatus: httpStatus,
        lastSuccess: lastSuccess,
        detail: _responseDiagnosticDetail(contentType, trimmed, error.message),
      );
    }
    if (decoded is! Map) {
      throw WesiAiApiException(
        'WAI_BAD_SERVER_RESPONSE',
        'Сервер WesiOS вернул некорректный ответ',
        stage: stage,
        component: component,
        operation: operation,
        httpStatus: httpStatus,
        lastSuccess: lastSuccess,
        detail: _responseDiagnosticDetail(
          contentType,
          trimmed,
          'JSON root is ${decoded.runtimeType}, expected object',
        ),
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  static Future<Map<String, dynamic>> readJsonResponse(
    HttpClientResponse response, {
    String stage = 'HTTP_RESPONSE',
    String component = 'WesiAiApi',
    String operation = 'decode response',
    String lastSuccess = 'RESPONSE_RECEIVED',
  }) async {
    final bytes = <int>[];
    var total = 0;
    await for (final chunk in response) {
      total += chunk.length;
      if (total > maxJsonResponseBytes) {
        throw WesiAiApiException(
          'WAI_RESPONSE_TOO_LARGE',
          'Сервер WesiOS вернул слишком большой ответ',
          stage: stage,
          component: component,
          operation: operation,
          httpStatus: response.statusCode,
          lastSuccess: lastSuccess,
          detail: 'Ответ превысил лимит $maxJsonResponseBytes байт',
        );
      }
      bytes.addAll(chunk);
    }
    String raw;
    try {
      raw = utf8.decode(bytes, allowMalformed: false);
    } on FormatException catch (error) {
      throw WesiAiApiException(
        'WAI_BAD_SERVER_RESPONSE',
        'Сервер WesiOS вернул некорректный ответ',
        stage: stage,
        component: component,
        operation: operation,
        httpStatus: response.statusCode,
        lastSuccess: lastSuccess,
        detail: _responseDiagnosticDetail(
          response.headers.value(HttpHeaders.contentTypeHeader) ?? '',
          '',
          error.message,
        ),
      );
    }
    return decodeJsonObjectResponse(
      raw,
      httpStatus: response.statusCode,
      contentType: response.headers.value(HttpHeaders.contentTypeHeader) ?? '',
      stage: stage,
      component: component,
      operation: operation,
      lastSuccess: lastSuccess,
    );
  }

  static Future<Map<String, dynamic>> _readJson(
    HttpClientResponse response,
  ) =>
      readJsonResponse(response);

  static String _responseDiagnosticDetail(
    String contentType,
    String raw,
    String reason,
  ) {
    final preview = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    final clipped =
        preview.length > 240 ? '${preview.substring(0, 240)}…' : preview;
    return <String>[
      if (contentType.trim().isNotEmpty) 'Content-Type: ${contentType.trim()}',
      if (reason.trim().isNotEmpty) 'Причина: ${reason.trim()}',
      if (clipped.isNotEmpty) 'Начало ответа: $clipped',
    ].join(' · ');
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
          Map<String, dynamic> raw) =>
      WesiMediaLocalRequestSanitizer.sanitize(raw);

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
        'WAI_BAD_SERVER_RESPONSE' => 'Сервер WesiOS вернул некорректный ответ',
        'WAI_RESPONSE_TOO_LARGE' =>
          'Сервер WesiOS вернул слишком большой ответ',
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
