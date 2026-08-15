from pathlib import Path


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write(path: str, content: str) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding='utf-8')


def replace_once(path: str, old: str, new: str, marker: str | None = None) -> None:
    text = read(path)
    if marker and marker in text:
        return
    if old not in text:
        raise RuntimeError(f'missing patch anchor in {path}: {old[:120]!r}')
    write(path, text.replace(old, new, 1))


def insert_before(path: str, anchor: str, addition: str, marker: str) -> None:
    text = read(path)
    if marker in text:
        return
    if anchor not in text:
        raise RuntimeError(f'missing insert anchor in {path}: {anchor[:120]!r}')
    write(path, text.replace(anchor, addition + anchor, 1))


def replace_section(path: str, start: str, end: str, replacement: str, marker: str | None = None) -> None:
    text = read(path)
    if marker and marker in text:
        return
    a = text.find(start)
    b = text.find(end, a + len(start)) if a >= 0 else -1
    if a < 0 or b < 0:
        raise RuntimeError(f'missing section anchor in {path}: {start!r} -> {end!r}')
    write(path, text[:a] + replacement + text[b:])


# ---------------------------------------------------------------------------
# Rich renderer wiring.
# ---------------------------------------------------------------------------
path = 'lib/features/ai/widgets/wesi_ai_message_content.dart'
replace_once(path, "import 'dart:async';\n", '', marker="import 'wesi_ai_rich_message.dart';")
replace_once(
    path,
    "import '../wesi_ai_action_api.dart';\n",
    "import '../wesi_ai_action_api.dart';\nimport 'wesi_ai_rich_message.dart';\n",
    marker="import 'wesi_ai_rich_message.dart';",
)
replace_once(
    path,
    "  final bool animateText;\n\n  const WesiAiMessageContent({\n    super.key,\n    required this.message,\n    this.animateText = true,\n  });",
    "  final bool animateText;\n  final bool expandWorkLog;\n\n  const WesiAiMessageContent({\n    super.key,\n    required this.message,\n    this.animateText = true,\n    this.expandWorkLog = false,\n  });",
    marker='final bool expandWorkLog;',
)
replace_once(
    path,
    "        if (message.text.isNotEmpty)\n          WesiAiTypewriterText(\n            messageId: message.id,\n            text: message.text,\n            animate: animateText &&\n                assistant &&\n                message.metadata['transportStreaming'] != true &&\n                message.metadata['transportStreamed'] != true,\n          ),",
    "        if (message.text.isNotEmpty || message.metadata['activity'] is List)\n          WesiAiRichMessage(\n            messageId: message.id,\n            text: message.text,\n            activityRaw: message.metadata['activity'],\n            streaming: message.metadata['transportStreaming'] == true,\n            expandWorkLog: expandWorkLog,\n            workDurationMs:\n                int.tryParse('${message.metadata['workDurationMs'] ?? 0}') ?? 0,\n          ),",
    marker='activityRaw: message.metadata',
)
replace_section(
    path,
    '/// Reveals a new AI reply rune-by-rune.',
    'class _BlockView extends StatelessWidget {',
    'class _BlockView extends StatelessWidget {',
    marker='class WesiAiTypewriterText',
)
# The replacement above is idempotent via absence of old class; if it ran, it
# duplicated the class marker. Normalize once.
text = read(path)
text = text.replace('class _BlockView extends StatelessWidget {class _BlockView extends StatelessWidget {', 'class _BlockView extends StatelessWidget {')
write(path, text)

# ---------------------------------------------------------------------------
# Conversation branch metadata.
# ---------------------------------------------------------------------------
path = 'lib/features/ai/models/wesi_ai_chat_models.dart'
replace_once(
    path,
    "  final bool importantForBackup;\n  final String? projectId;",
    "  final bool importantForBackup;\n  final String? projectId;\n  final String? branchedFromConversationId;\n  final String? branchedFromMessageId;",
    marker='branchedFromConversationId',
)
replace_once(
    path,
    "    this.importantForBackup = false,\n    this.projectId,\n  });",
    "    this.importantForBackup = false,\n    this.projectId,\n    this.branchedFromConversationId,\n    this.branchedFromMessageId,\n  });",
    marker='this.branchedFromConversationId',
)
replace_once(
    path,
    "    String? projectId,\n    bool clearProject = false,",
    "    String? projectId,\n    bool clearProject = false,\n    String? branchedFromConversationId,\n    String? branchedFromMessageId,",
    marker='String? branchedFromConversationId,',
)
replace_once(
    path,
    "        projectId: clearProject ? null : (projectId ?? this.projectId),\n      );",
    "        projectId: clearProject ? null : (projectId ?? this.projectId),\n        branchedFromConversationId:\n            branchedFromConversationId ?? this.branchedFromConversationId,\n        branchedFromMessageId: branchedFromMessageId ?? this.branchedFromMessageId,\n      );",
    marker='branchedFromConversationId:',
)
replace_once(
    path,
    "        'projectId': projectId,\n      };",
    "        'projectId': projectId,\n        'branchedFromConversationId': branchedFromConversationId,\n        'branchedFromMessageId': branchedFromMessageId,\n      };",
    marker="'branchedFromConversationId'",
)
replace_once(
    path,
    "        projectId: json['projectId'] as String?,\n      );",
    "        projectId: json['projectId'] as String?,\n        branchedFromConversationId: json['branchedFromConversationId'] as String?,\n        branchedFromMessageId: json['branchedFromMessageId'] as String?,\n      );",
    marker="json['branchedFromConversationId']",
)

