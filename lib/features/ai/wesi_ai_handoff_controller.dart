import 'dart:math';

import 'models/wesi_ai_chat_models.dart';
import 'storage/wesi_ai_local_store.dart';
import 'wesi_ai_managed_controller.dart';

class WesiAiHandoffController extends WesiAiManagedChatController {
  WesiAiHandoffController({required WesiAiLocalStore store})
      : super(store: store);

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
