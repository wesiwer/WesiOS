import 'models/wesi_ai_chat_models.dart';
import 'storage/wesi_ai_local_store.dart';
import 'wesi_ai_lobby_controller.dart';

class WesiAiManagedChatController extends WesiAiLobbyChatController {
  WesiAiManagedChatController({required WesiAiLocalStore store}) : super(store: store);

  Future<void> renameConversation(String id, String title) async {
    final clean = title.trim();
    if (sending || clean.isEmpty || clean.length > 120) return;
    var found = false;
    final conversations = state.conversations.map((conversation) {
      if (conversation.id != id || conversation.employeeId != store.employeeId) {
        return conversation;
      }
      found = true;
      return conversation.copyWith(title: clean, updatedAt: DateTime.now());
    }).toList();
    if (!found) return;
    state = state.copyWith(conversations: conversations);
    await _save();
  }

  Future<void> togglePinned(String id) async {
    if (sending) return;
    var found = false;
    final conversations = state.conversations.map((conversation) {
      if (conversation.id != id || conversation.employeeId != store.employeeId) {
        return conversation;
      }
      found = true;
      return conversation.copyWith(
        pinned: !conversation.pinned,
        updatedAt: DateTime.now(),
      );
    }).toList();
    if (!found) return;
    conversations.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    state = state.copyWith(conversations: conversations);
    await _save();
  }

  Future<void> archiveConversation(String id) async {
    if (sending) return;
    var found = false;
    final conversations = state.conversations.map((conversation) {
      if (conversation.id != id || conversation.employeeId != store.employeeId) {
        return conversation;
      }
      found = true;
      return conversation.copyWith(archived: true, updatedAt: DateTime.now());
    }).toList();
    if (!found) return;
    final next = conversations.where((c) => !c.archived && c.id != id).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = state.copyWith(
      conversations: conversations,
      activeConversationId:
          state.activeConversationId == id && next.isNotEmpty ? next.first.id : null,
      clearActiveConversation: state.activeConversationId == id && next.isEmpty,
    );
    await _save();
  }

  Future<void> restoreConversation(String id) async {
    if (sending) return;
    var found = false;
    final conversations = state.conversations.map((conversation) {
      if (conversation.id != id || conversation.employeeId != store.employeeId) {
        return conversation;
      }
      found = true;
      return conversation.copyWith(archived: false, updatedAt: DateTime.now());
    }).toList();
    if (!found) return;
    state = state.copyWith(
      conversations: conversations,
      activeConversationId: id,
    );
    await _save();
  }

  Future<void> deleteConversation(String id) async {
    if (sending) return;
    if (!state.conversations.any(
      (c) => c.id == id && c.employeeId == store.employeeId,
    )) {
      return;
    }
    final conversations = state.conversations.where((c) => c.id != id).toList();
    final messages = state.messages.where((m) => m.conversationId != id).toList();
    final next = conversations.where((c) => !c.archived).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final activeWasDeleted = state.activeConversationId == id;
    state = state.copyWith(
      conversations: conversations,
      messages: messages,
      activeConversationId:
          activeWasDeleted && next.isNotEmpty ? next.first.id : null,
      clearActiveConversation: activeWasDeleted && next.isEmpty,
    );
    await _save();
  }

  List<WesiAiConversation> get visibleConversations {
    final items = state.conversations.where((c) => !c.archived).toList();
    items.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return items;
  }

  List<WesiAiConversation> get archivedConversations {
    final items = state.conversations.where((c) => c.archived).toList();
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  Future<void> _save() async {
    await store.save(state);
    notifyListeners();
  }
}