# ---------------------------------------------------------------------------
# Controller: message archive + branching + live activity before first token.
# ---------------------------------------------------------------------------
path = 'lib/features/ai/controllers/wesi_ai_chat_controller.dart'
insert_before(
    path,
    '  Future<void> setConversationBackupImportant(',
    r'''  Future<void> setMessageSaved(String messageId, bool saved) async {
    var changed = false;
    final messages = state.messages.map((message) {
      if (message.id != messageId || message.employeeId != store.employeeId) {
        return message;
      }
      final metadata = Map<String, dynamic>.from(message.metadata);
      if (saved) {
        metadata['savedToChatArchive'] = true;
      } else {
        metadata.remove('savedToChatArchive');
      }
      changed = true;
      return message.copyWith(metadata: metadata);
    }).toList(growable: false);
    if (!changed) return;
    state = state.copyWith(messages: messages);
    await _persist();
  }

  Future<String?> branchConversationFromMessage(String messageId) async {
    WesiAiMessage? target;
    for (final message in state.messages) {
      if (message.id == messageId && message.employeeId == store.employeeId) {
        target = message;
        break;
      }
    }
    if (target == null) return null;
    WesiAiConversation? source;
    for (final conversation in state.conversations) {
      if (conversation.id == target.conversationId &&
          conversation.employeeId == store.employeeId) {
        source = conversation;
        break;
      }
    }
    if (source == null) return null;
    final sourceMessages = state.messagesFor(source.id);
    final targetIndex = sourceMessages.indexWhere((message) => message.id == messageId);
    if (targetIndex < 0) return null;

    final now = DateTime.now();
    final newId = '${now.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
    final copied = <WesiAiMessage>[];
    for (var index = 0; index <= targetIndex; index++) {
      final original = sourceMessages[index];
      copied.add(WesiAiMessage(
        id: '${newId}_branch_$index',
        conversationId: newId,
        employeeId: store.employeeId,
        author: original.author,
        kind: original.kind,
        text: original.text,
        createdAt: original.createdAt,
        metadata: <String, dynamic>{
          ...original.metadata,
          'branchOriginalConversationId': source.id,
          'branchOriginalMessageId': original.id,
        },
      ));
    }
    final branch = WesiAiConversation(
      id: newId,
      employeeId: store.employeeId,
      title: 'Ветка · ${source.title}',
      persona: source.persona,
      lobbyMode: source.lobbyMode,
      projectId: source.projectId,
      createdAt: now,
      updatedAt: now,
      branchedFromConversationId: source.id,
      branchedFromMessageId: messageId,
    );
    state = state.copyWith(
      conversations: <WesiAiConversation>[branch, ...state.conversations],
      messages: <WesiAiMessage>[...state.messages, ...copied],
      activeConversationId: newId,
      activeProjectId: source.projectId,
      clearActiveProject: source.projectId == null,
    );
    await _persist();
    return newId;
  }

''',
    marker='Future<String?> branchConversationFromMessage',
)

