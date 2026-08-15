from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"missing anchor: {label}")
    return text.replace(old, new, 1)


# Client API: consume NDJSON transport, keep old JSON route as rollout fallback.
p = Path('lib/features/ai/wesi_ai_api.dart')
s = p.read_text(encoding='utf-8')
reply_anchor = '''class WesiAiReply {
  final String answer;
  final String requestId;
  final List<WesiAiContentBlock> blocks;

  const WesiAiReply({
    required this.answer,
    required this.requestId,
    this.blocks = const <WesiAiContentBlock>[],
  });
}
'''
cancel_class = reply_anchor + '''
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
'''
s = replace_once(s, reply_anchor, cancel_class, 'cancellation class')
s = replace_once(
    s,
    '''    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
  }) async {''',
    '''    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
    void Function(String delta)? onDelta,
    WesiAiRequestCancellation? cancellation,
  }) async {''',
    'api send signature',
)
body_anchor = '''        if (transportAttachments.isNotEmpty) 'attachments': transportAttachments,
      };

      final request = await _http.postUrl(uri);'''
body_replacement = '''        if (transportAttachments.isNotEmpty) 'attachments': transportAttachments,
      };

      if (conversation.persona != WesiAiPersona.lobby) {
        final streamed = await _sendStream(
          base: base,
          auth: auth,
          body: body,
          onDelta: onDelta,
          cancellation: cancellation,
        );
        if (streamed != null) return streamed;
      }

      final request = await _http.postUrl(uri);
      cancellation?.bind(() => request.abort());'''
s = replace_once(s, body_anchor, body_replacement, 'stream attempt before json')
s = replace_once(
    s,
    '''      final response = await request.close().timeout(const Duration(seconds: 185));
      final json = await _readJson(response);''',
    '''      final response = await request.close().timeout(const Duration(seconds: 185));
      final json = await _readJson(response);
      cancellation?.unbind();''',
    'json cancellation unbind',
)
old_parse = '''      final parsed = WesiAiContentParser.parse(
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
      );'''
s = replace_once(s, old_parse, '      return _replyFromPayload(json);', 'shared reply parser')
helper_anchor = '  Future<List<Map<String, dynamic>>> _prepareTransportAttachments({'
helpers = r'''  Future<WesiAiReply?> _sendStream({
    required Uri base,
    required ({String token, String sessionId}) auth,
    required Map<String, dynamic> body,
    required void Function(String delta)? onDelta,
    required WesiAiRequestCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled == true) {
      throw const WesiAiApiException('WAI_CANCELLED', 'Запрос Wesi AI остановлен');
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
    subscription = utf8.decoder
        .bind(response)
        .transform(const LineSplitter())
        .listen(
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
            case 'heartbeat':
            case 'tool':
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
      blocks: blocks.take(WesiAiContentParser.maxBlocks).toList(growable: false),
    );
  }

'''
s = replace_once(s, helper_anchor, helpers + helper_anchor, 'stream helpers')
s = replace_once(
    s,
    "        'WAI_RELAY_BAD_RESPONSE' => 'Сервис Wesi AI вернул ошибку',",
    "        'WAI_RELAY_BAD_RESPONSE' => 'Сервис Wesi AI вернул ошибку',\n        'WAI_STREAM_FAILED' || 'WAI_STREAM_RELAY_REJECTED' || 'WAI_STREAM_MAIN_REJECTED' => 'Не удалось открыть поток Wesi AI',\n        'WAI_STREAM_BAD_EVENT' || 'WAI_STREAM_EOF' || 'WAI_STREAM_RELAY_EOF' => 'Поток Wesi AI оборвался',\n        'WAI_CANCELLED' => 'Запрос Wesi AI остановлен',",
    'stream error messages',
)
p.write_text(s, encoding='utf-8')

