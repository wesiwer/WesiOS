from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'missing anchor: {label}')
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# API: additive sendStreamed contract. send() is untouched, so existing fake
# APIs and adapters remain source-compatible. Production WesiAiLobbyApi opts
# into native network streaming; base WesiAiApi falls back to send().
# ---------------------------------------------------------------------------
p = Path('lib/features/ai/wesi_ai_api.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    "class WesiAiApi {\n  static const int maxTransportHistoryMessages = 80;\n",
    "class WesiAiApi {\n  static const int maxTransportHistoryMessages = 80;\n\n  bool get nativeStreaming => false;\n",
    'stream capability getter',
)
anchor = "  Future<WesiAiReply> send({\n"
methods = r'''  Future<WesiAiReply> sendStreamed({
    required WesiAiConversation conversation,
    required WesiAiTier tier,
    required String message,
    required List<WesiAiMessage> history,
    required WesiAiMemorySnapshot memory,
    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
    required void Function(String delta) onDelta,
    Future<void>? cancel,
  }) async {
    if (!nativeStreaming || conversation.persona == WesiAiPersona.lobby) {
      var cancelled = false;
      if (cancel != null) {
        unawaited(cancel.then((_) => cancelled = true));
      }
      final reply = await send(
        conversation: conversation,
        tier: tier,
        message: message,
        history: history,
        memory: memory,
        project: project,
        attachments: attachments,
      );
      if (!cancelled && reply.answer.isNotEmpty) onDelta(reply.answer);
      return reply;
    }
    return _sendNetworkStream(
      conversation: conversation,
      tier: tier,
      message: message,
      history: history,
      memory: memory,
      project: project,
      attachments: attachments,
      onDelta: onDelta,
      cancel: cancel,
    );
  }

  Future<WesiAiReply> _sendNetworkStream({
    required WesiAiConversation conversation,
    required WesiAiTier tier,
    required String message,
    required List<WesiAiMessage> history,
    required WesiAiMemorySnapshot memory,
    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
    required void Function(String delta) onDelta,
    Future<void>? cancel,
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
      final uri = base.replace(path: '/api/wesi/ai/chat/stream');
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
        if (transportAttachments.isNotEmpty) 'attachments': transportAttachments,
      };

      final request = await _http.postUrl(uri);
      _applyAuth(request, auth);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/x-ndjson');
      request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 45));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final json = await _readJson(response);
        final code = '${json['code'] ?? 'WAI_STREAM_FAILED'}';
        throw WesiAiApiException(code, _messageFor(code));
      }

      final done = Completer<Map<String, dynamic>>();
      final lines = utf8.decoder.bind(response).transform(const LineSplitter());
      late final StreamSubscription<String> subscription;
      subscription = lines.listen(
        (line) {
          if (done.isCompleted || line.trim().isEmpty) return;
          Map<String, dynamic> event;
          try {
            final decoded = jsonDecode(line);
            if (decoded is! Map) throw const FormatException();
            event = Map<String, dynamic>.from(decoded);
          } on FormatException {
            done.completeError(const WesiAiApiException(
              'WAI_STREAM_BAD_EVENT',
              'Wesi AI вернул повреждённый поток ответа',
            ));
            unawaited(subscription.cancel());
            return;
          }
          switch ('${event['type'] ?? ''}') {
            case 'delta':
              final delta = '${event['text'] ?? ''}';
              if (delta.isNotEmpty) onDelta(delta);
              break;
            case 'done':
              done.complete(event);
              unawaited(subscription.cancel());
              break;
            case 'error':
              final code = '${event['code'] ?? 'WAI_STREAM_FAILED'}';
              done.completeError(WesiAiApiException(code, _messageFor(code)));
              unawaited(subscription.cancel());
              break;
            case 'meta':
            case 'heartbeat':
            case 'tool':
              break;
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

      if (cancel != null) {
        unawaited(cancel.then((_) async {
          await subscription.cancel();
          if (!done.isCompleted) {
            done.completeError(const WesiAiApiException(
              'WAI_CANCELLED',
              'Запрос Wesi AI остановлен',
            ));
          }
        }));
      }

      final json = await done.future.timeout(
        const Duration(seconds: 185),
        onTimeout: () {
          unawaited(subscription.cancel());
          throw const WesiAiApiException(
            'NETWORK',
            'Wesi AI не успел обработать запрос',
          );
        },
      );
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
      throw const WesiAiApiException('NETWORK', 'Wesi AI не успел обработать запрос');
    } on FormatException catch (e) {
      throw WesiAiApiException('WAI_ATTACHMENT_INVALID', e.message);
    }
  }

'''
s = replace_once(s, anchor, methods + anchor, 'stream methods')
# Add readable stream-specific messages if the current switch has the relay line.
s = replace_once(
    s,
    "        'WAI_RELAY_BAD_RESPONSE' => 'Сервис Wesi AI вернул ошибку',",
    "        'WAI_RELAY_BAD_RESPONSE' => 'Сервис Wesi AI вернул ошибку',\n        'WAI_STREAM_FAILED' || 'WAI_STREAM_RELAY_REJECTED' || 'WAI_STREAM_MAIN_REJECTED' => 'Не удалось открыть поток Wesi AI',\n        'WAI_STREAM_BAD_EVENT' || 'WAI_STREAM_EOF' || 'WAI_STREAM_RELAY_EOF' => 'Поток Wesi AI оборвался',\n        'WAI_CANCELLED' => 'Запрос Wesi AI остановлен',",
    'stream error messages',
)
p.write_text(s, encoding='utf-8')