old_stream = r'''    final streamMessageId = '${user.id}_transport_stream';
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
      state =
          state.copyWith(messages: <WesiAiMessage>[...withoutPartial, partial]);
      streamVisible = true;
      notifyIfActive();
    }

'''
new_stream = r'''    final streamMessageId = '${user.id}_transport_stream';
    final workStartedAt = DateTime.now().toUtc();
    final activity = <Map<String, dynamic>>[];
    final openTools = <String, int>{};
    final openAgents = <String, int>{};
    var activitySequence = 0;
    var streamedText = '';
    var streamVisible = c.persona != WesiAiPersona.lobby;

    Map<String, dynamic> streamMetadata(bool streaming) => <String, dynamic>{
          if (streaming) 'transportStreaming': true,
          'activity': activity.map((item) => Map<String, dynamic>.from(item)).toList(growable: false),
          'workStartedAt': workStartedAt.toIso8601String(),
          'workDurationMs': DateTime.now().toUtc().difference(workStartedAt).inMilliseconds,
        };

    void publishPartial() {
      if (c.persona == WesiAiPersona.lobby) return;
      final partial = WesiAiMessage(
        id: streamMessageId,
        conversationId: c.id,
        employeeId: store.employeeId,
        author: author,
        text: streamedText,
        createdAt: workStartedAt.toLocal(),
        metadata: streamMetadata(true),
      );
      final withoutPartial = state.messages
          .where((message) => message.id != streamMessageId)
          .toList(growable: false);
      state = state.copyWith(messages: <WesiAiMessage>[...withoutPartial, partial]);
      streamVisible = true;
      notifyIfActive();
    }

    Map<String, dynamic> activityEntry({
      required String kind,
      required String label,
      String sourceName = '',
      String detail = '',
      String status = '',
      int additions = 0,
      int deletions = 0,
      List<dynamic> files = const <dynamic>[],
    }) {
      final at = DateTime.now().toUtc();
      return <String, dynamic>{
        'id': '${user.id}_activity_${activitySequence++}',
        'kind': kind,
        'label': label,
        if (sourceName.isNotEmpty) 'sourceName': sourceName,
        if (detail.isNotEmpty) 'detail': detail,
        if (status.isNotEmpty) 'status': status,
        'textOffset': streamedText.length,
        'startedAt': at.toIso8601String(),
        if (status == 'result' || status == 'done') 'completedAt': at.toIso8601String(),
        'additions': additions < 0 ? 0 : additions,
        'deletions': deletions < 0 ? 0 : deletions,
        if (files.isNotEmpty) 'files': files.take(40).map((item) => '$item').toList(growable: false),
      };
    }

    int safeCount(Object? value) {
      final count = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
      return count < 0 ? 0 : count;
    }

    void onActivity(Map<String, dynamic> raw) {
      final type = '${raw['type'] ?? 'activity'}'.toLowerCase();
      final phase = '${raw['phase'] ?? ''}'.toLowerCase();
      final name = '${raw['name'] ?? raw['agent'] ?? raw['persona'] ?? ''}'.trim();
      final additions = safeCount(raw['additions']);
      final deletions = safeCount(raw['deletions']);
      final files = raw['files'] is List ? List<dynamic>.from(raw['files'] as List) : const <dynamic>[];
      if (type == 'tool') {
        if (phase == 'start') {
          activity.add(activityEntry(
            kind: 'tool',
            label: name.isEmpty ? 'Запущен инструмент' : 'Инструмент · $name',
            sourceName: name,
            status: 'start',
          ));
          if (name.isNotEmpty) openTools[name] = activity.length - 1;
        } else {
          final index = name.isEmpty ? null : openTools.remove(name);
          if (index != null && index >= 0 && index < activity.length) {
            final current = Map<String, dynamic>.from(activity[index]);
            current['status'] = 'result';
            current['completedAt'] = DateTime.now().toUtc().toIso8601String();
            current['additions'] = additions;
            current['deletions'] = deletions;
            if (files.isNotEmpty) current['files'] = files.take(40).map((item) => '$item').toList(growable: false);
            final code = '${raw['code'] ?? ''}'.trim();
            if (code.isNotEmpty) current['detail'] = code;
            activity[index] = current;
          } else {
            activity.add(activityEntry(
              kind: 'tool',
              label: name.isEmpty ? 'Инструмент завершён' : 'Инструмент · $name',
              sourceName: name,
              status: 'result',
              additions: additions,
              deletions: deletions,
              files: files,
            ));
          }
        }
      } else if (type == 'agent') {
        if (phase == 'start') {
          activity.add(activityEntry(
            kind: 'agent',
            label: name.isEmpty ? 'Подключён агент' : 'Агент · $name',
            sourceName: name,
            status: 'start',
          ));
          if (name.isNotEmpty) openAgents[name] = activity.length - 1;
        } else {
          final index = name.isEmpty ? null : openAgents.remove(name);
          if (index != null && index >= 0 && index < activity.length) {
            final current = Map<String, dynamic>.from(activity[index]);
            current['status'] = 'result';
            current['completedAt'] = DateTime.now().toUtc().toIso8601String();
            current['additions'] = additions;
            current['deletions'] = deletions;
            if (files.isNotEmpty) current['files'] = files.take(40).map((item) => '$item').toList(growable: false);
            activity[index] = current;
          } else {
            activity.add(activityEntry(
              kind: 'agent',
              label: name.isEmpty ? 'Агент завершил работу' : 'Агент · $name',
              sourceName: name,
              status: 'result',
              additions: additions,
              deletions: deletions,
              files: files,
            ));
          }
        }
      } else if (type == 'meta') {
        final persona = '${raw['persona'] ?? ''}'.trim();
        final tier = '${raw['tier'] ?? ''}'.trim();
        activity.add(activityEntry(
          kind: 'status',
          label: 'Контекст и маршрут подготовлены',
          sourceName: persona,
          detail: [if (persona.isNotEmpty) persona, if (tier.isNotEmpty) tier].join(' · '),
          status: 'done',
        ));
      } else if (type == 'activity') {
        activity.add(activityEntry(
          kind: '${raw['kind'] ?? 'reasoning'}',
          label: '${raw['label'] ?? 'Ход работы'}'.trim(),
          sourceName: name,
          detail: '${raw['detail'] ?? raw['message'] ?? ''}'.trim(),
          status: phase.isEmpty ? '${raw['status'] ?? ''}' : phase,
          additions: additions,
          deletions: deletions,
          files: files,
        ));
      }
      publishPartial();
    }

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
      publishPartial();
    }

    if (streamVisible) {
      activity.add(activityEntry(
        kind: 'reasoning',
        label: 'Подготавливаю ответ',
        detail: 'Собираю контекст диалога, память, проект и доступные действия.',
        status: 'start',
      ));
      publishPartial();
    }

'''
replace_once(path, old_stream, new_stream, marker='void onActivity(Map<String, dynamic> raw)')
replace_once(
    path,
    "        onDelta: onDelta,\n        cancellation: cancellation,",
    "        onDelta: onDelta,\n        onActivity: onActivity,\n        cancellation: cancellation,",
    marker='onActivity: onActivity',
)
insert_before(
    path,
    "      final at = DateTime.now();\n      final assistant = WesiAiMessage(",
    r'''      for (final finalEvent in reply.activity) {
        final sourceName = '${finalEvent['sourceName'] ?? finalEvent['name'] ?? finalEvent['tool'] ?? ''}'.trim();
        final kind = '${finalEvent['kind'] ?? 'tool'}';
        var merged = false;
        if (sourceName.isNotEmpty) {
          for (var index = activity.length - 1; index >= 0; index--) {
            final current = activity[index];
            if ('${current['sourceName'] ?? ''}' == sourceName &&
                '${current['kind'] ?? ''}' == kind) {
              final next = Map<String, dynamic>.from(current);
              next['additions'] = safeCount(finalEvent['additions']);
              next['deletions'] = safeCount(finalEvent['deletions']);
              if (finalEvent['files'] is List) next['files'] = List<dynamic>.from(finalEvent['files'] as List);
              next['status'] = 'result';
              next['completedAt'] ??= DateTime.now().toUtc().toIso8601String();
              activity[index] = next;
              merged = true;
              break;
            }
          }
        }
        if (!merged) {
          final copy = Map<String, dynamic>.from(finalEvent);
          copy['id'] ??= '${user.id}_activity_${activitySequence++}';
          copy['textOffset'] ??= streamedText.length;
          activity.add(copy);
        }
      }
''',
    marker='for (final finalEvent in reply.activity)',
)
replace_once(
    path,
    "          'requestId': reply.requestId,\n          if (streamVisible) 'transportStreamed': true,",
    "          'requestId': reply.requestId,\n          if (streamVisible) 'transportStreamed': true,\n          if (activity.isNotEmpty)\n            'activity': activity.map((item) => Map<String, dynamic>.from(item)).toList(growable: false),\n          'workStartedAt': workStartedAt.toIso8601String(),\n          'workDurationMs': DateTime.now().toUtc().difference(workStartedAt).inMilliseconds,",
    marker="'workStartedAt': workStartedAt",
)

