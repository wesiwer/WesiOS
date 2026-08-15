import 'dart:math';

import '../models/wesi_ai_chat_models.dart';
import 'wesi_ai_memory_models.dart';

class WesiAiRetrievedMemory {
  final List<String> shared;
  final List<String> zane;
  final List<String> nirvana;
  final List<String> project;

  const WesiAiRetrievedMemory({
    this.shared = const <String>[],
    this.zane = const <String>[],
    this.nirvana = const <String>[],
    this.project = const <String>[],
  });

  WesiAiMemorySnapshot toSnapshot() => WesiAiMemorySnapshot(
        shared: shared,
        zane: zane,
        nirvana: nirvana,
        project: project,
      );
}

class WesiAiMemoryEngine {
  static const int maxMemoryTextLength = 2000;
  static const int maxAutoCandidatesPerCycle = 8;

  static final RegExp _word = RegExp(
    r'[A-Za-zА-Яа-яЁё0-9_]{2,}',
    unicode: true,
  );

  static const Set<String> _stopWords = <String>{
    'это',
    'как',
    'что',
    'чтобы',
    'для',
    'или',
    'если',
    'при',
    'про',
    'его',
    'ее',
    'её',
    'их',
    'мне',
    'мой',
    'моя',
    'мои',
    'надо',
    'нужно',
    'будет',
    'уже',
    'только',
    'the',
    'and',
    'for',
    'with',
    'this',
    'that',
    'from',
    'are',
    'was',
    'were',
  };

  static final List<RegExp> _secretPatterns = <RegExp>[
    RegExp(
        r'\b(?:api[_ -]?key|access[_ -]?token|refresh[_ -]?token|password|парол[ья]|токен)\b\s*[:=]\s*\S+',
        caseSensitive: false),
    RegExp(r'\bBearer\s+[A-Za-z0-9._~+\-/]+=*', caseSensitive: false),
    RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----', caseSensitive: false),
    RegExp(r'\bgh[pousr]_[A-Za-z0-9]{20,}\b'),
    RegExp(r'\bAIza[A-Za-z0-9_-]{20,}\b'),
  ];

  static bool looksSensitive(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return false;
    return _secretPatterns.any((pattern) => pattern.hasMatch(clean));
  }

  static String normalizeForDedup(String text) => text
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[^a-zа-яё0-9 ]', caseSensitive: false), '')
      .trim();

  static Set<String> _tokens(String text) => _word
      .allMatches(text.toLowerCase())
      .map((match) => match.group(0)!)
      .where((token) => !_stopWords.contains(token))
      .toSet();

  static WesiAiRetrievedMemory retrieve({
    required List<WesiAiMemoryEntry> entries,
    required String employeeId,
    required WesiAiPersona persona,
    required String query,
    required WesiAiMemorySettings settings,
    String? projectId,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final queryTokens = _tokens(query);
    final scored = <({WesiAiMemoryEntry entry, double score})>[];

    for (final entry in entries) {
      if (entry.employeeId != employeeId) continue;
      final allowed = switch (entry.scope) {
        WesiAiMemoryScope.shared => true,
        WesiAiMemoryScope.zane =>
          persona == WesiAiPersona.zane || persona == WesiAiPersona.lobby,
        WesiAiMemoryScope.nirvana =>
          persona == WesiAiPersona.nirvana || persona == WesiAiPersona.lobby,
        WesiAiMemoryScope.project =>
          projectId != null && entry.projectId == projectId,
      };
      if (!allowed) continue;

      final entryTokens = _tokens(entry.text);
      final overlap = queryTokens.isEmpty
          ? 0
          : entryTokens.intersection(queryTokens).length;
      final overlapRatio =
          queryTokens.isEmpty ? 0.0 : overlap / max(1, queryTokens.length);
      final ageDays = max(0, at.difference(entry.updatedAt).inDays);
      final recency = 1.0 / (1.0 + ageDays / 45.0);
      var score = overlapRatio * 8.0 + entry.importance * 2.0 + recency;
      if (entry.manual) score += 1.8;
      if (entry.pinned) score += 4.0;
      if (entry.scope == WesiAiMemoryScope.project) score += 0.7;

      if (overlap == 0 &&
          !entry.pinned &&
          !entry.manual &&
          queryTokens.isNotEmpty) {
        continue;
      }
      scored.add((entry: entry, score: score));
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.entry.updatedAt.compareTo(a.entry.updatedAt);
    });

    final selected = scored
        .take(settings.retrievalLimit)
        .map((item) => item.entry)
        .toList(growable: false);

    return WesiAiRetrievedMemory(
      shared: selected
          .where((entry) => entry.scope == WesiAiMemoryScope.shared)
          .map((entry) => entry.text)
          .toList(growable: false),
      zane: selected
          .where((entry) => entry.scope == WesiAiMemoryScope.zane)
          .map((entry) => entry.text)
          .toList(growable: false),
      nirvana: selected
          .where((entry) => entry.scope == WesiAiMemoryScope.nirvana)
          .map((entry) => entry.text)
          .toList(growable: false),
      project: selected
          .where((entry) => entry.scope == WesiAiMemoryScope.project)
          .map((entry) => entry.text)
          .toList(growable: false),
    );
  }