# Production managed API opts into native streaming.
p = Path('lib/features/ai/wesi_ai_lobby_api.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    "  const WesiAiLobbyApi();\n",
    "  const WesiAiLobbyApi();\n\n  @override\n  bool get nativeStreaming => true;\n",
    'enable production streaming',
)
p.write_text(s, encoding='utf-8')

# Controller: one transient partial assistant message, replaced by one durable
# final answer. Cancel signal reaches the network subscription.
p = Path('lib/features/ai/controllers/wesi_ai_chat_controller.dart')
s = p.read_text(encoding='utf-8')
old = '''    try {
      final reply = await awaitInterruptible(api.send(
        conversation: updated,
        tier: state.tier,
        message: clean,
        history: history,
        memory: state.memory,
        project: _projectFor(updated.projectId),
        attachments: attachments,
      ));
      if (reply == null) return;
      final at = DateTime.now();
      final author = switch (c.persona) {
        WesiAiPersona.zane => WesiAiMessageAuthor.zane,
        WesiAiPersona.nirvana => WesiAiMessageAuthor.nirvana,
        WesiAiPersona.lobby => WesiAiMessageAuthor.zane
      };
      final assistant = WesiAiMessage(
        id: '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
        conversationId: c.id,
        employeeId: store.employeeId,
        author: author,
        text: reply.answer,
        createdAt: at,
        metadata: <String, dynamic>{
          'requestId': reply.requestId,
          if (reply.blocks.isNotEmpty)
            'blocks': reply.blocks
                .map((block) => block.toJson())
                .toList(growable: false),
        },
      );
      state = state.copyWith(
        messages: <WesiAiMessage>[...state.messages, assistant],
      );
      _startPendingMedia(assistant);
    } on WesiAiApiException catch (e) {
      final at = DateTime.now();
      state = state.copyWith(
        messages: <WesiAiMessage>[
          ...state.messages,
          WesiAiMessage(
            id: '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
            conversationId: c.id,
            employeeId: store.employeeId,
            author: WesiAiMessageAuthor.system,
            kind: WesiAiMessageKind.error,
            text: e.message,
            createdAt: at,
            metadata: <String, dynamic>{'code': e.code},
          ),
        ],
      );
    } finally {
      sending = false;
      await _persist();
    }
'''
new = '''    final author = switch (c.persona) {
      WesiAiPersona.zane => WesiAiMessageAuthor.zane,
      WesiAiPersona.nirvana => WesiAiMessageAuthor.nirvana,
      WesiAiPersona.lobby => WesiAiMessageAuthor.zane
    };
    final partialAt = DateTime.now();
    final partialId = '${user.id}_network_stream';
    var partialText = '';
    var partialInserted = false;
    var acceptDeltas = true;

    void removePartial() {
      if (!partialInserted) return;
      state = state.copyWith(
        messages: state.messages
            .where((message) => message.id != partialId)
            .toList(growable: false),
      );
      partialInserted = false;
      notifyIfActive();
    }

    void onDelta(String delta) {
      if (!acceptDeltas || isDisposed || delta.isEmpty) return;
      partialText += delta;
      final partial = WesiAiMessage(
        id: partialId,
        conversationId: c.id,
        employeeId: store.employeeId,
        author: author,
        text: partialText,
        createdAt: partialAt,
        metadata: const <String, dynamic>{'streaming': true},
      );
      if (partialInserted) {
        state = state.copyWith(
          messages: state.messages
              .map((message) => message.id == partialId ? partial : message)
              .toList(growable: false),
        );
      } else {
        state = state.copyWith(
          messages: <WesiAiMessage>[...state.messages, partial],
        );
        partialInserted = true;
      }
      notifyIfActive();
    }

    try {
      final WesiAiReply? reply;
      if (updated.persona == WesiAiPersona.lobby) {
        reply = await awaitInterruptible(api.send(
          conversation: updated,
          tier: state.tier,
          message: clean,
          history: history,
          memory: state.memory,
          project: _projectFor(updated.projectId),
          attachments: attachments,
        ));
      } else {
        reply = await awaitInterruptibleOperation((cancel) => api.sendStreamed(
              conversation: updated,
              tier: state.tier,
              message: clean,
              history: history,
              memory: state.memory,
              project: _projectFor(updated.projectId),
              attachments: attachments,
              onDelta: onDelta,
              cancel: cancel,
            ));
      }
      if (reply == null) {
        acceptDeltas = false;
        removePartial();
        return;
      }
      acceptDeltas = false;
      final at = DateTime.now();
      final assistant = WesiAiMessage(
        id: partialInserted
            ? partialId
            : '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
        conversationId: c.id,
        employeeId: store.employeeId,
        author: author,
        text: reply.answer,
        createdAt: partialInserted ? partialAt : at,
        metadata: <String, dynamic>{
          'requestId': reply.requestId,
          if (reply.blocks.isNotEmpty)
            'blocks': reply.blocks
                .map((block) => block.toJson())
                .toList(growable: false),
        },
      );
      state = state.copyWith(
        messages: <WesiAiMessage>[
          ...state.messages.where((message) => message.id != partialId),
          assistant,
        ],
      );
      partialInserted = false;
      _startPendingMedia(assistant);
    } on WesiAiApiException catch (e) {
      acceptDeltas = false;
      removePartial();
      if (e.code == 'WAI_CANCELLED') return;
      final at = DateTime.now();
      state = state.copyWith(
        messages: <WesiAiMessage>[
          ...state.messages,
          WesiAiMessage(
            id: '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
            conversationId: c.id,
            employeeId: store.employeeId,
            author: WesiAiMessageAuthor.system,
            kind: WesiAiMessageKind.error,
            text: e.message,
            createdAt: at,
            metadata: <String, dynamic>{'code': e.code},
          ),
        ],
      );
    } finally {
      acceptDeltas = false;
      sending = false;
      await _persist();
    }
'''
s = replace_once(s, old, new, 'controller streaming send')
helper_anchor = '''  @protected
  Future<T?> awaitInterruptible<T>(Future<T> future) async {
'''
helper = '''  @protected
  Future<T?> awaitInterruptibleOperation<T>(
    Future<T> Function(Future<void> cancel) operation,
  ) async {
    final signal = Completer<void>();
    _activeTurnInterrupt = signal;
    final future = operation(signal.future);
    try {
      final result = await Future.any<(bool interrupted, T? value)>([
        future.then<(bool interrupted, T? value)>((value) => (false, value)),
        signal.future.then<(bool interrupted, T? value)>((_) => (true, null)),
      ]);
      return result.$1 ? null : result.$2;
    } finally {
      if (identical(_activeTurnInterrupt, signal)) {
        _activeTurnInterrupt = null;
      }
    }
  }

'''
s = replace_once(s, helper_anchor, helper + helper_anchor, 'cancel-aware interrupt helper')
p.write_text(s, encoding='utf-8')