# ---------------------------------------------------------------------------
# API: surface activity events and fallback tool summaries.
# ---------------------------------------------------------------------------
path = 'lib/features/ai/wesi_ai_api.dart'
replace_once(
    path,
    "  final List<WesiAiContentBlock> blocks;\n\n  const WesiAiReply({\n    required this.answer,\n    required this.requestId,\n    this.blocks = const <WesiAiContentBlock>[],\n  });",
    "  final List<WesiAiContentBlock> blocks;\n  final List<Map<String, dynamic>> activity;\n\n  const WesiAiReply({\n    required this.answer,\n    required this.requestId,\n    this.blocks = const <WesiAiContentBlock>[],\n    this.activity = const <Map<String, dynamic>>[],\n  });",
    marker='final List<Map<String, dynamic>> activity;',
)
replace_once(
    path,
    "    void Function(String delta)? onDelta,\n    WesiAiRequestCancellation? cancellation,",
    "    void Function(String delta)? onDelta,\n    void Function(Map<String, dynamic> event)? onActivity,\n    WesiAiRequestCancellation? cancellation,",
    marker='void Function(Map<String, dynamic> event)? onActivity',
)
replace_once(
    path,
    "          onDelta: onDelta,\n          cancellation: cancellation,",
    "          onDelta: onDelta,\n          onActivity: onActivity,\n          cancellation: cancellation,",
    marker='onActivity: onActivity',
)
replace_once(
    path,
    "    required void Function(String delta)? onDelta,\n    required WesiAiRequestCancellation? cancellation,",
    "    required void Function(String delta)? onDelta,\n    required void Function(Map<String, dynamic> event)? onActivity,\n    required WesiAiRequestCancellation? cancellation,",
    marker='required void Function(Map<String, dynamic> event)? onActivity',
)
replace_once(
    path,
    "            case 'meta':\n            case 'heartbeat':\n            case 'tool':\n              break;",
    "            case 'meta':\n            case 'tool':\n            case 'agent':\n            case 'activity':\n              onActivity?.call(event);\n              break;\n            case 'heartbeat':\n              break;",
    marker="case 'agent':",
)
replace_once(
    path,
    "      blocks:\n          blocks.take(WesiAiContentParser.maxBlocks).toList(growable: false),\n    );",
    "      blocks:\n          blocks.take(WesiAiContentParser.maxBlocks).toList(growable: false),\n      activity: _activityFromToolResults(json['toolResults']),\n    );",
    marker='activity: _activityFromToolResults',
)
insert_before(
    path,
    '  Future<List<Map<String, dynamic>>> _prepareTransportAttachments({',
    r'''  static List<Map<String, dynamic>> _activityFromToolResults(dynamic raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    final result = <Map<String, dynamic>>[];
    for (var index = 0; index < raw.length && index < 80; index++) {
      final item = raw[index];
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final payloadRaw = map['result'];
      final payload = payloadRaw is Map ? Map<String, dynamic>.from(payloadRaw) : const <String, dynamic>{};
      int count(Object? value) {
        final parsed = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
        return parsed < 0 ? 0 : parsed;
      }
      final tool = '${map['tool'] ?? map['name'] ?? ''}'.trim();
      final filesRaw = payload['files'] ?? map['files'];
      final files = filesRaw is List ? filesRaw.take(40).map((value) => '$value').toList(growable: false) : const <String>[];
      result.add(<String, dynamic>{
        'id': 'tool_result_$index',
        'kind': 'tool',
        'sourceName': tool,
        'label': tool.isEmpty ? 'Инструмент' : 'Инструмент · $tool',
        'status': 'result',
        'additions': count(payload['additions'] ?? map['additions']),
        'deletions': count(payload['deletions'] ?? map['deletions']),
        if (files.isNotEmpty) 'files': files,
        if ('${map['code'] ?? ''}'.trim().isNotEmpty) 'detail': '${map['code']}',
      });
    }
    return result;
  }

''',
    marker='static List<Map<String, dynamic>> _activityFromToolResults',
)

