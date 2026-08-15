from pathlib import Path


def replace_once(text, old, new, label):
    if old not in text:
        raise SystemExit(f'missing anchor: {label}')
    return text.replace(old, new, 1)


# 1) Request-scoped memory snapshot: keep legacy API while adding project,
# rolling summary and task state. This avoids breaking existing WesiAiApi fakes.
p = Path('lib/features/ai/models/wesi_ai_chat_models.dart')
s = p.read_text(encoding='utf-8')
old = '''class WesiAiMemorySnapshot {
  final List<String> shared;
  final List<String> zane;
  final List<String> nirvana;
  const WesiAiMemorySnapshot({this.shared = const [], this.zane = const [], this.nirvana = const []});
  Map<String, dynamic> toJson() => {'shared': shared, 'zane': zane, 'nirvana': nirvana};
  factory WesiAiMemorySnapshot.fromJson(Map<String, dynamic> json) => WesiAiMemorySnapshot(shared: List<String>.from(json['shared'] as List? ?? const []), zane: List<String>.from(json['zane'] as List? ?? const []), nirvana: List<String>.from(json['nirvana'] as List? ?? const []));
}
'''
new = '''class WesiAiMemorySnapshot {
  final List<String> shared;
  final List<String> zane;
  final List<String> nirvana;
  final List<String> project;
  final String conversationSummary;
  final Map<String, dynamic> taskState;

  const WesiAiMemorySnapshot({
    this.shared = const <String>[],
    this.zane = const <String>[],
    this.nirvana = const <String>[],
    this.project = const <String>[],
    this.conversationSummary = '',
    this.taskState = const <String, dynamic>{},
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'shared': shared,
        'zane': zane,
        'nirvana': nirvana,
        if (project.isNotEmpty) 'project': project,
        if (taskState.isNotEmpty) 'taskState': taskState,
      };

  factory WesiAiMemorySnapshot.fromJson(Map<String, dynamic> json) =>
      WesiAiMemorySnapshot(
        shared: List<String>.from(json['shared'] as List? ?? const []),
        zane: List<String>.from(json['zane'] as List? ?? const []),
        nirvana: List<String>.from(json['nirvana'] as List? ?? const []),
        project: List<String>.from(json['project'] as List? ?? const []),
        conversationSummary: '${json['conversationSummary'] ?? ''}',
        taskState: Map<String, dynamic>.from(
          json['taskState'] as Map? ?? const <String, dynamic>{},
        ),
      );
}
'''
s = replace_once(s, old, new, 'memory snapshot')
p.write_text(s, encoding='utf-8')

