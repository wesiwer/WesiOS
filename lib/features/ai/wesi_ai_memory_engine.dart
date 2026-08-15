import 'dart:math';

import 'models/wesi_ai_chat_models.dart';

class WesiAiMemoryEngine {
  static const int minMessagesForCompaction = 16;
  static const int recentMessagesToKeep = 8;
  static const int maxCompactionMessages = 28;

  const WesiAiMemoryEngine._();

  static WesiAiMemorySnapshot retrieve({
    required WesiAiMemorySnapshot memory,
    required WesiAiConversation conversation,
    required String query,
    String? taskId,
  }) {
    if (!memory.settings.enabled) {
      return WesiAiMemorySnapshot(
        settings: memory.settings,
        conversationSummary:
            memory.summaryFor(conversation.id)?.text ?? '',
      );
    }
    final queryTokens = _tokens(query);
    final projectId = conversation.projectId;
    final scored = <({WesiAiMemoryEntry entry, double score})>[];
    for (final entry in memory.entries) {
      if (!_scopeAllowed(memory.settings, entry.scope)) continue;
      if (!_matchesScope(entry, conversation, projectId, taskId)) continue;
      final textTokens = <String>{..._tokens(entry.text), ...entry.keywords};
      var overlap = 0;
      for (final token in queryTokens) {
        if (textTokens.contains(token)) overlap++;
      }
      final ageDays = max(
        0,
        DateTime.now().difference(entry.updatedAt).inHours / 24.0,
      );
      final recency = 1 / (1 + ageDays / 30);
      var score = entry.importance * 3 + recency;
      score += overlap * 2.2;
      if (entry.pinned) score += 8;
      if (entry.scope == WesiAiMemoryScope.project && projectId != null) {
        score += 2;
      }
      if (entry.scope == WesiAiMemoryScope.task && taskId != null) score += 3;
      scored.add((entry: entry, score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    final selected = scored
        .take(memory.settings.maxRetrievedEntries)
        .map((item) => item.entry)
        .toList(growable: false);

    final shared = <String>[];
    final zane = <String>[];
    final nirvana = <String>[];
    final project = <String>[];
    final task = <String>[];

    void addDistinct(List<String> target, String value, int maxItems) {
      final text = value.trim();
      if (text.isEmpty || target.contains(text) || target.length >= maxItems) return;
      target.add(text);
    }

    if (memory.settings.sharedMemory) {
      for (final legacy in memory.shared) {
        addDistinct(shared, legacy, 12);
      }
    }
    if (memory.settings.personaMemory) {
      if (conversation.persona == WesiAiPersona.zane ||
          conversation.persona == WesiAiPersona.lobby) {
        for (final legacy in memory.zane) {
          addDistinct(zane, legacy, 10);
        }
      }
      if (conversation.persona == WesiAiPersona.nirvana ||
          conversation.persona == WesiAiPersona.lobby) {
        for (final legacy in memory.nirvana) {
          addDistinct(nirvana, legacy, 10);
        }
      }
    }

    for (final entry in selected) {
      switch (entry.scope) {
        case WesiAiMemoryScope.shared:
          addDistinct(shared, entry.text, 16);
        case WesiAiMemoryScope.persona:
          if (entry.persona == 'nirvana') {
            addDistinct(nirvana, entry.text, 12);
          } else {
            addDistinct(zane, entry.text, 12);
          }
        case WesiAiMemoryScope.project:
          addDistinct(project, entry.text, 16);
        case WesiAiMemoryScope.task:
          addDistinct(task, entry.text, 16);
      }
    }

    return WesiAiMemorySnapshot(
      shared: List<String>.unmodifiable(shared),
      zane: List<String>.unmodifiable(zane),
      nirvana: List<String>.unmodifiable(nirvana),
      settings: memory.settings,
      project: List<String>.unmodifiable(project),
      task: List<String>.unmodifiable(task),
      conversationSummary: memory.summaryFor(conversation.id)?.text ?? '',
    );
  }

  static List<WesiAiMessage> historyForRequest({
    required WesiAiMemorySnapshot memory,
    required String conversationId,
    required List<WesiAiMessage> history,
  }) {
    final summary = memory.summaryFor(conversationId);
    if (summary == null || summary.text.trim().isEmpty) return history;
    var throughIndex = -1;
    for (var i = 0; i < history.length; i++) {
      if (history[i].id == summary.throughMessageId) throughIndex = i;
    }
    if (throughIndex < 0) {
      return history.length <= 24
          ? history
          : history.sublist(history.length - 24);
    }
    final remaining = history.sublist(min(history.length, throughIndex + 1));
    if (remaining.length >= recentMessagesToKeep) return remaining;
    final start = max(0, history.length - recentMessagesToKeep);
    return history.sublist(start);
  }

  static List<WesiAiMessage> compactionSlice({
    required WesiAiMemorySnapshot memory,
    required String conversationId,
    required List<WesiAiMessage> messages,
  }) {
    if (!memory.settings.enabled || !memory.settings.autoRemember) {
      return const <WesiAiMessage>[];
    }
    final textMessages = messages
        .where((message) =>
            message.kind == WesiAiMessageKind.text &&
            message.author != WesiAiMessageAuthor.system &&
            message.text.trim().isNotEmpty)
        .toList(growable: false);
    var start = 0;
    final previous = memory.summaryFor(conversationId);
    if (previous != null) {
      for (var i = 0; i < textMessages.length; i++) {
        if (textMessages[i].id == previous.throughMessageId) start = i + 1;
      }
    }
    final unsummarized = textMessages.sublist(min(start, textMessages.length));
    if (unsummarized.length < minMessagesForCompaction) {
      return const <WesiAiMessage>[];
    }
    final compactCount = min(
      maxCompactionMessages,
      max(0, unsummarized.length - recentMessagesToKeep),
    );
    if (compactCount <= 0) return const <WesiAiMessage>[];
    return unsummarized.take(compactCount).toList(growable: false);
  }

  static WesiAiMemorySnapshot mergeCompaction({
    required WesiAiMemorySnapshot memory,
    required String conversationId,
    required String throughMessageId,
    required WesiAiMemoryCompactionResult result,
    String? sourceMessageId,
  }) {
    final now = DateTime.now();
    final summaries = <WesiAiConversationSummary>[
      for (final current in memory.summaries)
        if (current.conversationId != conversationId) current,
      if (result.summary.trim().isNotEmpty)
        WesiAiConversationSummary(
          conversationId: conversationId,
          text: _limit(result.summary.trim(), 12000),
          throughMessageId: throughMessageId,
          updatedAt: now,
        ),
    ];

    final entries = <WesiAiMemoryEntry>[...memory.entries];
    for (final candidate in result.memories.take(8)) {
      final text = _limit(candidate.text.trim(), 4000);
      if (text.isEmpty || _looksSensitive(text)) continue;
      final normalized = _normalize(text);
      var duplicateIndex = -1;
      for (var i = 0; i < entries.length; i++) {
        final existing = entries[i];
        if (existing.scope == candidate.scope &&
            existing.persona == candidate.persona &&
            existing.projectId == candidate.projectId &&
            existing.taskId == candidate.taskId &&
            _normalize(existing.text) == normalized) {
          duplicateIndex = i;
          break;
        }
      }
      if (duplicateIndex >= 0) {
        final existing = entries[duplicateIndex];
        entries[duplicateIndex] = existing.copyWith(
          importance: max(existing.importance, candidate.importance),
          keywords: _mergeKeywords(existing.keywords, candidate.keywords),
          updatedAt: now,
        );
      } else {
        entries.add(WesiAiMemoryEntry(
          id: 'mem_${now.microsecondsSinceEpoch}_${entries.length}_${Random().nextInt(1 << 20)}',
          scope: candidate.scope,
          text: text,
          persona: candidate.persona,
          projectId: candidate.projectId,
          taskId: candidate.taskId,
          sourceConversationId: conversationId,
          sourceMessageId: sourceMessageId,
          keywords: _mergeKeywords(const <String>[], candidate.keywords),
          importance: candidate.importance.clamp(0.0, 1.0),
          automatic: true,
          createdAt: now,
          updatedAt: now,
        ));
      }
    }
    entries.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    final boundedEntries = entries.take(500).toList(growable: false);
    return memory.copyWith(
      entries: List<WesiAiMemoryEntry>.unmodifiable(boundedEntries),
      summaries: List<WesiAiConversationSummary>.unmodifiable(summaries),
    );
  }

  static WesiAiMemoryEntry? explicitMemory({
    required String message,
    required WesiAiConversation conversation,
  }) {
    final clean = message.trim();
    if (clean.isEmpty || _looksSensitive(clean)) return null;
    final patterns = <RegExp>[
      RegExp(r'^запомни(?:,|:)?\s*(?:что\s+)?(.+)$', caseSensitive: false),
      RegExp(r'^помни(?:,|:)?\s*(?:что\s+)?(.+)$', caseSensitive: false),
      RegExp(r'^remember(?:\s+that)?\s*[:,-]?\s*(.+)$', caseSensitive: false),
    ];
    String? remembered;
    for (final pattern in patterns) {
      final match = pattern.firstMatch(clean);
      if (match != null) {
        remembered = match.group(1)?.trim();
        break;
      }
    }
    if (remembered == null || remembered.isEmpty || remembered.length > 4000) {
      return null;
    }
    final projectScoped = conversation.projectId != null &&
        RegExp(r'(для\s+(этого\s+)?проекта|в\s+этом\s+проекте|for\s+(this\s+)?project)',
                caseSensitive: false)
            .hasMatch(clean);
    final now = DateTime.now();
    return WesiAiMemoryEntry(
      id: 'mem_${now.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
      scope: projectScoped
          ? WesiAiMemoryScope.project
          : WesiAiMemoryScope.shared,
      text: remembered,
      projectId: projectScoped ? conversation.projectId : null,
      sourceConversationId: conversation.id,
      keywords: _tokens(remembered).take(12).toList(growable: false),
      importance: 0.95,
      automatic: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  static bool _scopeAllowed(
    WesiAiMemorySettings settings,
    WesiAiMemoryScope scope,
  ) =>
      switch (scope) {
        WesiAiMemoryScope.shared => settings.sharedMemory,
        WesiAiMemoryScope.persona => settings.personaMemory,
        WesiAiMemoryScope.project => settings.projectMemory,
        WesiAiMemoryScope.task => settings.taskMemory,
      };

  static bool _matchesScope(
    WesiAiMemoryEntry entry,
    WesiAiConversation conversation,
    String? projectId,
    String? taskId,
  ) =>
      switch (entry.scope) {
        WesiAiMemoryScope.shared => true,
        WesiAiMemoryScope.persona =>
          conversation.persona == WesiAiPersona.lobby ||
              entry.persona == conversation.persona.name,
        WesiAiMemoryScope.project =>
          projectId != null && entry.projectId == projectId,
        WesiAiMemoryScope.task => taskId != null && entry.taskId == taskId,
      };

  static Set<String> _tokens(String text) => RegExp(
        r'[A-Za-zА-Яа-яЁё0-9_]{2,}',
      )
          .allMatches(text.toLowerCase())
          .map((match) => match.group(0)!)
          .toSet();

  static List<String> _mergeKeywords(List<String> a, List<String> b) {
    final result = <String>[];
    for (final raw in <String>[...a, ...b]) {
      final value = raw.trim().toLowerCase();
      if (value.isEmpty || value.length > 80 || result.contains(value)) continue;
      result.add(value);
      if (result.length >= 24) break;
    }
    return List<String>.unmodifiable(result);
  }

  static String _normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _limit(String text, int maxLength) =>
      text.length <= maxLength ? text : text.substring(0, maxLength);

  static bool _looksSensitive(String text) {
    final lower = text.toLowerCase();
    return RegExp(
      r'(password|парол|api[_ -]?key|token|токен|private[_ -]?key|secret|секрет|-----begin [a-z ]*private key)',
      caseSensitive: false,
    ).hasMatch(lower);
  }
}