# Lobby fallback also retains final tool activity.
path = 'lib/features/ai/wesi_ai_lobby_controller.dart'
replace_once(
    path,
    "            metadata: {'requestId': reply.requestId, 'lobby': true},",
    "            metadata: <String, dynamic>{\n              'requestId': reply.requestId,\n              'lobby': true,\n              if (reply.activity.isNotEmpty) 'activity': reply.activity,\n            },",
    marker="if (reply.activity.isNotEmpty) 'activity'",
)

# ---------------------------------------------------------------------------
# Chat screen actions, archive, branch header, compact camera.
# ---------------------------------------------------------------------------
path = 'lib/features/ai/ai_assistant_v2_screen.dart'
replace_once(
    path,
    "import 'widgets/wesi_ai_message_content.dart';\n",
    "import 'widgets/wesi_ai_message_content.dart';\nimport 'widgets/wesi_ai_message_actions.dart';\n",
    marker="import 'widgets/wesi_ai_message_actions.dart';",
)
replace_once(
    path,
    "        _conversationHeader(controller, active),",
    "        _conversationHeader(controller, active, messages),",
    marker='_conversationHeader(controller, active, messages)',
)
replace_once(
    path,
    "                  itemBuilder: (context, index) => _messageTile(\n                      messages[index], index == messages.length - 1),",
    "                  itemBuilder: (context, index) => _messageTile(\n                      controller, messages[index], index == messages.length - 1),",
    marker='_messageTile(\n                      controller,',
)
replace_once(
    path,
    "  Widget _conversationHeader(\n    WesiAiHandoffController controller,\n    WesiAiConversation active,\n  ) {\n    final enabled = !controller.processing;",
    "  Widget _conversationHeader(\n    WesiAiHandoffController controller,\n    WesiAiConversation active,\n    List<WesiAiMessage> messages,\n  ) {\n    final enabled = !controller.processing;\n    final savedMessages = messages\n        .where((message) => message.metadata['savedToChatArchive'] == true)\n        .toList(growable: false);",
    marker='final savedMessages = messages',
)
replace_once(
    path,
    "          const Spacer(),\n          if (active.persona != WesiAiPersona.lobby)",
    "          if (active.branchedFromConversationId != null) ...[\n            const SizedBox(width: 8),\n            ActionChip(\n              avatar: const Icon(Icons.account_tree_outlined, size: 16),\n              label: const Text('Ветка'),\n              onPressed: enabled\n                  ? () => controller.selectConversation(active.branchedFromConversationId!)\n                  : null,\n            ),\n          ],\n          if (savedMessages.isNotEmpty) ...[\n            const SizedBox(width: 4),\n            IconButton(\n              tooltip: 'Архив этого чата',\n              onPressed: () => showModalBottomSheet<void>(\n                context: context,\n                isScrollControlled: true,\n                showDragHandle: true,\n                builder: (_) => WesiAiMessageArchiveSheet(\n                  conversationTitle: active.title,\n                  messages: savedMessages,\n                ),\n              ),\n              icon: Badge(\n                label: Text('${savedMessages.length}'),\n                child: const Icon(Icons.bookmarks_outlined),\n              ),\n            ),\n          ],\n          const Spacer(),\n          if (active.persona != WesiAiPersona.lobby)",
    marker="tooltip: 'Архив этого чата'",
)
replace_once(
    path,
    "  Widget _messageTile(WesiAiMessage message, bool latest) {",
    "  Widget _messageTile(\n    WesiAiHandoffController controller,\n    WesiAiMessage message,\n    bool latest,\n  ) {",
    marker='WesiAiHandoffController controller,\n    WesiAiMessage message',
)
# Remove old synthetic reasoning summary card: rich content owns the live work log.
replace_once(
    path,
    "            if (assistant && _uiMode == WesiAiUiMode.thinking)\n              _reasoningSummary(message),\n",
    '',
    marker='WesiAiMessageActions(',
)
replace_once(
    path,
    "                    animateText: latest && assistant,\n                  ),",
    "                    animateText: latest && assistant,\n                    expandWorkLog: _uiMode == WesiAiUiMode.thinking,\n                  ),",
    marker='expandWorkLog: _uiMode == WesiAiUiMode.thinking',
)
replace_once(
    path,
    "            if (assistant && latest && message.text.trim().isNotEmpty)\n              _followUps(message.text),",
    "            if (assistant && message.metadata['transportStreaming'] != true)\n              WesiAiMessageActions(\n                message: message,\n                saved: message.metadata['savedToChatArchive'] == true,\n                onToggleSaved: (saved) => controller.setMessageSaved(message.id, saved),\n                onBranch: () async {\n                  await controller.branchConversationFromMessage(message.id);\n                },\n              ),\n            if (assistant && latest && message.text.trim().isNotEmpty)\n              _followUps(message.text),",
    marker='WesiAiMessageActions(',
)
# Remove obsolete synthetic summary method.
replace_section(
    path,
    '  Widget _reasoningSummary(WesiAiMessage message) => Container(',
    '  Widget _followUps(String answer) {',
    '  Widget _followUps(String answer) {',
    marker='safeReasoningSummary(message)',
)
text = read(path).replace('  Widget _followUps(String answer) {  Widget _followUps(String answer) {', '  Widget _followUps(String answer) {')
write(path, text)
replace_once(
    path,
    "                  subtitle: Text('Безопасное резюме обработки'),",
    "                  subtitle: Text('Ход работы раскрыт по умолчанию'),",
    marker='Ход работы раскрыт по умолчанию',
)
replace_once(
    path,
    "      final attachment = await Navigator.of(context).push<WesiAiAttachment>(\n        MaterialPageRoute(builder: (_) => const WesiAiCameraCaptureScreen()),\n      );",
    "      final attachment = await showDialog<WesiAiAttachment>(\n        context: context,\n        barrierColor: Colors.black87,\n        builder: (dialogContext) {\n          final size = MediaQuery.sizeOf(dialogContext);\n          final width = size.width < 620 ? size.width - 24 : 560.0;\n          final height = (size.height * 0.78).clamp(420.0, 720.0);\n          return Dialog(\n            insetPadding: const EdgeInsets.all(12),\n            clipBehavior: Clip.antiAlias,\n            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),\n            child: SizedBox(\n              width: width,\n              height: height,\n              child: const WesiAiCameraCaptureScreen(),\n            ),\n          );\n        },\n      );",
    marker='barrierColor: Colors.black87',
)