# Do not restart the old typewriter animation on each transport delta.
p = Path('lib/features/ai/widgets/wesi_ai_message_content.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    "    final assistant = message.author == WesiAiMessageAuthor.zane ||\n        message.author == WesiAiMessageAuthor.nirvana;\n",
    "    final assistant = message.author == WesiAiMessageAuthor.zane ||\n        message.author == WesiAiMessageAuthor.nirvana;\n    final streaming = message.metadata['streaming'] == true;\n",
    'streaming visual flag',
)
s = replace_once(
    s,
    '            animate: animateText && assistant,',
    '            animate: animateText && assistant && !streaming,',
    'disable typewriter on live stream',
)
p.write_text(s, encoding='utf-8')

# Regression tests live with existing queue fakes so no production storage is used.
p = Path('test/wesi_ai_queue_hardening_test.dart')
s = p.read_text(encoding='utf-8')
fake_anchor = '''Future<void> _waitUntil(bool Function() condition) async {
'''
fake = r'''class _StreamingApi extends WesiAiApi {
  final Completer<void> started = Completer<void>();
  final Completer<void> finish = Completer<void>();
  bool cancelled = false;

  @override
  Future<WesiAiReply> sendStreamed({
    required WesiAiConversation conversation,
    required WesiAiTier tier,
    required String message,
    required List<WesiAiMessage> history,
    required WesiAiMemorySnapshot memory,
    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
    required void Function(String delta) onDelta,
    Future<void>? cancel,
  }) async {
    if (!started.isCompleted) started.complete();
    onDelta('Первая ');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    onDelta('часть');
    if (cancel != null) {
      unawaited(cancel.then((_) => cancelled = true));
    }
    await Future.any<void>([
      finish.future,
      if (cancel != null) cancel,
    ]);
    if (cancelled) {
      throw const WesiAiApiException('WAI_CANCELLED', 'cancelled');
    }
    return const WesiAiReply(
      answer: 'Первая часть — готово',
      requestId: 'stream-request-1',
    );
  }

  @override
  Future<WesiAiReply> send({
    required WesiAiConversation conversation,
    required WesiAiTier tier,
    required String message,
    required List<WesiAiMessage> history,
    required WesiAiMemorySnapshot memory,
    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
  }) => throw StateError('streaming path expected');
}

'''
s = replace_once(s, fake_anchor, fake + fake_anchor, 'streaming fake')
idx = s.rfind('\n}')
if idx < 0:
    raise SystemExit('missing main closing brace')
