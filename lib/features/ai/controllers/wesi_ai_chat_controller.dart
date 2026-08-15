import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../media_engines/wesi_media_engine_runner.dart';
import '../models/wesi_ai_attachment.dart';
import '../models/wesi_ai_chat_models.dart';
import '../storage/wesi_ai_local_store.dart';
import '../wesi_ai_api.dart';

class WesiAiChatController extends ChangeNotifier {
  final WesiAiLocalStore store;
  final WesiAiApi api;
  final Set<String> _mediaPolls = <String>{};
  final Set<String> _localMediaRuns = <String>{};
  bool _disposed = false;

  WesiAiLocalState state;
  bool loading = true;
  bool sending = false;

  WesiAiChatController({required this.store, this.api = const WesiAiApi()})
      : state = WesiAiLocalState.empty(store.employeeId);

  Future<void> load() async {
    state = await store.load();
    loading = false;
    notifyIfActive();
    for (final message in state.messages) {
      _startPendingMedia(message);
    }
  }

  Future<void> setTier(WesiAiTier tier) async {
    state = state.copyWith(tier: tier);
    await _persist();
  }

  Future<void> createConversation(WesiAiPersona persona) async {
    final now = DateTime.now();
    final id = '${now.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
    final title = switch (persona) {
      WesiAiPersona.zane => 'Новый чат с Зейном',
      WesiAiPersona.nirvana => 'Новый чат с Нирваной',
      WesiAiPersona.lobby => 'Новое лобби'
    };
    final c = WesiAiConversation(
      id: id,
      employeeId: store.employeeId,
      title: title,
      persona: persona,
      createdAt: now,
      updatedAt: now,
    );
    state = state.copyWith(
      conversations: <WesiAiConversation>[c, ...state.conversations],
      activeConversationId: id,
    );
    await _persist();
  }

  Future<void> selectConversation(String id) async {
    if (!state.conversations.any(
      (c) => c.id == id && c.employeeId == store.employeeId,
    )) {
      return;
    }
    state = state.copyWith(activeConversationId: id);
    await _persist();
  }

  WesiAiProject? _projectFor(String? projectId) {
    if (projectId == null) return null;
    for (final project in state.projects) {
      if (project.id == projectId && project.employeeId == store.employeeId) {
        return project;
      }
    }
    return null;
  }