# ---------------------------------------------------------------------------
# Stream gateway: observable agent/tool lifecycle and per-tool diff stats.
# ---------------------------------------------------------------------------
path = 'server/wesi-ai-stream/gateway.mjs'
insert_before(
    path,
    'function relayPayload(prepared, toolResults, phase, finalOnly = false) {',
    r'''function diffStatsFromToolResult(toolResult) {
  const payload = toolResult && typeof toolResult.result === 'object' && !Array.isArray(toolResult.result)
    ? toolResult.result
    : {};
  const additions = Math.max(0, Number(payload.additions || toolResult?.additions || 0) || 0);
  const deletions = Math.max(0, Number(payload.deletions || toolResult?.deletions || 0) || 0);
  const rawFiles = Array.isArray(payload.files) ? payload.files : (Array.isArray(toolResult?.files) ? toolResult.files : []);
  const files = rawFiles.slice(0, 40).map((item) => {
    if (item && typeof item === 'object') return String(item.path || item.filename || item.name || '').slice(0, 500);
    return String(item || '').slice(0, 500);
  }).filter(Boolean);
  return {additions, deletions, files};
}

function aggregateDiffStats(toolResults) {
  let additions = 0;
  let deletions = 0;
  const files = new Set();
  for (const result of toolResults) {
    const stats = diffStatsFromToolResult(result);
    additions += stats.additions;
    deletions += stats.deletions;
    for (const file of stats.files) files.add(file);
  }
  return {additions, deletions, files: [...files].slice(0, 80)};
}

''',
    marker='function diffStatsFromToolResult',
)
replace_once(
    path,
    "      writeNdjson(res, {\n        type: 'meta',\n        requestId: prepared.requestId,\n        persona: prepared.persona,\n        tier: prepared.tier,\n      });\n\n      const toolResults = [];",
    "      writeNdjson(res, {\n        type: 'meta',\n        requestId: prepared.requestId,\n        persona: prepared.persona,\n        tier: prepared.tier,\n      });\n      writeNdjson(res, {\n        type: 'agent',\n        phase: 'start',\n        name: prepared.persona,\n        role: 'lead',\n      });\n      writeNdjson(res, {\n        type: 'activity',\n        kind: 'reasoning',\n        phase: 'result',\n        label: 'Контекст подготовлен',\n        detail: 'История, память, проект и доступные инструменты проверены.',\n      });\n\n      const toolResults = [];",
    marker="role: 'lead'",
)
replace_once(
    path,
    "        writeNdjson(res, {\n          type: 'tool',\n          phase: 'result',\n          name: toolRequest.name,\n          ok: toolResult?.ok === true,\n          code: toolResult?.code || null,\n        });",
    "        const diff = diffStatsFromToolResult(toolResult);\n        writeNdjson(res, {\n          type: 'tool',\n          phase: 'result',\n          name: toolRequest.name,\n          ok: toolResult?.ok === true,\n          code: toolResult?.code || null,\n          additions: diff.additions,\n          deletions: diff.deletions,\n          files: diff.files,\n        });",
    marker='const diff = diffStatsFromToolResult(toolResult);',
)
# Emit the lead agent completion immediately before each successful done.
replace_once(
    path,
    "          writeNdjson(res, {\n            type: 'done',\n            requestId: prepared.requestId,\n            answer: streamed.full,\n            toolResults,\n          });",
    "          const totalDiff = aggregateDiffStats(toolResults);\n          writeNdjson(res, {\n            type: 'agent',\n            phase: 'result',\n            name: prepared.persona,\n            role: 'lead',\n            additions: totalDiff.additions,\n            deletions: totalDiff.deletions,\n            files: totalDiff.files,\n          });\n          writeNdjson(res, {\n            type: 'done',\n            requestId: prepared.requestId,\n            answer: streamed.full,\n            toolResults,\n          });",
    marker='const totalDiff = aggregateDiffStats(toolResults);',
)
replace_once(
    path,
    "      writeNdjson(res, {\n        type: 'done',\n        requestId: prepared.requestId,\n        answer: finalStream.full,\n        toolResults,\n      });",
    "      const totalDiff = aggregateDiffStats(toolResults);\n      writeNdjson(res, {\n        type: 'agent',\n        phase: 'result',\n        name: prepared.persona,\n        role: 'lead',\n        additions: totalDiff.additions,\n        deletions: totalDiff.deletions,\n        files: totalDiff.files,\n      });\n      writeNdjson(res, {\n        type: 'done',\n        requestId: prepared.requestId,\n        answer: finalStream.full,\n        toolResults,\n      });",
    marker="answer: finalStream.full,\n        toolResults,\n      });\n      res.end();",
)