  static List<WesiAiMemoryEntry> mergeCandidates({
    required List<WesiAiMemoryEntry> existing,
    required List<WesiAiMemoryCandidate> candidates,
    required String employeeId,
    required String sourceConversationId,
    required WesiAiMemorySettings settings,
    String? projectId,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final next = <WesiAiMemoryEntry>[...existing];
    var serial = 0;

    for (final candidate in candidates.take(maxAutoCandidatesPerCycle)) {
      final text = candidate.text.trim();
      if (text.isEmpty ||
          text.length > maxMemoryTextLength ||
          looksSensitive(text)) {
        continue;
      }
      if (candidate.scope == WesiAiMemoryScope.project && projectId == null) {
        continue;
      }
      final normalized = normalizeForDedup(text);
      if (normalized.length < 4) continue;

      var duplicateIndex = -1;
      for (var index = 0; index < next.length; index++) {
        final entry = next[index];
        if (entry.employeeId != employeeId || entry.scope != candidate.scope) {
          continue;
        }
        if (candidate.scope == WesiAiMemoryScope.project &&
            entry.projectId != projectId) {
          continue;
        }
        if (normalizeForDedup(entry.text) == normalized) {
          duplicateIndex = index;
          break;
        }
      }

      if (duplicateIndex >= 0) {
        final old = next[duplicateIndex];
        next[duplicateIndex] = old.copyWith(
          text: text,
          updatedAt: at,
          sourceConversationId: sourceConversationId,
          importance: max(old.importance, candidate.importance),
        );
        continue;
      }

      serial++;
      final micros = at.microsecondsSinceEpoch + serial;
      next.add(WesiAiMemoryEntry(
        id: 'mem_${micros}_${normalized.hashCode.abs()}',
        employeeId: employeeId,
        scope: candidate.scope,
        text: text,
        createdAt: at,
        updatedAt: at,
        sourceConversationId: sourceConversationId,
        projectId:
            candidate.scope == WesiAiMemoryScope.project ? projectId : null,
        importance: candidate.importance.clamp(0.0, 1.0).toDouble(),
      ));
    }

    if (next.length <= settings.maxEntries) {
      return List<WesiAiMemoryEntry>.unmodifiable(next);
    }

    final sorted = <WesiAiMemoryEntry>[...next]..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        if (a.manual != b.manual) return a.manual ? -1 : 1;
        final importance = b.importance.compareTo(a.importance);
        if (importance != 0) return importance;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return List<WesiAiMemoryEntry>.unmodifiable(
      sorted.take(settings.maxEntries),
    );
  }

  static bool shouldProcess({
    required WesiAiMemorySettings settings,
    required WesiAiConversationMemoryState conversationMemory,
    required int currentTextMessageCount,
    required String latestUserText,
  }) {
    if (!settings.autoMemoryEnabled || !conversationMemory.memoryEnabled) {
      return false;
    }
    final normalized = latestUserText.trim().toLowerCase();
    final explicit = const <String>[
      'запомни',
      'запомнить',
      'помни',
      'remember',
      'save this to memory',
    ].any(normalized.contains);
    if (explicit) return true;
    return currentTextMessageCount -
            conversationMemory.summarizedMessageCount >=
        10;
  }
}
