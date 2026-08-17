import 'dart:math';

import 'controllers/wesi_ai_chat_controller.dart';
import 'memory/wesi_ai_memory_api.dart';
import 'models/wesi_ai_attachment.dart';
import 'models/wesi_ai_chat_models.dart';
import 'storage/wesi_ai_local_store.dart';
import 'wesi_ai_api.dart';
import 'wesi_ai_lobby_api.dart';
import 'wesi_ai_lobby_codec.dart';

class WesiAiLobbyChatController extends WesiAiChatController {
  WesiAiLobbyChatController({
    required WesiAiLocalStore store,
    WesiAiApi api = const WesiAiLobbyApi(),
    WesiAiMemoryApi memoryApi = const WesiAiMemoryApi(),
  }) : super(store: store, api: api, memoryApi: memoryApi);

  @override
  Future<void> addUserMessage(
    String text, {
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
    bool thinkingMode = true,
  }) async {
    final conversation = state.activeConversation;
    if (conversation == null || conversation.persona != WesiAiPersona.lobby) {
      return super.addUserMessage(
        text,
        attachments: attachments,
        thinkingMode: thinkingMode,
      );
    }

    // Multimodal Lobby uses the canonical universal chat path. This avoids
    // the legacy dual-speaker codec ever dropping file bytes or pretending a
    // file was seen when it was not.
    if (attachments.isNotEmpty) {
      return super.addUserMessage(
        text,
        attachments: attachments,
        thinkingMode: thinkingMode,
      );
    }

    final clean = text.trim();
    if (clean.isEmpty || sending) return;
    final fullHistory = state.messagesFor(conversation.id);
    final history = historyForMemoryRequest(conversation.id, fullHistory);
    final now = DateTime.now();
    final user = WesiAiMessage(
      id: _id(now),
      conversationId: conversation.id,
      employeeId: store.employeeId,
      author: WesiAiMessageAuthor.user,
      text: clean,
      createdAt: now,
    );
    final updated = conversation.copyWith(
      updatedAt: now,
      title: _title(conversation, clean),
    );
    final conversations = state.conversations
        .map((c) => c.id == conversation.id ? updated : c)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = state.copyWith(
      messages: [...state.messages, user],
      conversations: conversations,
    );
    sending = true;
    await _save();
    try {
      final reply = await awaitInterruptible(api.send(
        conversation: updated,
        tier: state.tier,
        message: clean,
        history: history,
        memory: relevantMemoryFor(updated, clean),
        conversationSummary: conversationMemoryFor(updated.id).rollingSummary,
        taskState: conversationMemoryFor(updated.id).taskState,
      ));
      if (reply == null) return;
      final turns = WesiAiLobbyCodec.decode(reply.answer);
      if (turns.isEmpty) {
        throw const WesiAiApiException(
          'WAI_BAD_LOBBY_RESPONSE',
          'Lobby вернул некорректный ответ',
          stage: 'LOBBY',
          component: 'WesiAiLobbyCodec',
          operation: 'decode',
          lastSuccess: 'LOBBY_RESPONSE_RECEIVED',
        );
      }
      final messages = <WesiAiMessage>[];
      for (var i = 0; i < turns.length; i++) {
        final at = DateTime.now().add(Duration(microseconds: i));
        final actorActivity = _activityForTurn(
          turns[i],
          reply.requestId,
          at,
        );
        messages.add(
          WesiAiMessage(
            id: _id(at),
            conversationId: conversation.id,
            employeeId: store.employeeId,
            author: turns[i].author,
            text: turns[i].text,
            createdAt: at,
            metadata: <String, dynamic>{
              'requestId': reply.requestId,
              'lobby': true,
              'lobbyPersona': turns[i].author.name,
              'activity': <Map<String, dynamic>>[
                ...reply.activity,
                actorActivity,
              ],
            },
          ),
        );
      }
      state = state.copyWith(messages: [...state.messages, ...messages]);
      scheduleMemoryRefresh(updated, clean);
    } on WesiAiApiException catch (error) {
      final at = DateTime.now();
      state = state.copyWith(
        messages: [
          ...state.messages,
          WesiAiMessage(
            id: _id(at),
            conversationId: conversation.id,
            employeeId: store.employeeId,
            author: WesiAiMessageAuthor.system,
            kind: WesiAiMessageKind.error,
            text: error.displayMessage,
            createdAt: at,
            metadata: <String, dynamic>{
              'code': error.code,
              'diagnostic': error.diagnostic,
              if (error.requestId.isNotEmpty) 'requestId': error.requestId,
            },
          ),
        ],
      );
    } finally {
      sending = false;
      await _save();
    }
  }

  static Map<String, dynamic> _activityForTurn(
    WesiAiLobbyTurn turn,
    String requestId,
    DateTime at,
  ) {
    final persona = switch (turn.author) {
      WesiAiMessageAuthor.zane => 'zane',
      WesiAiMessageAuthor.nirvana => 'nirvana',
      _ => 'unknown',
    };
    final label = switch (turn.author) {
      WesiAiMessageAuthor.zane => 'Отвечает Зейн',
      WesiAiMessageAuthor.nirvana => 'Отвечает Нирвана',
      _ => 'Ответ Lobby',
    };
    return <String, dynamic>{
      'kind': 'persona',
      'sourceName': label.replaceFirst('Отвечает ', ''),
      'persona': persona,
      'actorRole': 'lobby_participant',
      'label': label,
      'detail': 'Ответ сформирован отдельным участником Lobby: $persona.',
      'status': 'done',
      'completedAt': at.toUtc().toIso8601String(),
      if (requestId.isNotEmpty) 'requestId': requestId,
    };
  }

  Future<void> setLobbyMode(WesiAiLobbyMode mode) async {
    final active = state.activeConversation;
    if (active == null || active.persona != WesiAiPersona.lobby) return;
    state = state.copyWith(
      conversations: state.conversations
          .map((c) => c.id == active.id ? c.copyWith(lobbyMode: mode) : c)
          .toList(),
    );
    await _save();
  }

  String _id(DateTime at) =>
      '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';

  String _title(WesiAiConversation c, String text) =>
      !c.title.startsWith('Новый ')
          ? c.title
          : (text.length <= 42 ? text : '${text.substring(0, 42)}…');

  Future<void> _save() async {
    await store.save(state);
    notifyIfActive();
  }
}
