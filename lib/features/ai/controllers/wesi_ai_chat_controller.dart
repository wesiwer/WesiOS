import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/wesi_ai_chat_models.dart';
import '../storage/wesi_ai_local_store.dart';

class WesiAiChatController extends ChangeNotifier {
  final WesiAiLocalStore store;
  WesiAiLocalState state;
  bool loading = true;

  WesiAiChatController({required this.store}) : state = WesiAiLocalState.empty(store.employeeId);

  Future<void> load() async {
    state = await store.load();
    loading = false;
    notifyListeners();
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
      WesiAiPersona.lobby => 'Новое лобби',
    };
    final conversation = WesiAiConversation(id: id, employeeId: store.employeeId, title: title, persona: persona, createdAt: now, updatedAt: now);
    state = state.copyWith(conversations: [conversation, ...state.conversations], activeConversationId: id);
    await _persist();
  }

  Future<void> selectConversation(String id) async {
    final exists = state.conversations.any((c) => c.id == id && c.employeeId == store.employeeId);
    if (!exists) return;
    state = state.copyWith(activeConversationId: id);
    await _persist();
  }

  Future<void> addUserMessage(String text) async {
    final conversation = state.activeConversation;
    final clean = text.trim();
    if (conversation == null || clean.isEmpty) return;
    final now = DateTime.now();
    final message = WesiAiMessage(id: '${now.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}', conversationId: conversation.id, employeeId: store.employeeId, author: WesiAiMessageAuthor.user, text: clean, createdAt: now);
    final updatedConversation = conversation.copyWith(updatedAt: now, title: _titleFor(conversation, clean));
    final conversations = state.conversations.map((c) => c.id == conversation.id ? updatedConversation : c).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = state.copyWith(messages: [...state.messages, message], conversations: conversations);
    await _persist();
  }

  String _titleFor(WesiAiConversation conversation, String text) {
    final isDefault = conversation.title.startsWith('Новый ');
    if (!isDefault) return conversation.title;
    return text.length <= 42 ? text : '${text.substring(0, 42)}…';
  }

  Future<void> _persist() async {
    await store.save(state);
    notifyListeners();
  }
}