tests = r'''

  test('streaming deltas update one transient assistant message and persist one final answer', () async {
    final api = _StreamingApi();
    final controller = WesiAiManagedChatController(
      store: _MemoryStore('employee-1'),
      api: api,
    );
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);
    final conversationId = controller.state.activeConversationId!;

    expect(
      await controller.submitUserMessage('stream me'),
      WesiAiMessageSubmitResult.accepted,
    );
    await api.started.future;
    await _waitUntil(() => controller.state.messagesFor(conversationId).any(
          (message) =>
              message.metadata['streaming'] == true &&
              message.text == 'Первая часть',
        ));
    expect(
      controller.state
          .messagesFor(conversationId)
          .where((message) => message.metadata['streaming'] == true)
          .length,
      1,
    );

    api.finish.complete();
    await _waitUntil(() => !controller.processing);
    final messages = controller.state.messagesFor(conversationId);
    expect(messages.any((message) => message.metadata['streaming'] == true), isFalse);
    expect(
      messages.any((message) =>
          message.author == WesiAiMessageAuthor.zane &&
          message.text == 'Первая часть — готово' &&
          message.metadata['requestId'] == 'stream-request-1'),
      isTrue,
    );
  });

  test('control cancels active stream and removes transient assistant text', () async {
    final api = _StreamingApi();
    final controller = WesiAiManagedChatController(
      store: _MemoryStore('employee-1'),
      api: api,
    );
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);
    final conversationId = controller.state.activeConversationId!;

    expect(
      await controller.submitUserMessage('long stream'),
      WesiAiMessageSubmitResult.accepted,
    );
    await api.started.future;
    await _waitUntil(() => controller.state.messagesFor(conversationId).any(
          (message) => message.metadata['streaming'] == true,
        ));
    expect(
      await controller.submitUserMessage('стой'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => api.cancelled);
    await _waitUntil(() => !controller.processing);

    final messages = controller.state.messagesFor(conversationId);
    expect(messages.any((message) => message.metadata['streaming'] == true), isFalse);
    expect(messages.any((message) => message.text == 'Первая часть — готово'), isFalse);
    expect(
      messages.any((message) => message.metadata['code'] == 'WAI_CONTROL_APPLIED'),
      isTrue,
    );
  });
'''
s = s[:idx] + tests + s[idx:]
p.write_text(s, encoding='utf-8')
