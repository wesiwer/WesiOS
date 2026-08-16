import 'dart:async';
import 'dart:math';

import 'models/wesi_ai_attachment.dart';
import 'models/wesi_ai_chat_models.dart';
import 'runtime/wesi_ai_answer_attention.dart';
import 'storage/wesi_ai_local_store.dart';
import 'wesi_ai_managed_controller.dart';

class WesiAiHandoffController extends WesiAiManagedChatController {
  WesiAiHandoffController({required WesiAiLocalStore store}) : super(store: store);

  @override
  Future<void> addUserMessage(
    String text, {
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
  }) async {
    final conversation = state.activeConversation;
    if (conversation == null) {
      await super.addUserMessage(text, attachments: attachments);
      return;
    }

    final beforeIds = state
        .messagesFor(conversation.id)
        .map((message) => message.id)
        .toSet();

    await super.addUserMessage(text, attachments: attachments);

    WesiAiMessage? answer;
    for (final message in state.messagesFor(conversation.id).reversed) {
      if (beforeIds.contains(message.id)) continue;
      if (message.author == WesiAiMessageAuthor.zane ||
          message.author == WesiAiMessageAuthor.nirvana) {
        answer = message;
        break;
      }
    }
    if (answer == null) return;

    var currentConversation = conversation;
    for (final item in state.conversations) {
      if (item.id == conversation.id) {
        currentConversation = item;
        break;
      }
    }
    final personaLabel = switch (currentConversation.persona) {
      WesiAiPersona.zane => 'Зейн',
      WesiAiPersona.nirvana => 'Нирвана',
      WesiAiPersona.lobby => 'Лобби',
    };
    final clean = answer.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final preview = clean.length <= 140 ? clean : '${clean.substring(0, 140)}…';

    unawaited(WesiAiAnswerAttention.complete(
      WesiAiAnswerReady(
        conversationId: currentConversation.id,
        conversationTitle: currentConversation.title,
        personaLabel: personaLabel,
        preview: preview,
        completedAt: answer.createdAt,
      ),
      // «Пользователь смотрит этот ответ» истинно только когда этот же
      // контроллер ещё жив и /ai действительно верхний route. Если старый
      // turn завершился после пересоздания AI-экрана, показываем плашку:
      // по нажатию новый экран загрузит уже сохранённый ответ из store.
      chatVisible: !isDisposed && WesiAiAnswerAttention.chatVisible,
    ));
  }

  /// Creates a new persona-owned conversation after the UI has obtained
  /// explicit user consent. The source chat remains intact.
  Future<String?> handoffTo(WesiAiPersona target) async {
    final source = state.activeConversation;
    if (source == null || sending || target == WesiAiPersona.lobby) return null;
    if (source.persona == target) return source.id;

    final now = DateTime.now();
    final newId = '${now.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
    final textMessages = state
        .messagesFor(source.id)
        .where((message) => message.kind == WesiAiMessageKind.text)
        .toList();
    final context = textMessages.length <= 90
        ? textMessages
        : textMessages.sublist(textMessages.length - 90);

    final copied = <WesiAiMessage>[];
    for (var i = 0; i < context.length; i++) {
      final original = context[i];
      copied.add(WesiAiMessage(
        id: '${newId}_handoff_$i',
        conversationId: newId,
        employeeId: store.employeeId,
        author: original.author,
        kind: WesiAiMessageKind.text,
        text: original.text,
        createdAt: original.createdAt,
        metadata: {
          ...original.metadata,
          'handoffFromConversationId': source.id,
          'handoffOriginalMessageId': original.id,
        },
      ));
    }

    copied.add(WesiAiMessage(
      id: '${newId}_handoff_status',
      conversationId: newId,
      employeeId: store.employeeId,
      author: WesiAiMessageAuthor.system,
      kind: WesiAiMessageKind.status,
      text: 'Контекст передан из «${source.title}».',
      createdAt: now,
      metadata: {
        'handoff': true,
        'fromConversationId': source.id,
        'fromPersona': source.persona.name,
        'toPersona': target.name,
        'copiedTextMessages': context.length,
      },
    ));

    final targetName = target == WesiAiPersona.zane ? 'Зейн' : 'Нирвана';
    final conversation = WesiAiConversation(
      id: newId,
      employeeId: store.employeeId,
      title: '$targetName · ${source.title}',
      persona: target,
      projectId: source.projectId,
      createdAt: now,
      updatedAt: now,
    );
    state = state.copyWith(
      conversations: [conversation, ...state.conversations],
      messages: [...state.messages, ...copied],
      activeConversationId: newId,
      activeProjectId: source.projectId,
      clearActiveProject: source.projectId == null,
    );
    await store.save(state);
    notifyIfActive();
    return newId;
  }
}
