import 'dart:math';

import 'models/wesi_ai_chat_models.dart';
import 'storage/wesi_ai_local_store.dart';
import 'wesi_ai_managed_controller.dart';

class WesiAiHandoffController extends WesiAiManagedChatController {
  WesiAiHandoffController({required WesiAiLocalStore store}) : super(store: store);

  Future<String?> changePersonaInPlace(WesiAiPersona target) async {
    final source = state.activeConversation;
    if (source == null || sending) return null;
    if (source.persona == target) return source.id;

    final now = DateTime.now();
    final title = _titleForTarget(target, source.title);
    final updated = source.copyWith(
      persona: target,
      title: title,
      updatedAt: now,
    );
    final conversations = state.conversations
        .map((item) => item.id == source.id ? updated : item)
        .toList(growable: false);
    final status = WesiAiMessage(
      id: '${now.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
      conversationId: source.id,
      employeeId: store.employeeId,
      author: WesiAiMessageAuthor.system,
      kind: WesiAiMessageKind.status,
      text: _transitionLabel(source.persona, target),
      createdAt: now,
      metadata: {
        'personaTransition': true,
        'sameConversation': true,
        'fromPersona': source.persona.name,
        'toPersona': target.name,
      },
    );
    state = state.copyWith(
      conversations: conversations,
      messages: [...state.messages, status],
      activeConversationId: source.id,
    );
    await store.save(state);
    notifyListeners();
    return source.id;
  }

  Future<String?> forkToPersona(WesiAiPersona target) async {
    final source = state.activeConversation;
    if (source == null || sending) return null;

    final now = DateTime.now();
    final newId = '${now.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
    final textMessages = state
        .messagesFor(source.id)
        .where((message) => message.kind == WesiAiMessageKind.text)
        .toList();
    final context = textMessages.length <= 120
        ? textMessages
        : textMessages.sublist(textMessages.length - 120);

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
      text: 'Контекст продолжен из «${source.title}».',
      createdAt: now,
      metadata: {
        'handoff': true,
        'sameConversation': false,
        'fromConversationId': source.id,
        'fromPersona': source.persona.name,
        'toPersona': target.name,
        'copiedTextMessages': context.length,
      },
    ));

    final conversation = WesiAiConversation(
      id: newId,
      employeeId: store.employeeId,
      title: _titleForTarget(target, source.title),
      persona: target,
      createdAt: now,
      updatedAt: now,
      contextSummary: source.contextSummary,
      contextCompactedMessageCount: 0,
    );
    state = state.copyWith(
      conversations: [conversation, ...state.conversations],
      messages: [...state.messages, ...copied],
      activeConversationId: newId,
    );
    await store.save(state);
    notifyListeners();
    return newId;
  }

  Future<String?> handoffTo(WesiAiPersona target) => forkToPersona(target);

  String _titleForTarget(WesiAiPersona target, String sourceTitle) {
    final prefix = switch (target) {
      WesiAiPersona.zane => 'Зейн',
      WesiAiPersona.nirvana => 'Нирвана',
      WesiAiPersona.lobby => 'Лобби',
    };
    final clean = sourceTitle
        .replaceFirst(RegExp(r'^(Зейн|Нирвана|Лобби)\s*·\s*'), '')
        .trim();
    return '$prefix · $clean';
  }

  String _transitionLabel(WesiAiPersona from, WesiAiPersona to) {
    if (to == WesiAiPersona.lobby) {
      final joined = from == WesiAiPersona.zane ? 'Нирвана' : 'Зейн';
      return '$joined подключается к этому диалогу.';
    }
    if (from == WesiAiPersona.lobby) {
      final left = to == WesiAiPersona.zane ? 'Нирвана' : 'Зейн';
      return '$left покидает диалог. Разговор продолжается без потери контекста.';
    }
    final name = to == WesiAiPersona.zane ? 'Зейн' : 'Нирвана';
    return '$name продолжает этот же диалог с сохранённым контекстом.';
  }
}
