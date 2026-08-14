import 'dart:math';

import 'models/wesi_ai_chat_models.dart';
import 'storage/wesi_ai_local_store.dart';
import 'wesi_ai_lobby_controller.dart';

class WesiAiManagedChatController extends WesiAiLobbyChatController {
  WesiAiManagedChatController({required WesiAiLocalStore store}) : super(store: store);

  @override
  Future<void> createConversation(WesiAiPersona persona) async {
    final projectId = state.activeProjectId;
    await super.createConversation(persona);
    final id = state.activeConversationId;
    if (id == null || projectId == null) return;
    state = state.copyWith(
      conversations: state.conversations
          .map((conversation) => conversation.id == id
              ? conversation.copyWith(projectId: projectId)
              : conversation)
          .toList(growable: false),
    );
    await _save();
  }

  Future<String?> createProject(String title, {String description = '', String instructions = ''}) async {
    final clean = title.trim();
    if (sending || clean.isEmpty || clean.length > 120) return null;
    final now = DateTime.now();
    final id = 'project_${now.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
    final project = WesiAiProject(
      id: id,
      employeeId: store.employeeId,
      title: clean,
      description: description.trim().substring(0, min(description.trim().length, 2000)),
      instructions: instructions.trim().substring(0, min(instructions.trim().length, 8000)),
      createdAt: now,
      updatedAt: now,
    );
    state = state.copyWith(
      projects: <WesiAiProject>[project, ...state.projects],
      activeProjectId: id,
      clearActiveConversation: true,
    );
    await _save();
    return id;
  }

  Future<void> selectProject(String? id) async {
    if (sending) return;
    if (id != null && !state.projects.any((project) => project.id == id && !project.archived)) return;
    final active = state.activeConversation;
    final keepConversation = active != null && active.projectId == id && !active.archived;
    state = state.copyWith(
      activeProjectId: id,
      clearActiveProject: id == null,
      activeConversationId: keepConversation ? active.id : null,
      clearActiveConversation: !keepConversation,
    );
    await _save();
  }

  Future<void> renameProject(String id, String title) async {
    final clean = title.trim();
    if (sending || clean.isEmpty || clean.length > 120) return;
    var changed = false;
    final now = DateTime.now();
    final projects = state.projects.map((project) {
      if (project.id != id || project.employeeId != store.employeeId) return project;
      changed = true;
      return project.copyWith(title: clean, updatedAt: now);
    }).toList(growable: false);
    if (!changed) return;
    state = state.copyWith(projects: projects);
    await _save();
  }

  Future<void> updateProjectContext(String id, {required String description, required String instructions}) async {
    if (sending) return;
    final cleanDescription = description.trim();
    final cleanInstructions = instructions.trim();
    if (cleanDescription.length > 2000 || cleanInstructions.length > 8000) return;
    var changed = false;
    final projects = state.projects.map((project) {
      if (project.id != id || project.employeeId != store.employeeId) return project;
      changed = true;
      return project.copyWith(
        description: cleanDescription,
        instructions: cleanInstructions,
        updatedAt: DateTime.now(),
      );
    }).toList(growable: false);
    if (!changed) return;
    state = state.copyWith(projects: projects);
    await _save();
  }

  Future<void> toggleProjectPinned(String id) async {
    if (sending) return;
    var changed = false;
    final projects = state.projects.map((project) {
      if (project.id != id || project.employeeId != store.employeeId) return project;
      changed = true;
      return project.copyWith(pinned: !project.pinned, updatedAt: DateTime.now());
    }).toList(growable: false);
    if (!changed) return;
    state = state.copyWith(projects: projects);
    await _save();
  }

  Future<void> deleteProject(String id) async {
    if (sending) return;
    if (!state.projects.any((project) => project.id == id && project.employeeId == store.employeeId)) return;
    final projects = state.projects.where((project) => project.id != id).toList(growable: false);
    final conversations = state.conversations
        .map((conversation) => conversation.projectId == id
            ? conversation.copyWith(clearProject: true)
            : conversation)
        .toList(growable: false);
    final wasActive = state.activeProjectId == id;
    state = state.copyWith(
      projects: projects,
      conversations: conversations,
      clearActiveProject: wasActive,
      clearActiveConversation: wasActive,
    );
    await _save();
  }

  Future<void> moveConversationToProject(String conversationId, String? projectId) async {
    if (sending) return;
    if (projectId != null && !state.projects.any((project) => project.id == projectId && !project.archived)) return;
    var changed = false;
    final conversations = state.conversations.map((conversation) {
      if (conversation.id != conversationId || conversation.employeeId != store.employeeId) return conversation;
      changed = true;
      return conversation.copyWith(
        projectId: projectId,
        clearProject: projectId == null,
        updatedAt: DateTime.now(),
      );
    }).toList(growable: false);
    if (!changed) return;
    state = state.copyWith(conversations: conversations);
    await _save();
  }

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
    final next = conversations
        .where((c) => !c.archived && c.id != id && c.projectId == state.activeProjectId)
        .toList()
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
    WesiAiConversation? restored;
    final conversations = state.conversations.map((conversation) {
      if (conversation.id != id || conversation.employeeId != store.employeeId) return conversation;
      restored = conversation.copyWith(archived: false, updatedAt: DateTime.now());
      return restored!;
    }).toList();
    if (restored == null) return;
    state = state.copyWith(
      conversations: conversations,
      activeProjectId: restored!.projectId,
      clearActiveProject: restored!.projectId == null,
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
    final next = conversations
        .where((c) => !c.archived && c.projectId == state.activeProjectId)
        .toList()
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

  Future<void> clearLastError() async {
    if (sending) return;
    final conversation = state.activeConversation;
    if (conversation == null) return;
    final messages = state.messagesFor(conversation.id);
    if (messages.isEmpty || messages.last.kind != WesiAiMessageKind.error) return;
    final errorId = messages.last.id;
    state = state.copyWith(
      messages: state.messages.where((message) => message.id != errorId).toList(),
    );
    await _save();
  }

  Future<void> regenerateLastResponse() async {
    if (sending) return;
    final conversation = state.activeConversation;
    if (conversation == null) return;
    final ordered = state.messagesFor(conversation.id);
    var userIndex = -1;
    for (var i = ordered.length - 1; i >= 0; i--) {
      if (ordered[i].author == WesiAiMessageAuthor.user) {
        userIndex = i;
        break;
      }
    }
    if (userIndex < 0) return;
    final text = ordered[userIndex].text.trim();
    if (text.isEmpty) return;
    final removeIds = ordered.sublist(userIndex).map((m) => m.id).toSet();
    state = state.copyWith(
      messages: state.messages.where((message) => !removeIds.contains(message.id)).toList(),
    );
    await _save();
    await addUserMessage(text);
  }

  List<WesiAiProject> get visibleProjects {
    final items = state.projects.where((project) => !project.archived).toList();
    items.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return items;
  }

  List<WesiAiConversation> get visibleConversations {
    final items = state.conversations
        .where((c) => !c.archived && c.projectId == state.activeProjectId)
        .toList();
    items.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return items;
  }

  List<WesiAiConversation> get archivedConversations {
    final items = state.conversations
        .where((c) => c.archived && c.projectId == state.activeProjectId)
        .toList();
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  Future<void> _save() async {
    await store.save(state);
    notifyListeners();
  }
}
