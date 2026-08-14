import 'dart:math';

import 'controllers/wesi_ai_chat_controller.dart';
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
  }) : super(store: store, api: api);

  @override
  Future<void> addUserMessage(
    String text, {
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
  }) async {
    final conversation = state.activeConversation;
    if (conversation == null || conversation.persona != WesiAiPersona.lobby) {
      return super.addUserMessage(text, attachments: attachments);
    }

    // Multimodal Lobby uses the canonical universal chat path. This avoids
    // the legacy dual-speaker codec ever dropping file bytes or pretending a
    // file was seen when it was not.
    if (attachments.isNotEmpty) {
      return super.addUserMessage(text, attachments: attachments);
    }

    final clean = text.trim();
    if (clean.isEmpty || sending) return;
    final history = state.messagesFor(conversation.id);
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
      final reply = await api.send(
        conversation: updated,
        tier: state.tier,
        message: clean,
        history: history,
        memory: state.memory,
      );
      final turns = WesiAiLobbyCodec.decode(reply.answer);
      if (turns.isEmpty) {
        throw const WesiAiApiException(
          'WAI_BAD_LOBBY_RESPONSE',
          'Lobby вернул некорректный ответ',
        );
      }
      final messages = <WesiAiMessage>[];
      for (var i = 0; i < turns.length; i++) {
        final at = DateTime.now().add(Duration(microseconds: i));
        messages.add(
          WesiAiMessage(
            id: _id(at),
            conversationId: conversation.id,
            employeeId: store.employeeId,
            author: turns[i].author,
            text: turns[i].text,
            createdAt: at,
            metadata: {'requestId': reply.requestId, 'lobby': true},
          ),
        );
      }
      state = state.copyWith(messages: [...state.messages, ...messages]);
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
            text: error.message,
            createdAt: at,
            metadata: {'code': error.code},
          ),
        ],
      );
    } finally {
      sending = false;
      await _save();
    }
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
    notifyListeners();
  }
}