# ---------------------------------------------------------------------------
# GitHub file writes: exact commit diff stats from GitHub itself.
# ---------------------------------------------------------------------------
path = 'server/pb_hooks/wesi_ai_github_connector.js'
old = r'''      const saved=api(e,ctx,input,name,"PUT",prefix+"/contents/"+p.split("/").map(encodeURIComponent).join("/"),null,payload);
      const d=json(saved)||{}; return {ok:true,result:external({path:p,branch:target,contentSha:String(d.content&&d.content.sha||""),commitSha:String(d.commit&&d.commit.sha||"")})};'''
new = r'''      const saved=api(e,ctx,input,name,"PUT",prefix+"/contents/"+p.split("/").map(encodeURIComponent).join("/"),null,payload);
      const d=json(saved)||{}, commitSha=String(d.commit&&d.commit.sha||"");
      let additions=0,deletions=0,files=[],diffKnown=false;
      if(/^[a-f0-9]{40,64}$/i.test(commitSha)){
        try{
          const detail=api(e,ctx,input,name,"GET",prefix+"/commits/"+encodeURIComponent(commitSha),null,null);
          const commit=json(detail)||{}, rows=Array.isArray(commit.files)?commit.files:[];
          const changed=rows.find((item)=>String(item&&item.filename||"")===p);
          if(changed){
            additions=Math.max(0,Number(changed.additions||0)||0);
            deletions=Math.max(0,Number(changed.deletions||0)||0);
            files=[p];
            diffKnown=true;
          }
        }catch(_){ /* write already succeeded; diff enrichment is best effort */ }
      }
      return {ok:true,result:external({path:p,branch:target,contentSha:String(d.content&&d.content.sha||""),commitSha,additions,deletions,files,diffKnown})};'''
replace_once(path, old, new, marker='diffKnown=true;')

# ---------------------------------------------------------------------------
# Tests.
# ---------------------------------------------------------------------------
path = 'server/wesi-ai-stream/gateway.test.mjs'
replace_once(
    path,
    "    assert.deepEqual(events.map((event) => event.type), ['meta', 'delta', 'delta', 'done']);",
    "    assert.deepEqual(events.map((event) => event.type), ['meta', 'agent', 'activity', 'delta', 'delta', 'agent', 'done']);",
    marker="['meta', 'agent', 'activity', 'delta'",
)
replace_once(
    path,
    "        toolResult: {tool: 'tasks_list', verified: true, ok: true, result: {tasks: []}},",
    "        toolResult: {tool: 'tasks_list', verified: true, ok: true, result: {tasks: [], additions: 3, deletions: 1, files: ['lib/a.dart']}},",
    marker="additions: 3, deletions: 1",
)
insert_before(
    path,
    "    assert.equal(events.filter((event) => event.type === 'delta').map((event) => event.text).join(''), 'Задач нет.');",
    "    const toolResultEvent = events.find((event) => event.type === 'tool' && event.phase === 'result');\n    assert.equal(toolResultEvent.additions, 3);\n    assert.equal(toolResultEvent.deletions, 1);\n    assert.deepEqual(toolResultEvent.files, ['lib/a.dart']);\n    const leadDone = events.find((event) => event.type === 'agent' && event.phase === 'result');\n    assert.equal(leadDone.additions, 3);\n    assert.equal(leadDone.deletions, 1);\n",
    marker='const toolResultEvent = events.find',
)

