import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/wesi_ai_chat_models.dart';
import '../storage/wesi_ai_local_store.dart';
import '../wesi_ai_api.dart';

class WesiAiChatController extends ChangeNotifier {
  final WesiAiLocalStore store;
  final WesiAiApi api;
  WesiAiLocalState state;
  bool loading = true;
  bool sending = false;
  WesiAiChatController({required this.store, this.api = const WesiAiApi()}) : state = WesiAiLocalState.empty(store.employeeId);
  Future<void> load() async { state = await store.load(); loading = false; notifyListeners(); }
  Future<void> setTier(WesiAiTier tier) async { state = state.copyWith(tier: tier); await _persist(); }
  Future<void> createConversation(WesiAiPersona persona) async {
    final now = DateTime.now(); final id = '${now.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
    final title = switch (persona) { WesiAiPersona.zane => 'Новый чат с Зейном', WesiAiPersona.nirvana => 'Новый чат с Нирваной', WesiAiPersona.lobby => 'Новое лобби' };
    final c = WesiAiConversation(id: id, employeeId: store.employeeId, title: title, persona: persona, createdAt: now, updatedAt: now);
    state = state.copyWith(conversations: [c, ...state.conversations], activeConversationId: id); await _persist();
  }
  Future<void> selectConversation(String id) async { if (!state.conversations.any((c) => c.id == id && c.employeeId == store.employeeId)) return; state = state.copyWith(activeConversationId: id); await _persist(); }
  Future<void> addUserMessage(String text) async {
    final c = state.activeConversation; final clean = text.trim(); if (c == null || clean.isEmpty || sending) return;
    final history = state.messagesFor(c.id); final now = DateTime.now();
    final user = WesiAiMessage(id: '${now.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}', conversationId: c.id, employeeId: store.employeeId, author: WesiAiMessageAuthor.user, text: clean, createdAt: now);
    final updated = c.copyWith(updatedAt: now, title: _titleFor(c, clean));
    final conversations = state.conversations.map((x) => x.id == c.id ? updated : x).toList()..sort((a,b) => b.updatedAt.compareTo(a.updatedAt));
    state = state.copyWith(messages: [...state.messages, user], conversations: conversations); sending = true; await _persist();
    try {
      final reply = await api.send(conversation: updated, tier: state.tier, message: clean, history: history, memory: state.memory); final at = DateTime.now();
      final author = switch (c.persona) { WesiAiPersona.zane => WesiAiMessageAuthor.zane, WesiAiPersona.nirvana => WesiAiMessageAuthor.nirvana, WesiAiPersona.lobby => WesiAiMessageAuthor.zane };
      state = state.copyWith(messages: [...state.messages, WesiAiMessage(id: '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}', conversationId: c.id, employeeId: store.employeeId, author: author, text: reply.answer, createdAt: at, metadata: {'requestId': reply.requestId})]);
    } on WesiAiApiException catch (e) {
      final at = DateTime.now(); state = state.copyWith(messages: [...state.messages, WesiAiMessage(id: '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}', conversationId: c.id, employeeId: store.employeeId, author: WesiAiMessageAuthor.system, kind: WesiAiMessageKind.error, text: e.message, createdAt: at, metadata: {'code': e.code})]);
    } finally { sending = false; await _persist(); }
  }
  String _titleFor(WesiAiConversation c, String text) { if (!c.title.startsWith('Новый ')) return c.title; return text.length <= 42 ? text : '${text.substring(0,42)}…'; }
  Future<void> _persist() async { await store.save(state); notifyListeners(); }
}