# 2) Persist structured memory and migrate legacy lists without losing history.
p = Path('lib/features/ai/storage/wesi_ai_local_store.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    "import '../models/wesi_ai_chat_models.dart';\n",
    "import '../memory/wesi_ai_memory_models.dart';\nimport '../models/wesi_ai_chat_models.dart';\n",
    'memory model import',
)
s = replace_once(s, '  static const int schemaVersion = 2;', '  static const int schemaVersion = 3;', 'schema v3')
s = replace_once(
    s,
    '''  final List<WesiAiMessage> messages;
  final WesiAiMemorySnapshot memory;
''',
    '''  final List<WesiAiMessage> messages;
  final WesiAiMemorySnapshot memory;
  final List<WesiAiMemoryEntry> memoryEntries;
  final WesiAiMemorySettings memorySettings;
  final Map<String, WesiAiConversationMemoryState> conversationMemory;
''',
    'state memory fields',
)
s = replace_once(
    s,
    '''    required this.messages,
    required this.memory,
  });
''',
    '''    required this.messages,
    required this.memory,
    this.memoryEntries = const <WesiAiMemoryEntry>[],
    this.memorySettings = const WesiAiMemorySettings(),
    this.conversationMemory = const <String, WesiAiConversationMemoryState>{},
  });
''',
    'state ctor',
)
s = replace_once(
    s,
    '''        messages: const [],
        memory: const WesiAiMemorySnapshot(),
      );
''',
    '''        messages: const [],
        memory: const WesiAiMemorySnapshot(),
        memoryEntries: const <WesiAiMemoryEntry>[],
        memorySettings: const WesiAiMemorySettings(),
        conversationMemory:
            const <String, WesiAiConversationMemoryState>{},
      );
''',
    'state empty memory',
)
s = replace_once(
    s,
    '''    List<WesiAiMessage>? messages,
    WesiAiMemorySnapshot? memory,
  }) =>
''',
    '''    List<WesiAiMessage>? messages,
    WesiAiMemorySnapshot? memory,
    List<WesiAiMemoryEntry>? memoryEntries,
    WesiAiMemorySettings? memorySettings,
    Map<String, WesiAiConversationMemoryState>? conversationMemory,
  }) =>
''',
    'copy signature',
)
s = replace_once(
    s,
    '''        messages: messages ?? this.messages,
        memory: memory ?? this.memory,
      );
''',
    '''        messages: messages ?? this.messages,
        memory: memory ?? this.memory,
        memoryEntries: memoryEntries ?? this.memoryEntries,
        memorySettings: memorySettings ?? this.memorySettings,
        conversationMemory: conversationMemory ?? this.conversationMemory,
      );
''',
    'copy values',
)
s = replace_once(
    s,
    '''        'messages': messages.map((e) => e.toJson()).toList(),
        'memory': memory.toJson(),
      };
''',
    '''        'messages': messages.map((e) => e.toJson()).toList(),
        'memory': memory.toJson(),
        'memoryEntries': memoryEntries.map((e) => e.toJson()).toList(),
        'memorySettings': memorySettings.toJson(),
        'conversationMemory':
            conversationMemory.values.map((e) => e.toJson()).toList(),
      };
''',
    'state json',
)
anchor = '''    WesiAiMemorySnapshot memory = const WesiAiMemorySnapshot();
    try {
      final rawMemory = json['memory'];
      if (rawMemory is Map) {
        memory =
            WesiAiMemorySnapshot.fromJson(Map<String, dynamic>.from(rawMemory));
      }
    } catch (_) {}

'''
insert = anchor + '''    final memoryEntries = <WesiAiMemoryEntry>[];
    final rawMemoryEntries = json['memoryEntries'];
    if (rawMemoryEntries is List) {
      for (final raw in rawMemoryEntries.take(600)) {
        if (raw is! Map) continue;
        try {
          memoryEntries.add(WesiAiMemoryEntry.fromJson(
            Map<String, dynamic>.from(raw),
            expectedEmployeeId: expectedEmployeeId,
          ));
        } catch (_) {}
      }
    }

    // Schema 2 -> 3 migration. Legacy lists remain readable, but are copied
    // once into structured manual entries so no existing memory disappears.
    if (memoryEntries.isEmpty &&
        (memory.shared.isNotEmpty || memory.zane.isNotEmpty || memory.nirvana.isNotEmpty)) {
      final migratedAt = DateTime.fromMillisecondsSinceEpoch(0);
      var serial = 0;
      void migrate(WesiAiMemoryScope scope, List<String> values) {
        for (final raw in values) {
          final text = raw.trim();
          if (text.isEmpty || text.length > 2000) continue;
          serial++;
          memoryEntries.add(WesiAiMemoryEntry(
            id: 'mem_legacy_${scope.name}_$serial',
            employeeId: expectedEmployeeId,
            scope: scope,
            text: text,
            createdAt: migratedAt,
            updatedAt: migratedAt,
            manual: true,
            importance: 0.8,
          ));
        }
      }
      migrate(WesiAiMemoryScope.shared, memory.shared);
      migrate(WesiAiMemoryScope.zane, memory.zane);
      migrate(WesiAiMemoryScope.nirvana, memory.nirvana);
    }

    var memorySettings = const WesiAiMemorySettings();
    final rawMemorySettings = json['memorySettings'];
    if (rawMemorySettings is Map) {
      try {
        memorySettings = WesiAiMemorySettings.fromJson(
          Map<String, dynamic>.from(rawMemorySettings),
        );
      } catch (_) {}
    }

    final conversationMemory = <String, WesiAiConversationMemoryState>{};
    final rawConversationMemory = json['conversationMemory'];
    if (rawConversationMemory is List) {
      for (final raw in rawConversationMemory.take(400)) {
        if (raw is! Map) continue;
        try {
          final item = WesiAiConversationMemoryState.fromJson(
            Map<String, dynamic>.from(raw),
            knownConversationIds: conversationIds,
          );
          conversationMemory[item.conversationId] = item;
        } catch (_) {}
      }
    }

'''
s = replace_once(s, anchor, insert, 'parse structured memory')
s = replace_once(
    s,
    '''      messages: messages,
      memory: memory,
    );
''',
    '''      messages: messages,
      memory: memory,
      memoryEntries: List<WesiAiMemoryEntry>.unmodifiable(memoryEntries),
      memorySettings: memorySettings,
      conversationMemory:
          Map<String, WesiAiConversationMemoryState>.unmodifiable(
        conversationMemory,
      ),
    );
''',
    'return structured memory',
)
p.write_text(s, encoding='utf-8')

