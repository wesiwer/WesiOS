from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'missing patch anchor: {label}')
    return text.replace(old, new, 1)


# Fix numeric clamp typing in newly added models.
p = Path('lib/features/ai/memory/wesi_ai_memory_models.dart')
s = p.read_text(encoding='utf-8')
s = s.replace('importanceRaw.toDouble().clamp(0.0, 1.0)', 'importanceRaw.toDouble().clamp(0.0, 1.0).toDouble()')
s = s.replace('(retrievalLimit ?? this.retrievalLimit).clamp(4, 24)', '(retrievalLimit ?? this.retrievalLimit).clamp(4, 24).toInt()')
s = s.replace('(maxEntries ?? this.maxEntries).clamp(40, 600)', '(maxEntries ?? this.maxEntries).clamp(40, 600).toInt()')
s = s.replace("((json['retrievalLimit'] as num?)?.toInt() ?? 12).clamp(4, 24)", "((json['retrievalLimit'] as num?)?.toInt() ?? 12).clamp(4, 24).toInt()")
s = s.replace("((json['maxEntries'] as num?)?.toInt() ?? 240).clamp(40, 600)", "((json['maxEntries'] as num?)?.toInt() ?? 240).clamp(40, 600).toInt()")
p.write_text(s, encoding='utf-8')

# Extend transport memory snapshot with project-scoped retrieval.
p = Path('lib/features/ai/models/wesi_ai_chat_models.dart')
s = p.read_text(encoding='utf-8')
old = '''class WesiAiMemorySnapshot {
  final List<String> shared;
  final List<String> zane;
  final List<String> nirvana;
  const WesiAiMemorySnapshot({this.shared = const [], this.zane = const [], this.nirvana = const []});
  Map<String, dynamic> toJson() => {'shared': shared, 'zane': zane, 'nirvana': nirvana};
  factory WesiAiMemorySnapshot.fromJson(Map<String, dynamic> json) => WesiAiMemorySnapshot(shared: List<String>.from(json['shared'] as List? ?? const []), zane: List<String>.from(json['zane'] as List? ?? const []), nirvana: List<String>.from(json['nirvana'] as List? ?? const []));
}'''
new = '''class WesiAiMemorySnapshot {
  final List<String> shared;
  final List<String> zane;
  final List<String> nirvana;
  final List<String> project;
  const WesiAiMemorySnapshot({
    this.shared = const [],
    this.zane = const [],
    this.nirvana = const [],
    this.project = const [],
  });
  Map<String, dynamic> toJson() => {
        'shared': shared,
        'zane': zane,
        'nirvana': nirvana,
        if (project.isNotEmpty) 'project': project,
      };
  factory WesiAiMemorySnapshot.fromJson(Map<String, dynamic> json) =>
      WesiAiMemorySnapshot(
        shared: List<String>.from(json['shared'] as List? ?? const []),
        zane: List<String>.from(json['zane'] as List? ?? const []),
        nirvana: List<String>.from(json['nirvana'] as List? ?? const []),
        project: List<String>.from(json['project'] as List? ?? const []),
      );
}'''
s = replace_once(s, old, new, 'memory snapshot project scope')
p.write_text(s, encoding='utf-8')