  Future<void> addUserMessage(
    String text, {
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
  }) async {
    final c = state.activeConversation;
    final clean = text.trim();
    if (c == null || sending || (clean.isEmpty && attachments.isEmpty)) return;
    try {
      WesiAiAttachment.validateBatch(attachments);
    } on FormatException catch (e) {
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
            metadata: const <String, dynamic>{'code': 'WAI_ATTACHMENT_INVALID'},
          ),
        ],
      );
      await _persist();
      return;
    }

    final history = state.messagesFor(c.id);
    final now = DateTime.now();
    final visibleText = clean.isNotEmpty
        ? clean
        : 'Вложения: ${attachments.map((item) => item.name).join(', ')}';
    final user = WesiAiMessage(
      id: '${now.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
      conversationId: c.id,
      employeeId: store.employeeId,
      author: WesiAiMessageAuthor.user,
      text: visibleText,
      createdAt: now,
      metadata: attachments.isEmpty
          ? const <String, dynamic>{}
          : <String, dynamic>{
              'attachments': attachments
                  .map((attachment) => attachment.toMetadataJson())
                  .toList(growable: false),
            },
    );
    final titleSource = clean.isNotEmpty ? clean : attachments.first.name;
    final updated =
        c.copyWith(updatedAt: now, title: _titleFor(c, titleSource));
    final conversations = state.conversations
        .map((x) => x.id == c.id ? updated : x)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = state.copyWith(
      messages: <WesiAiMessage>[...state.messages, user],
      conversations: conversations,
    );
    sending = true;
    await _persist();

    try {
      final reply = await api.send(
        conversation: updated,
        tier: state.tier,
        message: clean,
        history: history,
        memory: state.memory,
        project: _projectFor(updated.projectId),
        attachments: attachments,
      );
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
  }

  void _startPendingMedia(WesiAiMessage message) {
    final rawBlocks = message.metadata['blocks'];
    if (rawBlocks is! List) return;
    for (final raw in rawBlocks) {
      if (raw is! Map) continue;
      final block = Map<String, dynamic>.from(raw);
      if ('${block['type'] ?? ''}' != 'media') continue;
      final rawData = block['data'];
      if (rawData is! Map) continue;
      final data = Map<String, dynamic>.from(rawData);
      if ('${data['status'] ?? ''}'.toLowerCase() != 'pending') continue;

      final localRequest = data['localRequest'];
      if (localRequest is Map) {
        final key =
            '${message.id}|local|${data['mediaType']}|${data['prompt']}';
        if (_localMediaRuns.add(key)) {
          unawaited(_runLocalMedia(
            message,
            Map<String, dynamic>.from(localRequest),
            key,
          ));
        }
        continue;
      }

      final statusUrl = '${data['url'] ?? ''}'.trim();
      final uri = Uri.tryParse(statusUrl);
      if (uri == null || !uri.path.startsWith('/api/wesi/ai/media/jobs/')) {
        continue;
      }
      final key = '${message.id}|$statusUrl';
      if (!_mediaPolls.add(key)) continue;
      unawaited(_monitorMedia(message.id, statusUrl, key));
    }
  }

  Future<void> _runLocalMedia(
    WesiAiMessage source,
    Map<String, dynamic> request,
    String key,
  ) async {
    try {
      final result = await WesiMediaEngineRunner.run(request);
      if (_disposed) return;
      await _markLocalRequestFinished(source.id, request, result.ok);
      final at = DateTime.now();
      final type = '${request['mediaType'] ?? 'media'}';
      final label = switch (type) {
        'image' => 'изображения',
        'music' => 'музыки',
        'video' => 'видео',
        _ => 'медиа',
      };
      final text = result.ok
          ? 'Локальная генерация $label завершена. Файл сохранён: ${result.outputPath}'
          : result.code == 'WAI_MEDIA_ENGINE_NOT_INSTALLED'
              ? 'Для генерации $label установите соответствующий Wesi AI Media Engine в Настройки → Модели.'
              : 'Локальная генерация $label не завершилась (${result.code}).';
      state = state.copyWith(
        messages: <WesiAiMessage>[
          ...state.messages,
          WesiAiMessage(
            id: '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
            conversationId: source.conversationId,
            employeeId: store.employeeId,
            author: WesiAiMessageAuthor.system,
            kind: result.ok ? WesiAiMessageKind.file : WesiAiMessageKind.error,
            text: text,
            createdAt: at,
            metadata: <String, dynamic>{
              'code': result.code,
              'mediaType': type,
              if (result.outputPath != null) 'localPath': result.outputPath,
              if (result.mimeType != null) 'mimeType': result.mimeType,
            },
          ),
        ],
      );
      await _persist();
    } finally {
      _localMediaRuns.remove(key);
    }
  }

  Future<void> _markLocalRequestFinished(
    String messageId,
    Map<String, dynamic> request,
    bool ok,
  ) async {
    var changed = false;
    final messages = state.messages.map((message) {
      if (message.id != messageId) return message;
      final rawBlocks = message.metadata['blocks'];
      if (rawBlocks is! List) return message;
      final nextBlocks = <dynamic>[];
      for (final raw in rawBlocks) {
        if (raw is Map) {
          final block = Map<String, dynamic>.from(raw);
          final dataRaw = block['data'];
          if (block['type'] == 'media' && dataRaw is Map) {
            final data = Map<String, dynamic>.from(dataRaw);
            final localRaw = data['localRequest'];
            if (localRaw is Map &&
                '${localRaw['mediaType'] ?? ''}' ==
                    '${request['mediaType'] ?? ''}' &&
                '${localRaw['prompt'] ?? ''}' == '${request['prompt'] ?? ''}') {
              data.remove('localRequest');
              data['status'] = ok ? 'ready' : 'failed';
              block['data'] = data;
              nextBlocks.add(block);
              changed = true;
              continue;
            }
          }
        }
        nextBlocks.add(raw);
      }
      if (!changed) return message;
      final metadata = Map<String, dynamic>.from(message.metadata);
      metadata['blocks'] = nextBlocks;
      return message.copyWith(metadata: metadata);
    }).toList(growable: false);
    if (!changed || _disposed) return;
    state = state.copyWith(messages: messages);
    await _persist();
  }

  Future<void> _monitorMedia(
    String messageId,
    String statusUrl,
    String key,
  ) async {
    try {
      for (var attempt = 0; attempt < 120 && !_disposed; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(seconds: 5));
        }
        if (_disposed || !_messageStillHasStatusUrl(messageId, statusUrl)) {
          return;
        }
        final block = await api.mediaJob(statusUrl);
        if (block == null) continue;
        final status = '${block.data['status'] ?? ''}'.toLowerCase();
        if (status != 'ready' && status != 'failed') continue;
        await _replacePendingMedia(messageId, statusUrl, block.toJson());
        return;
      }
    } finally {
      _mediaPolls.remove(key);
    }
  }

  bool _messageStillHasStatusUrl(String messageId, String statusUrl) {
    WesiAiMessage? message;
    for (final item in state.messages) {
      if (item.id == messageId) {
        message = item;
        break;
      }
    }
    if (message == null) return false;
    final blocks = message.metadata['blocks'];
    if (blocks is! List) return false;
    for (final raw in blocks) {
      if (raw is! Map) continue;
      final data = raw['data'];
      if (data is Map && '${data['url'] ?? ''}' == statusUrl) return true;
    }
    return false;
  }

  Future<void> _replacePendingMedia(
    String messageId,
    String statusUrl,
    Map<String, dynamic> resolved,
  ) async {
    var changed = false;
    final messages = state.messages.map((message) {
      if (message.id != messageId) return message;
      final rawBlocks = message.metadata['blocks'];
      if (rawBlocks is! List) return message;
      final nextBlocks = <dynamic>[];
      for (final raw in rawBlocks) {
        if (raw is Map) {
          final map = Map<String, dynamic>.from(raw);
          final data = map['data'];
          if (map['type'] == 'media' &&
              data is Map &&
              '${data['url'] ?? ''}' == statusUrl) {
            nextBlocks.add(resolved);
            changed = true;
            continue;
          }
        }
        nextBlocks.add(raw);
      }
      if (!changed) return message;
      final metadata = Map<String, dynamic>.from(message.metadata);
      metadata['blocks'] = nextBlocks;
      return message.copyWith(metadata: metadata);
    }).toList(growable: false);
    if (!changed || _disposed) return;
    state = state.copyWith(messages: messages);
    await _persist();
  }

  String _titleFor(WesiAiConversation c, String text) {
    if (!c.title.startsWith('Новый ')) return c.title;
    return text.length <= 42 ? text : '${text.substring(0, 42)}…';
  }

  @protected
  bool get isDisposed => _disposed;

  @protected
  void notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _persist() async {
    await store.save(state);
    notifyIfActive();
  }

  @override
  void dispose() {
    _disposed = true;
    _mediaPolls.clear();
    _localMediaRuns.clear();
    super.dispose();
  }
}