# 3) API semantics: summary is a real rolling conversation summary; project
# context is a separate field. Memory snapshot now carries retrieved project
# memories + task state.
p = Path('lib/features/ai/wesi_ai_api.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    "        'summary': projectContext(project),\n",
    "        'summary': memory.conversationSummary,\n        'projectContext': projectContext(project),\n",
    'chat request context split',
)
p.write_text(s, encoding='utf-8')

p = Path('lib/features/ai/wesi_ai_lobby_api.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    "      'summary': WesiAiApi.projectContext(project),\n",
    "      'summary': memory.conversationSummary,\n      'projectContext': WesiAiApi.projectContext(project),\n",
    'lobby context split',
)
p.write_text(s, encoding='utf-8')

# 4) Retrieval + automatic local-first memory processing + user controls.
p = Path('lib/features/ai/controllers/wesi_ai_chat_controller.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    "import '../media_engines/wesi_media_engine_runner.dart';\n",
    "import '../media_engines/wesi_media_engine_runner.dart';\nimport '../memory/wesi_ai_memory_api.dart';\nimport '../memory/wesi_ai_memory_engine.dart';\nimport '../memory/wesi_ai_memory_models.dart';\n",
    'memory imports',
)
s = replace_once(
    s,
    '''  final Set<String> _localMediaRuns = <String>{};
  bool _disposed = false;
''',
    '''  final Set<String> _localMediaRuns = <String>{};
  final Set<String> _memoryProcesses = <String>{};
  static const WesiAiMemoryApi _memoryApi = WesiAiMemoryApi();
  bool _disposed = false;
''',
    'memory process fields',
)
# Insert memory management helpers before addUserMessage.
anchor = '''  Future<void> addUserMessage(
'''
helpers = r'''  WesiAiMemorySettings get memorySettings => state.memorySettings;
  List<WesiAiMemoryEntry> get memoryEntries =>
      List<WesiAiMemoryEntry>.unmodifiable(state.memoryEntries);

  WesiAiConversationMemoryState conversationMemoryFor(String conversationId) =>
      state.conversationMemory[conversationId] ??
      WesiAiConversationMemoryState(conversationId: conversationId);

  Future<void> setAutoMemoryEnabled(bool enabled) async {
    state = state.copyWith(
      memorySettings:
          state.memorySettings.copyWith(autoMemoryEnabled: enabled),
    );
    await _persist();
  }

  Future<void> setActiveConversationMemoryEnabled(bool enabled) async {
    final conversation = state.activeConversation;
    if (conversation == null) return;
    await setConversationMemoryEnabled(conversation.id, enabled);
  }

  Future<void> setConversationMemoryEnabled(
    String conversationId,
    bool enabled,
  ) async {
    if (!state.conversations.any((item) => item.id == conversationId)) return;
    final current = conversationMemoryFor(conversationId);
    final next = <String, WesiAiConversationMemoryState>{
      ...state.conversationMemory,
      conversationId: current.copyWith(memoryEnabled: enabled),
    };
    state = state.copyWith(conversationMemory: next);
    await _persist();
  }

  Future<bool> addManualMemory(
    WesiAiMemoryScope scope,
    String rawText,
  ) async {
    final text = rawText.trim();
    if (text.isEmpty ||
        text.length > WesiAiMemoryEngine.maxMemoryTextLength ||
        WesiAiMemoryEngine.looksSensitive(text)) {
      return false;
    }
    final active = state.activeConversation;
    final projectId = scope == WesiAiMemoryScope.project
        ? active?.projectId
        : null;
    if (scope == WesiAiMemoryScope.project && projectId == null) return false;
    final now = DateTime.now();
    final candidate = WesiAiMemoryCandidate(
      scope: scope,
      text: text,
      importance: 1.0,
    );
    var entries = WesiAiMemoryEngine.mergeCandidates(
      existing: state.memoryEntries,
      candidates: <WesiAiMemoryCandidate>[candidate],
      employeeId: store.employeeId,
      sourceConversationId: active?.id ?? 'manual_memory',
      settings: state.memorySettings,
      projectId: projectId,
      now: now,
    );
    final normalized = WesiAiMemoryEngine.normalizeForDedup(text);
    entries = entries.map((entry) {
      if (entry.employeeId == store.employeeId &&
          entry.scope == scope &&
          (scope != WesiAiMemoryScope.project || entry.projectId == projectId) &&
          WesiAiMemoryEngine.normalizeForDedup(entry.text) == normalized) {
        return WesiAiMemoryEntry(
          id: entry.id,
          employeeId: entry.employeeId,
          scope: entry.scope,
          text: entry.text,
          createdAt: entry.createdAt,
          updatedAt: now,
          sourceConversationId: entry.sourceConversationId,
          projectId: entry.projectId,
          manual: true,
          pinned: entry.pinned,
          importance: 1.0,
        );
      }
      return entry;
    }).toList(growable: false);
    state = state.copyWith(memoryEntries: entries);
    await _persist();
    return true;
  }

  Future<void> deleteMemory(String id) async {
    final next = state.memoryEntries
        .where((entry) => entry.id != id)
        .toList(growable: false);
    if (next.length == state.memoryEntries.length) return;
    state = state.copyWith(memoryEntries: next);
    await _persist();
  }

  Future<void> clearMemoryScope(WesiAiMemoryScope scope) async {
    final activeProjectId = state.activeConversation?.projectId;
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

  WesiAiMemorySnapshot _memoryForRequest(
    WesiAiConversation conversation,
    String query,
  ) {
    final retrieved = WesiAiMemoryEngine.retrieve(
      entries: state.memoryEntries,
      employeeId: store.employeeId,
      persona: conversation.persona,
      query: query,
      settings: state.memorySettings,
      projectId: conversation.projectId,
    );
    final conversationMemory = conversationMemoryFor(conversation.id);
    return WesiAiMemorySnapshot(
      shared: retrieved.shared,
      zane: retrieved.zane,
      nirvana: retrieved.nirvana,
      project: retrieved.project,
      conversationSummary: conversationMemory.rollingSummary,
      taskState: conversationMemory.taskState,
    );
  }

  List<WesiAiMessage> _historyForRequest(
    String conversationId,
    List<WesiAiMessage> history,
  ) {
    final memory = conversationMemoryFor(conversationId);
    if (memory.rollingSummary.trim().isEmpty ||
        memory.summarizedMessageCount <= 0) {
      return history;
    }
    final textMessages = history
        .where((message) =>
            message.kind == WesiAiMessageKind.text &&
            message.author != WesiAiMessageAuthor.system)
        .toList(growable: false);
    final start = memory.summarizedMessageCount.clamp(0, textMessages.length);
    final unsummarized = textMessages.sublist(start);
    if (unsummarized.length <= 24) return unsummarized;
    return unsummarized.sublist(unsummarized.length - 24);
  }

  void _scheduleMemoryProcessing(
    WesiAiConversation conversation,
    String latestUserText,
  ) {
    if (api is! WesiAiLobbyApi || _memoryProcesses.contains(conversation.id)) {
      return;
    }
    final current = conversationMemoryFor(conversation.id);
    final textMessages = state
        .messagesFor(conversation.id)
        .where((message) =>
            message.kind == WesiAiMessageKind.text &&
            message.author != WesiAiMessageAuthor.system)
        .toList(growable: false);
    if (!WesiAiMemoryEngine.shouldProcess(
      settings: state.memorySettings,
      conversationMemory: current,
      currentTextMessageCount: textMessages.length,
      latestUserText: latestUserText,
    )) {
      return;
    }
    _memoryProcesses.add(conversation.id);
    unawaited(_processMemory(conversation, latestUserText).whenComplete(() {
      _memoryProcesses.remove(conversation.id);
    }));
  }

  Future<void> _processMemory(
    WesiAiConversation conversation,
    String latestUserText,
  ) async {
    try {
      final current = conversationMemoryFor(conversation.id);
      final textMessages = state
          .messagesFor(conversation.id)
          .where((message) =>
              message.kind == WesiAiMessageKind.text &&
              message.author != WesiAiMessageAuthor.system)
          .toList(growable: false);
      final start = current.summarizedMessageCount.clamp(0, textMessages.length);
      if (start >= textMessages.length) return;
      final pending = textMessages.sublist(start);
      final batch = pending.length <= 24
          ? pending
          : pending.sublist(0, 24);
      if (batch.isEmpty) return;
      final requestMemory = _memoryForRequest(conversation, latestUserText);
      final result = await _memoryApi.process(
        conversation: conversation,
        recentMessages: batch,
        previousSummary: current.rollingSummary,
        taskState: current.taskState,
        memory: requestMemory,
        project: _projectFor(conversation.projectId),
      );
      final entries = WesiAiMemoryEngine.mergeCandidates(
        existing: state.memoryEntries,
        candidates: result.memories,
        employeeId: store.employeeId,
        sourceConversationId: conversation.id,
        settings: state.memorySettings,
        projectId: conversation.projectId,
      );
      final nextConversationMemory = <String, WesiAiConversationMemoryState>{
        ...state.conversationMemory,
        conversation.id: current.copyWith(
          rollingSummary: result.summary,
          taskState: result.taskState,
          summarizedMessageCount: start + batch.length,
        ),
      };
      state = state.copyWith(
        memoryEntries: entries,
        conversationMemory: nextConversationMemory,
      );
      await _persist();
    } catch (_) {
      // Memory is auxiliary. A failed compaction must never turn a successful
      // user chat into an error or block Smart Queue draining.
    }
  }

'''
s = replace_once(s, anchor, helpers + anchor, 'memory controller helpers')
# Prepare request context from full history before adding current user message.
s = replace_once(
    s,
    '''    final history = state.messagesFor(c.id);
    final now = DateTime.now();
''',
    '''    final fullHistory = state.messagesFor(c.id);
    final history = _historyForRequest(c.id, fullHistory);
    final requestMemory = _memoryForRequest(c, clean);
    final now = DateTime.now();
''',
    'request memory context',
)
s = replace_once(
    s,
    '        memory: state.memory,\n',
    '        memory: requestMemory,\n',
    'base chat request memory',
)
# Schedule after successful final assistant state is ready.
s = replace_once(
    s,
    '''      streamVisible = false;
      _startPendingMedia(assistant);
''',
    '''      streamVisible = false;
      _startPendingMedia(assistant);
      _scheduleMemoryProcessing(updated, clean);
''',
    'schedule memory after chat',
)
p.write_text(s, encoding='utf-8')