write('test/wesi_ai_rich_message_test.dart', r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_activity.dart';
import 'package:wesios/features/ai/widgets/wesi_ai_rich_message.dart';

void main() {
  test('rich parser separates code quotes and removes markdown markers for copy', () {
    const source = '''
Обычный **жирный** текст.

```dart
void main() => print('ok');
```

> Готовое сообщение
> в две строки
''';
    final blocks = WesiAiRichParser.parse(source);
    expect(blocks.any((block) => block.kind == WesiAiRichBlockKind.code && block.language == 'dart'), isTrue);
    expect(blocks.any((block) => block.kind == WesiAiRichBlockKind.quote), isTrue);
    final plain = WesiAiRichParser.plainText(source);
    expect(plain, contains('жирный'));
    expect(plain, isNot(contains('**')));
  });

  test('activity model preserves per tool diff and source', () {
    final event = WesiAiActivityEvent.fromJson({
      'id': 'tool-1',
      'type': 'tool',
      'name': 'github_file_upsert',
      'phase': 'result',
      'textOffset': 18,
      'additions': 42,
      'deletions': 7,
      'files': ['lib/a.dart'],
    });
    expect(event, isNotNull);
    expect(event!.kind, WesiAiActivityKind.tool);
    expect(event.sourceName, 'github_file_upsert');
    expect(event.additions, 42);
    expect(event.deletions, 7);
    expect(event.files, ['lib/a.dart']);
  });

  testWidgets('code and quote blocks expose quick copy controls', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: WesiAiRichMessage(
          messageId: 'm1',
          text: '```dart\nprint(1);\n```\n\n> Скопируй меня',
        ),
      ),
    ));
    expect(find.text('dart'), findsOneWidget);
    expect(find.byTooltip('Копировать код'), findsOneWidget);
    expect(find.byTooltip('Копировать'), findsOneWidget);
  });

  testWidgets('live work log is expanded before final answer', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WesiAiRichMessage(
          messageId: 'm2',
          text: '',
          streaming: true,
          activityRaw: [
            {
              'id': 'r1',
              'kind': 'reasoning',
              'label': 'Контекст подготовлен',
            }
          ],
        ),
      ),
    ));
    expect(find.text('Ход работы…'), findsOneWidget);
    expect(find.text('Контекст подготовлен'), findsOneWidget);
  });
}
''')

write('docs/WESI_AI_CHAT_UX.md', r'''# Wesi AI — observable chat UX

Этот слой отвечает только за представление и наблюдаемость работы Wesi AI.

## Контент ответа

- fenced code рендерится отдельным code block с названием языка, быстрым копированием и полноэкранным просмотром;
- blockquote и fenced `text/message/email/draft/letter` рендерятся как переносимый текст с вертикальной линией и copy;
- inline `**bold**`, `*italic*`, `` `code` `` не показывают служебные markdown-маркеры;
- копирование полного ответа использует plain-text представление без markdown-обвязки.

## Ход работы

WesiOS не показывает скрытую chain-of-thought модели. Вместо неё UI показывает фактический work log: подготовку контекста, выбранный маршрут, инструментальные вызовы, агентов, проверки и статусы, которые реально пришли из streaming protocol. Пока ответ выполняется, блок раскрыт автоматически; после завершения его можно раскрыть вручную.

`tool` / `agent` activity хранит `textOffset`, поэтому renderer может вставлять событие в ту позицию ответа, в которой оно произошло. События сохраняются вместе с сообщением и переживают перезапуск приложения.

## Diff stats

Зелёное `+N` и красное `-N` — число добавленных/удалённых строк. Статистика хранится отдельно для каждого tool/agent event и агрегируется в message diff badge. Для `github_file_upsert` цифры берутся из GitHub commit detail после успешного PUT, а не вычисляются приблизительно на клиенте.

## Действия сообщения

Под завершённым ответом доступны: copy, сохранить/убрать из архива текущего чата, создать conversation branch от выбранного сообщения, открыть diff review. Архив не глобальный: сохранённые сообщения фильтруются только в пределах текущей conversation.

## Камера

Камера Wesi AI открывается модальным окном с ограниченной шириной/высотой. Внутренний `CameraPreview` продолжает использовать аппаратный aspect ratio, поэтому изображение не растягивается на весь экран и не деформируется.
''')

print('Wesi AI observable chat UX product slice generated')