# Local schema v3: structured entries/settings + per-conversation summary/task state.
p = Path('lib/features/ai/storage/wesi_ai_local_store.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(s, "import '../models/wesi_ai_chat_models.dart';\n", "import '../memory/wesi_ai_memory_models.dart';\nimport '../models/wesi_ai_chat_models.dart';\n", 'local memory import')
s = s.replace("static const int schemaVersion = 2;", "static const int schemaVersion = 3;")
s = replace_once(s,
'''  final List<WesiAiMessage> messages;
  final WesiAiMemorySnapshot memory;

  const WesiAiLocalState({''',
'''  final List<WesiAiMessage> messages;
  final WesiAiMemorySnapshot memory;
  final List<WesiAiMemoryEntry> memoryEntries;
  final WesiAiMemorySettings memorySettings;
  final Map<String, WesiAiConversationMemoryState> conversationMemory;

  const WesiAiLocalState({''', 'local state fields')
s = replace_once(s,
'''    required this.messages,
    required this.memory,
  });''',
'''    required this.messages,
    required this.memory,
    this.memoryEntries = const <WesiAiMemoryEntry>[],
    this.memorySettings = const WesiAiMemorySettings(),
    this.conversationMemory = const <String, WesiAiConversationMemoryState>{},
  });''', 'local state ctor')
s = replace_once(s,
'''        messages: const [],
        memory: const WesiAiMemorySnapshot(),
      );''',
'''        messages: const [],
        memory: const WesiAiMemorySnapshot(),
        memoryEntries: const <WesiAiMemoryEntry>[],
        memorySettings: const WesiAiMemorySettings(),
        conversationMemory:
            const <String, WesiAiConversationMemoryState>{},
      );''', 'empty memory state')
copy_sig = '''    List<WesiAiConversation>? conversations,
    List<WesiAiMessage>? messages,
    WesiAiMemorySnapshot? memory,
  }) =>'''
s = replace_once(s, copy_sig, '''    List<WesiAiConversation>? conversations,
    List<WesiAiMessage>? messages,
    WesiAiMemorySnapshot? memory,
    List<WesiAiMemoryEntry>? memoryEntries,
    WesiAiMemorySettings? memorySettings,
    Map<String, WesiAiConversationMemoryState>? conversationMemory,
  }) =>''', 'copy signature')
s = replace_once(s,
'''        messages: messages ?? this.messages,
        memory: memory ?? this.memory,
      );''',
'''        messages: messages ?? this.messages,
        memory: memory ??
            (memoryEntries == null
                ? this.memory
                : _snapshotFromEntries(memoryEntries)),
        memoryEntries: memoryEntries ?? this.memoryEntries,
        memorySettings: memorySettings ?? this.memorySettings,
        conversationMemory: conversationMemory ?? this.conversationMemory,
      );''', 'copy memory values')
method_anchor = '  WesiAiLocalState copyWith({'
helper = '''  static WesiAiMemorySnapshot _snapshotFromEntries(
    List<WesiAiMemoryEntry> entries,
  ) =>
      WesiAiMemorySnapshot(
        shared: entries
            .where((entry) => entry.scope == WesiAiMemoryScope.shared)
            .map((entry) => entry.text)
            .toList(growable: false),
        zane: entries
            .where((entry) => entry.scope == WesiAiMemoryScope.zane)
            .map((entry) => entry.text)
            .toList(growable: false),
        nirvana: entries
            .where((entry) => entry.scope == WesiAiMemoryScope.nirvana)
            .map((entry) => entry.text)
            .toList(growable: false),
      );

'''
s = replace_once(s, method_anchor, helper + method_anchor, 'snapshot helper')
s = replace_once(s,
'''        'messages': messages.map((e) => e.toJson()).toList(),
        'memory': memory.toJson(),
      };''',
'''        'messages': messages.map((e) => e.toJson()).toList(),
        'memory': _snapshotFromEntries(memoryEntries).toJson(),
        'memoryEntries': memoryEntries.map((entry) => entry.toJson()).toList(),
        'memorySettings': memorySettings.toJson(),
        'conversationMemory':
            conversationMemory.values.map((item) => item.toJson()).toList(),
      };''', 'state json memory')
old_tail = '''    WesiAiMemorySnapshot memory = const WesiAiMemorySnapshot();
    try {
      final rawMemory = json['memory'];
      if (rawMemory is Map) {
        memory =
            WesiAiMemorySnapshot.fromJson(Map<String, dynamic>.from(rawMemory));
      }
    } catch (_) {}

    return WesiAiLocalState(
      employeeId: expectedEmployeeId,
      tier: tier,
      activeConversationId: activeConversation?.id,
      activeProjectId: activeProjectId,
      projects: projects,
      conversations: conversations,
      messages: messages,
      memory: memory,
    );'''
new_tail = '''    WesiAiMemorySnapshot legacyMemory = const WesiAiMemorySnapshot();
    try {
      final rawMemory = json['memory'];
      if (rawMemory is Map) {
        legacyMemory =
            WesiAiMemorySnapshot.fromJson(Map<String, dynamic>.from(rawMemory));
      }
    } catch (_) {}

    final memoryEntries = <WesiAiMemoryEntry>[];
    final rawEntries = json['memoryEntries'];
    if (rawEntries is List) {
      for (final raw in rawEntries) {
        try {
          if (raw is! Map) continue;
          memoryEntries.add(WesiAiMemoryEntry.fromJson(
            Map<String, dynamic>.from(raw),
            expectedEmployeeId: expectedEmployeeId,
          ));
        } catch (_) {}
      }
    }
    if (memoryEntries.isEmpty) {
      final migratedAt = DateTime.now();
      void migrate(List<String> values, WesiAiMemoryScope scope) {
        for (var index = 0; index < values.length; index++) {
          final text = values[index].trim();
          if (text.isEmpty || text.length > 2000) continue;
          memoryEntries.add(WesiAiMemoryEntry(
            id: 'memory_migrated_${scope.name}_$index',
            employeeId: expectedEmployeeId,
            scope: scope,
            text: text,
            createdAt: migratedAt,
            updatedAt: migratedAt,
          ));
        }
      }
      migrate(legacyMemory.shared, WesiAiMemoryScope.shared);
      migrate(legacyMemory.zane, WesiAiMemoryScope.zane);
      migrate(legacyMemory.nirvana, WesiAiMemoryScope.nirvana);
    }

    var memorySettings = const WesiAiMemorySettings();
    try {
      final rawSettings = json['memorySettings'];
      if (rawSettings is Map) {
        memorySettings = WesiAiMemorySettings.fromJson(
          Map<String, dynamic>.from(rawSettings),
        );
      }
    } catch (_) {}

    final conversationMemory = <String, WesiAiConversationMemoryState>{};
    for (final conversation in conversations) {
      conversationMemory[conversation.id] = WesiAiConversationMemoryState(
        conversationId: conversation.id,
      );
    }
    final rawConversationMemory = json['conversationMemory'];
    if (rawConversationMemory is List) {
      for (final raw in rawConversationMemory) {
        try {
          if (raw is! Map) continue;
          final item = WesiAiConversationMemoryState.fromJson(
            Map<String, dynamic>.from(raw),
            knownConversationIds: conversationIds,
          );
          conversationMemory[item.conversationId] = item;
        } catch (_) {}
      }
    }

    return WesiAiLocalState(
      employeeId: expectedEmployeeId,
      tier: tier,
      activeConversationId: activeConversation?.id,
      activeProjectId: activeProjectId,
      projects: projects,
      conversations: conversations,
      messages: messages,
      memory: _snapshotFromEntries(memoryEntries),
      memoryEntries: List<WesiAiMemoryEntry>.unmodifiable(memoryEntries),
      memorySettings: memorySettings,
      conversationMemory:
          Map<String, WesiAiConversationMemoryState>.unmodifiable(
        conversationMemory,
      ),
    );'''
s = replace_once(s, old_tail, new_tail, 'local migration tail')
p.write_text(s, encoding='utf-8')

# Context package carries summary/task-state and only retrieved memories.
p = Path('lib/features/ai/wesi_ai_api.dart')
s = p.read_text(encoding='utf-8')
project_end = '''    return parts.join('\\n');
  }

  Future<WesiAiReply> send({'''
context_helper = '''    return parts.join('\\n');
  }

  static String contextPackage(
    WesiAiProject? project, {
    required String conversationSummary,
    required Map<String, dynamic> taskState,
  }) {
    final parts = <String>[];
    final projectText = projectContext(project);
    if (projectText.isNotEmpty) parts.add(projectText);
    final cleanSummary = conversationSummary.trim();
    if (cleanSummary.isNotEmpty) {
      parts.add('[WESI_AI_ROLLING_SUMMARY]\\n$cleanSummary');
    }
    if (taskState.isNotEmpty) {
      final encoded = jsonEncode(taskState);
      if (encoded.length <= 12000) {
        parts.add('[WESI_AI_TASK_STATE]\\n$encoded');
      }
    }
    return parts.join('\\n\\n');
  }

  Future<WesiAiReply> send({'''
s = replace_once(s, project_end, context_helper, 'context package helper')
s = replace_once(s,
'''    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],''',
'''    WesiAiProject? project,
    String conversationSummary = '',
    Map<String, dynamic> taskState = const <String, dynamic>{},
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],''', 'api memory signature')
s = replace_once(s,
"        'summary': projectContext(project),",
"        'summary': contextPackage(project, conversationSummary: conversationSummary, taskState: taskState),", 'api context package use')
p.write_text(s, encoding='utf-8')

# Base controller: relevant retrieval, background processing and user controls.
p = Path('lib/features/ai/controllers/wesi_ai_chat_controller.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(s,
"import '../media_engines/wesi_media_engine_runner.dart';\n",
"import '../media_engines/wesi_media_engine_runner.dart';\nimport '../memory/wesi_ai_memory_api.dart';\nimport '../memory/wesi_ai_memory_engine.dart';\nimport '../memory/wesi_ai_memory_models.dart';\n", 'controller memory imports')
s = replace_once(s,
'''  final Set<String> _localMediaRuns = <String>{};
  bool _disposed = false;''',
'''  final Set<String> _localMediaRuns = <String>{};
  final Set<String> _memoryRefreshes = <String>{};
  final WesiAiMemoryApi memoryApi = const WesiAiMemoryApi();
  bool _disposed = false;''', 'controller memory fields')
s = replace_once(s,
'''        history: history,
        memory: state.memory,
        project: _projectFor(updated.projectId),
        attachments: attachments,''',
'''        history: history,
        memory: relevantMemoryFor(updated, clean),
        project: _projectFor(updated.projectId),
        conversationSummary: conversationMemoryFor(updated.id).rollingSummary,
        taskState: conversationMemoryFor(updated.id).taskState,
        attachments: attachments,''', 'controller retrieved memory send')
s = replace_once(s,
'''      streamVisible = false;
      _startPendingMedia(assistant);''',
'''      streamVisible = false;
      _startPendingMedia(assistant);
      scheduleMemoryRefresh(updated, clean);''', 'schedule memory after response')
anchor = '  void _startPendingMedia(WesiAiMessage message) {'
helpers = r'''  @protected
  WesiAiConversationMemoryState conversationMemoryFor(String conversationId) =>
      state.conversationMemory[conversationId] ??
      WesiAiConversationMemoryState(conversationId: conversationId);

  @protected
  WesiAiMemorySnapshot relevantMemoryFor(
    WesiAiConversation conversation,
    String query,
  ) =>
      WesiAiMemoryEngine.retrieve(
        entries: state.memoryEntries,
        employeeId: store.employeeId,
        persona: conversation.persona,
        projectId: conversation.projectId,
        query: query,
        settings: state.memorySettings,
      ).toSnapshot();

  @protected
  void scheduleMemoryRefresh(
    WesiAiConversation conversation,
    String latestUserText,
  ) {
    if (!_memoryRefreshes.add(conversation.id)) return;
    unawaited(_refreshMemory(conversation, latestUserText).whenComplete(() {
      _memoryRefreshes.remove(conversation.id);
    }));
  }

  Future<void> _refreshMemory(
    WesiAiConversation conversation,
    String latestUserText,
  ) async {
    try {
      if (!state.conversations.any((item) => item.id == conversation.id)) return;
      final messages = state.messagesFor(conversation.id);
      final textMessages = messages
          .where((message) => message.kind == WesiAiMessageKind.text)
          .toList(growable: false);
      final conversationMemory = conversationMemoryFor(conversation.id);
      if (!WesiAiMemoryEngine.shouldProcess(
        settings: state.memorySettings,
        conversationMemory: conversationMemory,
        currentTextMessageCount: textMessages.length,
        latestUserText: latestUserText,
      )) {
        return;
      }
      final relevant = relevantMemoryFor(conversation, latestUserText);
      final result = await memoryApi.process(
        conversation: conversation,
        recentMessages: textMessages,
        previousSummary: conversationMemory.rollingSummary,
        taskState: conversationMemory.taskState,
        memory: relevant,
        project: _projectFor(conversation.projectId),
      );
      if (!state.conversations.any((item) => item.id == conversation.id)) return;
      final merged = WesiAiMemoryEngine.mergeCandidates(
        existing: state.memoryEntries,
        candidates: result.memories,
        employeeId: store.employeeId,
        sourceConversationId: conversation.id,
        projectId: conversation.projectId,
        settings: state.memorySettings,
      );
      final nextConversationMemory =
          Map<String, WesiAiConversationMemoryState>.from(
        state.conversationMemory,
      );
      nextConversationMemory[conversation.id] = conversationMemory.copyWith(
        rollingSummary: result.summary,
        taskState: result.taskState,
        summarizedMessageCount: textMessages.length,
      );
      state = state.copyWith(
        memoryEntries: merged,
        conversationMemory: nextConversationMemory,
      );
      await _persist();
    } catch (_) {
      // Memory enrichment is best-effort and must never fail the chat turn.
    }
  }

  Future<void> setAutoMemoryEnabled(bool enabled) async {
    state = state.copyWith(
      memorySettings: state.memorySettings.copyWith(autoMemoryEnabled: enabled),
    );
    await _persist();
  }

  Future<void> setActiveConversationMemoryEnabled(bool enabled) async {
    final conversation = state.activeConversation;
    if (conversation == null) return;
    final map = Map<String, WesiAiConversationMemoryState>.from(
      state.conversationMemory,
    );
    map[conversation.id] =
        conversationMemoryFor(conversation.id).copyWith(memoryEnabled: enabled);
    state = state.copyWith(conversationMemory: map);
    await _persist();
  }

  Future<bool> addManualMemory(
    WesiAiMemoryScope scope,
    String text,
  ) async {
    final clean = text.trim();
    if (clean.isEmpty ||
        clean.length > WesiAiMemoryEngine.maxMemoryTextLength ||
        WesiAiMemoryEngine.looksSensitive(clean)) {
      return false;
    }
    final projectId = state.activeProjectId;
    if (scope == WesiAiMemoryScope.project && projectId == null) return false;
    final normalized = WesiAiMemoryEngine.normalizeForDedup(clean);
    if (normalized.length < 4) return false;
    final now = DateTime.now();
    final entries = <WesiAiMemoryEntry>[...state.memoryEntries];
    for (var index = 0; index < entries.length; index++) {
      final old = entries[index];
      if (old.scope != scope ||
          (scope == WesiAiMemoryScope.project && old.projectId != projectId)) {
        continue;
      }
      if (WesiAiMemoryEngine.normalizeForDedup(old.text) == normalized) {
        entries[index] = old.copyWith(
          text: clean,
          updatedAt: now,
          manual: true,
          importance: 1,
        );
        state = state.copyWith(memoryEntries: entries);
        await _persist();
        return true;
      }
    }
    entries.add(WesiAiMemoryEntry(
      id: 'memory_manual_${now.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
      employeeId: store.employeeId,
      scope: scope,
      text: clean,
      createdAt: now,
      updatedAt: now,
      sourceConversationId: state.activeConversationId,
      projectId: scope == WesiAiMemoryScope.project ? projectId : null,
      manual: true,
      importance: 1,
    ));
    state = state.copyWith(memoryEntries: entries);
    await _persist();
    return true;
  }

  Future<void> deleteMemory(String id) async {
    final next = state.memoryEntries.where((entry) => entry.id != id).toList();
    if (next.length == state.memoryEntries.length) return;
    state = state.copyWith(memoryEntries: next);
    await _persist();
  }

  Future<void> clearMemoryScope(WesiAiMemoryScope scope) async {
    final activeProjectId = state.activeProjectId;
    final next = state.memoryEntries.where((entry) {
      if (entry.scope != scope) return true;
      if (scope == WesiAiMemoryScope.project) {
        return activeProjectId == null || entry.projectId != activeProjectId;
      }
      return false;
    }).toList(growable: false);
    state = state.copyWith(memoryEntries: next);
    await _persist();
  }

'''
s = replace_once(s, anchor, helpers + anchor, 'controller memory helpers')
p.write_text(s, encoding='utf-8')

# Lobby uses the same retrieval/summary and schedules memory after its multi-author result.
p = Path('lib/features/ai/wesi_ai_lobby_controller.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(s,
'''        history: history,
        memory: state.memory,
      ));''',
'''        history: history,
        memory: relevantMemoryFor(updated, clean),
        conversationSummary: conversationMemoryFor(updated.id).rollingSummary,
        taskState: conversationMemoryFor(updated.id).taskState,
      ));''', 'lobby memory context')
s = replace_once(s,
'''      state = state.copyWith(messages: [...state.messages, ...messages]);
    } on WesiAiApiException catch (error) {''',
'''      state = state.copyWith(messages: [...state.messages, ...messages]);
      scheduleMemoryRefresh(updated, clean);
    } on WesiAiApiException catch (error) {''', 'lobby memory schedule')
p.write_text(s, encoding='utf-8')

# Lobby API override + test fakes accept summary/taskState parameters.
p = Path('lib/features/ai/wesi_ai_lobby_api.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(s,
'''    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],''',
'''    WesiAiProject? project,
    String conversationSummary = '',
    Map<String, dynamic> taskState = const <String, dynamic>{},
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],''', 'lobby api signature')
s = s.replace(
'''        project: project,
        attachments: attachments,''',
'''        project: project,
        conversationSummary: conversationSummary,
        taskState: taskState,
        attachments: attachments,''')
p.write_text(s, encoding='utf-8')

for path in Path('test').glob('**/*.dart'):
    s = path.read_text(encoding='utf-8')
    if 'Future<WesiAiReply> send({' not in s:
        continue
    old = '''    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],'''
    new = '''    WesiAiProject? project,
    String conversationSummary = '',
    Map<String, dynamic> taskState = const <String, dynamic>{},
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],'''
    s = s.replace(old, new)
    path.write_text(s, encoding='utf-8')

# UI memory button.
p = Path('lib/features/ai/ai_assistant_v2_screen.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(s,
"import 'models/wesi_ai_chat_models.dart';\n",
"import 'memory/wesi_ai_memory_sheet.dart';\nimport 'models/wesi_ai_chat_models.dart';\n", 'memory sheet import')
s = replace_once(s,
'''        actions: [
          PopupMenuButton<WesiAiUiMode>(''',
'''        actions: [
          IconButton(
            tooltip: 'Память Wesi AI',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => WesiAiMemorySheet(controller: controller),
            ),
            icon: const Icon(Icons.memory_outlined),
          ),
          PopupMenuButton<WesiAiUiMode>(''', 'memory appbar button')
p.write_text(s, encoding='utf-8')

# Main server accepts project memory and injects it separately.
p = Path('server/pb_hooks/wesi_ai_lib.js')
s = p.read_text(encoding='utf-8')
s = replace_once(s,
'''    const result = {shared: [], zane: [], nirvana: []};
    for (const key of ["shared", "zane", "nirvana"]) {''',
'''    const result = {shared: [], zane: [], nirvana: [], project: []};
    for (const key of ["shared", "zane", "nirvana", "project"]) {''', 'server project memory sanitizer')
p.write_text(s, encoding='utf-8')

for file in ['server/pb_hooks/wesi_ai_routes.pb.js', 'server/pb_hooks/wesi_ai_stream.pb.js']:
    p = Path(file)
    s = p.read_text(encoding='utf-8')
    needle = '''  if (personaMemory.length) systemParts.push("[WESI_AI_PERSONA_MEMORY]\\n" + personaMemory.join("\\n"));'''
    replacement = needle + '''
  if (cleanMemory.project.length) systemParts.push("[WESI_AI_PROJECT_MEMORY]\\n" + cleanMemory.project.join("\\n"));'''
    s = replace_once(s, needle, replacement, f'project memory injection {file}')
    p.write_text(s, encoding='utf-8')