# 5) Lobby uses the same retrieval/summaries and automatic memory processing.
p = Path('lib/features/ai/wesi_ai_lobby_controller.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    '''    final history = state.messagesFor(conversation.id);
    final now = DateTime.now();
''',
    '''    final fullHistory = state.messagesFor(conversation.id);
    final history = memoryHistoryForRequest(conversation.id, fullHistory);
    final requestMemory = memoryForRequest(conversation, clean);
    final now = DateTime.now();
''',
    'lobby request memory',
)
s = replace_once(
    s,
    '        memory: state.memory,\n',
    '        memory: requestMemory,\n',
    'lobby request snapshot',
)
# Need inherited protected wrappers with public names. We'll patch base private
# helper names below so Lobby can call them safely.
s = replace_once(
    s,
    '''      state = state.copyWith(messages: [...state.messages, ...messages]);
''',
    '''      state = state.copyWith(messages: [...state.messages, ...messages]);
      scheduleMemoryProcessing(updated, clean);
''',
    'lobby schedule memory',
)
p.write_text(s, encoding='utf-8')

# Expose three internal helpers to subclasses (same library-level behavior,
# explicit non-private names avoids duplicating retrieval in Lobby).
p = Path('lib/features/ai/controllers/wesi_ai_chat_controller.dart')
s = p.read_text(encoding='utf-8')
s = s.replace('  WesiAiMemorySnapshot _memoryForRequest(\n', '  WesiAiMemorySnapshot memoryForRequest(\n')
s = s.replace('  List<WesiAiMessage> _historyForRequest(\n', '  List<WesiAiMessage> memoryHistoryForRequest(\n')
s = s.replace('  void _scheduleMemoryProcessing(\n', '  void scheduleMemoryProcessing(\n')
s = s.replace('_memoryForRequest(c, clean)', 'memoryForRequest(c, clean)')
s = s.replace('_historyForRequest(c.id, fullHistory)', 'memoryHistoryForRequest(c.id, fullHistory)')
s = s.replace('_scheduleMemoryProcessing(updated, clean)', 'scheduleMemoryProcessing(updated, clean)')
s = s.replace('_memoryForRequest(conversation, latestUserText)', 'memoryForRequest(conversation, latestUserText)')
p.write_text(s, encoding='utf-8')

# 6) Add Memory action to app bar.
p = Path('lib/features/ai/ai_assistant_v2_screen.dart')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    "import 'models/wesi_ai_chat_models.dart';\n",
    "import 'memory/wesi_ai_memory_sheet.dart';\nimport 'models/wesi_ai_chat_models.dart';\n",
    'memory sheet import',
)
anchor = '''          DropdownButtonHideUnderline(
'''
button = '''          IconButton(
            tooltip: 'Память Wesi AI',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => WesiAiMemorySheet(controller: controller),
            ),
            icon: const Icon(Icons.memory_rounded),
          ),
'''
s = replace_once(s, anchor, button + anchor, 'memory appbar button')
p.write_text(s, encoding='utf-8')

# 7) Server sanitizer + direct and stream contexts.
p = Path('server/pb_hooks/wesi_ai_lib.js')
s = p.read_text(encoding='utf-8')
old = '''  sanitizeMemory: function(memory) {
    const result = {shared: [], zane: [], nirvana: []};
    for (const key of ["shared", "zane", "nirvana"]) {
      const values = Array.isArray(memory[key]) ? memory[key] : [];
      result[key] = values.slice(0, 80).map(function(v) { return String(v).slice(0, 4000); });
    }
    return result;
  }
'''
new = '''  sanitizeMemory: function(memory) {
    const result = {shared: [], zane: [], nirvana: [], project: [], taskState: {}};
    for (const key of ["shared", "zane", "nirvana", "project"]) {
      const values = Array.isArray(memory[key]) ? memory[key] : [];
      result[key] = values.slice(0, 24).map(function(v) { return String(v).slice(0, 4000); });
    }
    try {
      const rawTask = memory.taskState && typeof memory.taskState === "object" && !Array.isArray(memory.taskState)
        ? JSON.stringify(memory.taskState)
        : "{}";
      if (rawTask.length <= 12000) result.taskState = JSON.parse(rawTask);
    } catch (_) {}
    return result;
  }
'''
s = replace_once(s, old, new, 'server memory sanitizer')
p.write_text(s, encoding='utf-8')

p = Path('server/pb_hooks/wesi_ai_routes.pb.js')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    '''  const summary = String(body.summary || "").trim();
  const activeOrganizationId = String(body.activeOrganizationId || "").trim();
''',
    '''  const summary = String(body.summary || "").trim();
  const projectContext = String(body.projectContext || "").trim();
  const activeOrganizationId = String(body.activeOrganizationId || "").trim();
''',
    'direct project context read',
)
s = replace_once(
    s,
    '''  if (summary.length > 64000 || history.length > 100) throw new BadRequestError("Слишком большой контекст Wesi AI");
''',
    '''  if (summary.length > 64000 || projectContext.length > 64000 || history.length > 100) throw new BadRequestError("Слишком большой контекст Wesi AI");
''',
    'direct context limit',
)
s = replace_once(
    s,
    '''  if (summary) systemParts.push("[WESI_AI_CONVERSATION_SUMMARY]\\n" + summary);
  if (cleanMemory.shared.length) systemParts.push("[WESI_AI_SHARED_MEMORY]\\n" + cleanMemory.shared.join("\\n"));
''',
    '''  if (summary) systemParts.push("[WESI_AI_CONVERSATION_SUMMARY]\\n" + summary);
  if (projectContext) systemParts.push("[WESI_AI_PROJECT_CONTEXT]\\n" + projectContext);
  if (cleanMemory.shared.length) systemParts.push("[WESI_AI_SHARED_MEMORY]\\n" + cleanMemory.shared.join("\\n"));
''',
    'direct summary project split',
)
s = replace_once(
    s,
    '''  if (personaMemory.length) systemParts.push("[WESI_AI_PERSONA_MEMORY]\\n" + personaMemory.join("\\n"));
  if (persona === "lobby") systemParts.push("[WESI_AI_LOBBY_MODE]\\n" + lobbyMode);
''',
    '''  if (personaMemory.length) systemParts.push("[WESI_AI_PERSONA_MEMORY]\\n" + personaMemory.join("\\n"));
  if (cleanMemory.project.length) systemParts.push("[WESI_AI_PROJECT_MEMORY]\\n" + cleanMemory.project.join("\\n"));
  if (Object.keys(cleanMemory.taskState || {}).length) systemParts.push("[WESI_AI_TASK_STATE]\\n" + JSON.stringify(cleanMemory.taskState));
  if (persona === "lobby") systemParts.push("[WESI_AI_LOBBY_MODE]\\n" + lobbyMode);
''',
    'direct project task memory',
)
p.write_text(s, encoding='utf-8')

p = Path('server/pb_hooks/wesi_ai_stream.pb.js')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    '''  const summary = String(body.summary || "").trim();
  const conversationId = String(body.conversationId || "").trim();
''',
    '''  const summary = String(body.summary || "").trim();
  const projectContext = String(body.projectContext || "").trim();
  const conversationId = String(body.conversationId || "").trim();
''',
    'stream project context read',
)
s = replace_once(
    s,
    '''  if (summary.length > 64000 || history.length > 100 || conversationId.length > 160) {
''',
    '''  if (summary.length > 64000 || projectContext.length > 64000 || history.length > 100 || conversationId.length > 160) {
''',
    'stream context limit',
)
s = replace_once(
    s,
    '''  if (summary) systemParts.push("[WESI_AI_CONVERSATION_SUMMARY]\\n" + summary);
  if (cleanMemory.shared.length) systemParts.push("[WESI_AI_SHARED_MEMORY]\\n" + cleanMemory.shared.join("\\n"));
''',
    '''  if (summary) systemParts.push("[WESI_AI_CONVERSATION_SUMMARY]\\n" + summary);
  if (projectContext) systemParts.push("[WESI_AI_PROJECT_CONTEXT]\\n" + projectContext);
  if (cleanMemory.shared.length) systemParts.push("[WESI_AI_SHARED_MEMORY]\\n" + cleanMemory.shared.join("\\n"));
''',
    'stream summary project split',
)
s = replace_once(
    s,
    '''  if (personaMemory.length) systemParts.push("[WESI_AI_PERSONA_MEMORY]\\n" + personaMemory.join("\\n"));
  if (cleanAttachments.length) {
''',
    '''  if (personaMemory.length) systemParts.push("[WESI_AI_PERSONA_MEMORY]\\n" + personaMemory.join("\\n"));
  if (cleanMemory.project.length) systemParts.push("[WESI_AI_PROJECT_MEMORY]\\n" + cleanMemory.project.join("\\n"));
  if (Object.keys(cleanMemory.taskState || {}).length) systemParts.push("[WESI_AI_TASK_STATE]\\n" + JSON.stringify(cleanMemory.taskState));
  if (cleanAttachments.length) {
''',
    'stream project task memory',
)
p.write_text(s, encoding='utf-8')

# Lobby server flow gets separate project context + project/task memories.
p = Path('server/pb_hooks/wesi_ai_lobby_core.js')
s = p.read_text(encoding='utf-8')
s = replace_once(
    s,
    '''    const memory = ai.sanitizeMemory(body.memory && typeof body.memory === "object" ? body.memory : {});
''',
    '''    const memory = ai.sanitizeMemory(body.memory && typeof body.memory === "object" ? body.memory : {});
    const projectContext = String(body.projectContext || "").trim();
    if (projectContext.length > 64000) return {status: 400, body: {ok: false, code: "WAI_BAD_LOBBY_REQUEST"}};
''',
    'lobby server project context',
)
s = replace_once(
    s,
    '''      const result = turn.run(ai, cfg, route, rootId + "_" + name, name, profile, message, history, memory.shared, personaMemory, messages, String(body.summary || ""));
''',
    '''      const result = turn.run(ai, cfg, route, rootId + "_" + name, name, profile, message, history, memory.shared, personaMemory, memory.project, memory.taskState, messages, String(body.summary || ""), projectContext);
''',
    'lobby turn args',
)
p.write_text(s, encoding='utf-8')

p = Path('server/pb_hooks/wesi_ai_lobby_turn.js')
s = p.read_text(encoding='utf-8')
old = '''  run: function(ai, cfg, route, requestId, personaName, profile, message, history, sharedMemory, personaMemory, priorTurns, summary) {
    const parts = [profile.prompt, "[WESI_AI_LOBBY]\\nYou are in shared Lobby. Speak only as yourself; never write lines for the other participant."];
    if (summary) parts.push("[WESI_AI_CONVERSATION_SUMMARY]\\n" + summary);
    if (sharedMemory.length) parts.push("[WESI_AI_SHARED_MEMORY]\\n" + sharedMemory.join("\\n"));
    if (personaMemory.length) parts.push("[WESI_AI_PERSONA_MEMORY]\\n" + personaMemory.join("\\n"));
    if (priorTurns.length) parts.push("[WESI_AI_CURRENT_LOBBY_TURNS]\\n" + JSON.stringify(priorTurns));
'''
new = '''  run: function(ai, cfg, route, requestId, personaName, profile, message, history, sharedMemory, personaMemory, projectMemory, taskState, priorTurns, summary, projectContext) {
    const parts = [profile.prompt, "[WESI_AI_LOBBY]\\nYou are in shared Lobby. Speak only as yourself; never write lines for the other participant."];
    if (summary) parts.push("[WESI_AI_CONVERSATION_SUMMARY]\\n" + summary);
    if (projectContext) parts.push("[WESI_AI_PROJECT_CONTEXT]\\n" + projectContext);
    if (sharedMemory.length) parts.push("[WESI_AI_SHARED_MEMORY]\\n" + sharedMemory.join("\\n"));
    if (personaMemory.length) parts.push("[WESI_AI_PERSONA_MEMORY]\\n" + personaMemory.join("\\n"));
    if (projectMemory.length) parts.push("[WESI_AI_PROJECT_MEMORY]\\n" + projectMemory.join("\\n"));
    if (taskState && Object.keys(taskState).length) parts.push("[WESI_AI_TASK_STATE]\\n" + JSON.stringify(taskState));
    if (priorTurns.length) parts.push("[WESI_AI_CURRENT_LOBBY_TURNS]\\n" + JSON.stringify(priorTurns));
'''
s = replace_once(s, old, new, 'lobby turn memory')
p.write_text(s, encoding='utf-8')