# Lobby API must keep override compatibility; Lobby itself remains its canonical multi-author endpoint.
p = Path('lib/features/ai/wesi_ai_lobby_api.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    '''    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
  }) async {''',
    '''    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
    void Function(String delta)? onDelta,
    WesiAiRequestCancellation? cancellation,
  }) async {''',
    'lobby send signature',
)
s = s.replace(
    '        attachments: attachments,\n      );',
    '        attachments: attachments,\n        onDelta: onDelta,\n        cancellation: cancellation,\n      );',
)
p.write_text(s, encoding='utf-8')

# Controller: update one transient assistant message as network deltas arrive.
p = Path('lib/features/ai/controllers/wesi_ai_chat_controller.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    '  Completer<void>? _activeTurnInterrupt;\n',
    '  Completer<void>? _activeTurnInterrupt;\n  WesiAiRequestCancellation? _activeRequestCancellation;\n',
    'controller cancellation field',
)
try_anchor = '''    try {
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
      _startPendingMedia(assistant);'''
try_replacement = '''    final author = switch (c.persona) {
      WesiAiPersona.zane => WesiAiMessageAuthor.zane,
      WesiAiPersona.nirvana => WesiAiMessageAuthor.nirvana,
      WesiAiPersona.lobby => WesiAiMessageAuthor.zane
    };
    final streamMessageId = '${user.id}_transport_stream';
    var streamedText = '';
    var streamVisible = false;

    void removeTransientStream() {
      if (!streamVisible) return;
      state = state.copyWith(
        messages: state.messages
            .where((message) => message.id != streamMessageId)
            .toList(growable: false),
      );
      streamVisible = false;
      streamedText = '';
      notifyIfActive();
    }

    void onDelta(String delta) {
      if (delta.isEmpty || c.persona == WesiAiPersona.lobby) return;
      streamedText += delta;
      final at = DateTime.now();
      final partial = WesiAiMessage(
        id: streamMessageId,
        conversationId: c.id,
        employeeId: store.employeeId,
        author: author,
        text: streamedText,
        createdAt: at,
        metadata: const <String, dynamic>{'transportStreaming': true},
      );
      final withoutPartial = state.messages
          .where((message) => message.id != streamMessageId)
          .toList(growable: false);
      state = state.copyWith(messages: <WesiAiMessage>[...withoutPartial, partial]);
      streamVisible = true;
      notifyIfActive();
    }

    final cancellation = WesiAiRequestCancellation();
    _activeRequestCancellation = cancellation;
    try {
      final reply = await awaitInterruptible(api.send(
        conversation: updated,
        tier: state.tier,
        message: clean,
        history: history,
        memory: state.memory,
        project: _projectFor(updated.projectId),
        attachments: attachments,
        onDelta: onDelta,
        cancellation: cancellation,
      ));
      if (reply == null) {
        removeTransientStream();
        return;
      }
      final at = DateTime.now();
      final assistant = WesiAiMessage(
        id: streamVisible
            ? streamMessageId
            : '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
        conversationId: c.id,
        employeeId: store.employeeId,
        author: author,
        text: reply.answer,
        createdAt: at,
        metadata: <String, dynamic>{
          'requestId': reply.requestId,
          if (streamVisible) 'transportStreamed': true,
          if (reply.blocks.isNotEmpty)
            'blocks': reply.blocks
                .map((block) => block.toJson())
                .toList(growable: false),
        },
      );
      final withoutPartial = state.messages
          .where((message) => message.id != streamMessageId)
          .toList(growable: false);
      state = state.copyWith(
        messages: <WesiAiMessage>[...withoutPartial, assistant],
      );
      streamVisible = false;
      _startPendingMedia(assistant);'''
s = replace_once(s, try_anchor, try_replacement, 'controller streaming block')
s = replace_once(
    s,
    '''    } on WesiAiApiException catch (e) {
      final at = DateTime.now();''',
    '''    } on WesiAiApiException catch (e) {
      removeTransientStream();
      if (e.code == 'WAI_CANCELLED') return;
      final at = DateTime.now();''',
    'controller stream error cleanup',
)
s = replace_once(
    s,
    '''    } finally {
      sending = false;
      await _persist();
    }''',
    '''    } finally {
      if (identical(_activeRequestCancellation, cancellation)) {
        _activeRequestCancellation = null;
      }
      sending = false;
      await _persist();
    }''',
    'controller cancellation cleanup',
)
s = replace_once(
    s,
    '''  bool interruptActiveTurn() {
    final signal = _activeTurnInterrupt;
    if (signal == null || signal.isCompleted) return false;
    signal.complete();
    return true;
  }''',
    '''  bool interruptActiveTurn() {
    final transportCancelled = _activeRequestCancellation?.cancel() ?? false;
    final signal = _activeTurnInterrupt;
    if (signal == null || signal.isCompleted) return transportCancelled;
    signal.complete();
    return true;
  }''',
    'controller physical transport cancel',
)
p.write_text(s, encoding='utf-8')

# Real transport deltas should not be animated a second time by the old typewriter.
p = Path('lib/features/ai/widgets/wesi_ai_message_content.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    '            animate: animateText && assistant,',
    "            animate: animateText &&\n                assistant &&\n                message.metadata['transportStreaming'] != true &&\n                message.metadata['transportStreamed'] != true,",
    'disable duplicate typewriter',
)
p.write_text(s, encoding='utf-8')

# Existing fake APIs need the widened method signature.
for p in Path('test').glob('**/*.dart'):
    s = p.read_text(encoding='utf-8')
    if 'Future<WesiAiReply> send({' not in s:
        continue
    old = '''    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
  }) {'''
    new = '''    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
    void Function(String delta)? onDelta,
    WesiAiRequestCancellation? cancellation,
  }) {'''
    s = s.replace(old, new)
    old_async = '''    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
  }) async {'''
    new_async = '''    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
    void Function(String delta)? onDelta,
    WesiAiRequestCancellation? cancellation,
  }) async {'''
    s = s.replace(old_async, new_async)
    p.write_text(s, encoding='utf-8')

# Add a regression fake that emits deltas before completing.
p = Path('test/wesi_ai_queue_hardening_test.dart')
s = p.read_text(encoding='utf-8')
insert = r'''

class _StreamingControlledApi extends WesiAiApi {
  final Completer<WesiAiReply> reply = Completer<WesiAiReply>();
  void Function(String delta)? onDelta;

  @override
  Future<WesiAiReply> send({
    required WesiAiConversation conversation,
    required WesiAiTier tier,
    required String message,
    required List<WesiAiMessage> history,
    required WesiAiMemorySnapshot memory,
    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
    void Function(String delta)? onDelta,
    WesiAiRequestCancellation? cancellation,
  }) {
    this.onDelta = onDelta;
    return reply.future;
  }
}
'''
class_anchor = 'Future<void> _waitUntil(bool Function() condition) async {'
s = replace_once(s, class_anchor, insert + '\n' + class_anchor, 'stream fake')
end = s.rfind('\n}')
if end < 0:
    raise SystemExit('missing test suite close')
test = r'''

  test('transport deltas are visible before final reply and collapse into one persisted message', () async {
    final api = _StreamingControlledApi();
    final store = _MemoryStore('employee-stream');
    final controller = WesiAiManagedChatController(store: store, api: api);
    await controller.load();
    await controller.createConversation(WesiAiPersona.zane);
    final conversationId = controller.state.activeConversationId!;

    final sending = controller.addUserMessage('stream me');
    await _waitUntil(() => api.onDelta != null);
    api.onDelta!('При');
    api.onDelta!('вет');
    await _waitUntil(() => controller.state.messagesFor(conversationId).any(
          (message) => message.metadata['transportStreaming'] == true && message.text == 'Привет',
        ));

    api.reply.complete(const WesiAiReply(answer: 'Привет', requestId: 'stream-1'));
    await sending;
    final messages = controller.state.messagesFor(conversationId);
    expect(messages.where((message) => message.author == WesiAiMessageAuthor.zane).length, 1);
    expect(messages.last.text, 'Привет');
    expect(messages.last.metadata['transportStreamed'], isTrue);
    expect(store.saved!.messagesFor(conversationId).last.text, 'Привет');
  });
'''
s = s[:end] + test + s[end:]
p.write_text(s, encoding='utf-8')
