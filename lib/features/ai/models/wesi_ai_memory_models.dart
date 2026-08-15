enum WesiAiMemoryScope { shared, persona, project, task }

class WesiAiMemoryEntry {
  final String id;
  final WesiAiMemoryScope scope;
  final String text;
  final String? persona;
  final String? projectId;
  final String? taskId;
  final String? sourceConversationId;
  final String? sourceMessageId;
  final List<String> keywords;
  final double importance;
  final bool pinned;
  final bool automatic;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WesiAiMemoryEntry({
    required this.id,
    required this.scope,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.persona,
    this.projectId,
    this.taskId,
    this.sourceConversationId,
    this.sourceMessageId,
    this.keywords = const <String>[],
    this.importance = 0.5,
    this.pinned = false,
    this.automatic = true,
  });

  WesiAiMemoryEntry copyWith({
    WesiAiMemoryScope? scope,
    String? text,
    String? persona,
    bool clearPersona = false,
    String? projectId,
    bool clearProject = false,
    String? taskId,
    bool clearTask = false,
    List<String>? keywords,
    double? importance,
    bool? pinned,
    bool? automatic,
    DateTime? updatedAt,
  }) =>
      WesiAiMemoryEntry(
        id: id,
        scope: scope ?? this.scope,
        text: text ?? this.text,
        persona: clearPersona ? null : (persona ?? this.persona),
        projectId: clearProject ? null : (projectId ?? this.projectId),
        taskId: clearTask ? null : (taskId ?? this.taskId),
        sourceConversationId: sourceConversationId,
        sourceMessageId: sourceMessageId,
        keywords: keywords ?? this.keywords,
        importance: importance ?? this.importance,
        pinned: pinned ?? this.pinned,
        automatic: automatic ?? this.automatic,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'scope': scope.name,
        'text': text,
        if (persona != null) 'persona': persona,
        if (projectId != null) 'projectId': projectId,
        if (taskId != null) 'taskId': taskId,
        if (sourceConversationId != null)
          'sourceConversationId': sourceConversationId,
        if (sourceMessageId != null) 'sourceMessageId': sourceMessageId,
        if (keywords.isNotEmpty) 'keywords': keywords,
        'importance': importance,
        'pinned': pinned,
        'automatic': automatic,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory WesiAiMemoryEntry.fromJson(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final text = '${json['text'] ?? ''}'.trim();
    final createdAt = DateTime.tryParse('${json['createdAt'] ?? ''}');
    final updatedAt = DateTime.tryParse('${json['updatedAt'] ?? ''}');
    var scope = WesiAiMemoryScope.shared;
    final rawScope = '${json['scope'] ?? 'shared'}';
    for (final candidate in WesiAiMemoryScope.values) {
      if (candidate.name == rawScope) scope = candidate;
    }
    if (id.isEmpty || id.length > 180 || text.isEmpty || text.length > 4000) {
      throw const FormatException('Invalid Wesi AI memory entry');
    }
    final rawKeywords = json['keywords'];
    final keywords = <String>[];
    if (rawKeywords is List) {
      for (final raw in rawKeywords.take(24)) {
        final value = '$raw'.trim().toLowerCase();
        if (value.isNotEmpty && value.length <= 80 && !keywords.contains(value)) {
          keywords.add(value);
        }
      }
    }
    final rawImportance = json['importance'];
    final importance = rawImportance is num
        ? rawImportance.toDouble().clamp(0.0, 1.0)
        : 0.5;
    return WesiAiMemoryEntry(
      id: id,
      scope: scope,
      text: text,
      persona: _cleanId(json['persona']),
      projectId: _cleanId(json['projectId']),
      taskId: _cleanId(json['taskId']),
      sourceConversationId: _cleanId(json['sourceConversationId']),
      sourceMessageId: _cleanId(json['sourceMessageId']),
      keywords: List<String>.unmodifiable(keywords),
      importance: importance,
      pinned: json['pinned'] == true,
      automatic: json['automatic'] != false,
      createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static String? _cleanId(Object? raw) {
    final value = '${raw ?? ''}'.trim();
    if (value.isEmpty || value.length > 180) return null;
    return value;
  }
}

class WesiAiConversationSummary {
  final String conversationId;
  final String text;
  final String throughMessageId;
  final DateTime updatedAt;

  const WesiAiConversationSummary({
    required this.conversationId,
    required this.text,
    required this.throughMessageId,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'conversationId': conversationId,
        'text': text,
        'throughMessageId': throughMessageId,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory WesiAiConversationSummary.fromJson(Map<String, dynamic> json) {
    final conversationId = '${json['conversationId'] ?? ''}'.trim();
    final text = '${json['text'] ?? ''}'.trim();
    final throughMessageId = '${json['throughMessageId'] ?? ''}'.trim();
    final updatedAt = DateTime.tryParse('${json['updatedAt'] ?? ''}');
    if (conversationId.isEmpty ||
        conversationId.length > 180 ||
        text.isEmpty ||
        text.length > 12000 ||
        throughMessageId.isEmpty ||
        throughMessageId.length > 180) {
      throw const FormatException('Invalid Wesi AI conversation summary');
    }
    return WesiAiConversationSummary(
      conversationId: conversationId,
      text: text,
      throughMessageId: throughMessageId,
      updatedAt: updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class WesiAiMemorySettings {
  final bool enabled;
  final bool autoRemember;
  final bool sharedMemory;
  final bool personaMemory;
  final bool projectMemory;
  final bool taskMemory;
  final int maxRetrievedEntries;

  const WesiAiMemorySettings({
    this.enabled = true,
    this.autoRemember = true,
    this.sharedMemory = true,
    this.personaMemory = true,
    this.projectMemory = true,
    this.taskMemory = true,
    this.maxRetrievedEntries = 12,
  });

  WesiAiMemorySettings copyWith({
    bool? enabled,
    bool? autoRemember,
    bool? sharedMemory,
    bool? personaMemory,
    bool? projectMemory,
    bool? taskMemory,
    int? maxRetrievedEntries,
  }) =>
      WesiAiMemorySettings(
        enabled: enabled ?? this.enabled,
        autoRemember: autoRemember ?? this.autoRemember,
        sharedMemory: sharedMemory ?? this.sharedMemory,
        personaMemory: personaMemory ?? this.personaMemory,
        projectMemory: projectMemory ?? this.projectMemory,
        taskMemory: taskMemory ?? this.taskMemory,
        maxRetrievedEntries:
            (maxRetrievedEntries ?? this.maxRetrievedEntries).clamp(4, 24),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enabled': enabled,
        'autoRemember': autoRemember,
        'sharedMemory': sharedMemory,
        'personaMemory': personaMemory,
        'projectMemory': projectMemory,
        'taskMemory': taskMemory,
        'maxRetrievedEntries': maxRetrievedEntries,
      };

  factory WesiAiMemorySettings.fromJson(Map<String, dynamic> json) =>
      WesiAiMemorySettings(
        enabled: json['enabled'] != false,
        autoRemember: json['autoRemember'] != false,
        sharedMemory: json['sharedMemory'] != false,
        personaMemory: json['personaMemory'] != false,
        projectMemory: json['projectMemory'] != false,
        taskMemory: json['taskMemory'] != false,
        maxRetrievedEntries:
            (json['maxRetrievedEntries'] as num?)?.toInt().clamp(4, 24) ?? 12,
      );
}

class WesiAiMemoryCandidate {
  final WesiAiMemoryScope scope;
  final String text;
  final String? persona;
  final String? projectId;
  final String? taskId;
  final List<String> keywords;
  final double importance;

  const WesiAiMemoryCandidate({
    required this.scope,
    required this.text,
    this.persona,
    this.projectId,
    this.taskId,
    this.keywords = const <String>[],
    this.importance = 0.5,
  });
}

class WesiAiMemoryCompactionResult {
  final String summary;
  final List<WesiAiMemoryCandidate> memories;

  const WesiAiMemoryCompactionResult({
    required this.summary,
    this.memories = const <WesiAiMemoryCandidate>[],
  });
}

class WesiAiMemorySnapshot {
  // Legacy lists remain readable/writable for backward compatibility with
  // pre-Stage-3 local state and older server bundles.
  final List<String> shared;
  final List<String> zane;
  final List<String> nirvana;
  final List<WesiAiMemoryEntry> entries;
  final List<WesiAiConversationSummary> summaries;
  final WesiAiMemorySettings settings;

  // These fields are transient retrieval context. Persisted state normally
  // keeps them empty; a request-scoped snapshot fills them before transport.
  final List<String> project;
  final List<String> task;
  final String conversationSummary;

  const WesiAiMemorySnapshot({
    this.shared = const <String>[],
    this.zane = const <String>[],
    this.nirvana = const <String>[],
    this.entries = const <WesiAiMemoryEntry>[],
    this.summaries = const <WesiAiConversationSummary>[],
    this.settings = const WesiAiMemorySettings(),
    this.project = const <String>[],
    this.task = const <String>[],
    this.conversationSummary = '',
  });

  WesiAiMemorySnapshot copyWith({
    List<String>? shared,
    List<String>? zane,
    List<String>? nirvana,
    List<WesiAiMemoryEntry>? entries,
    List<WesiAiConversationSummary>? summaries,
    WesiAiMemorySettings? settings,
    List<String>? project,
    List<String>? task,
    String? conversationSummary,
  }) =>
      WesiAiMemorySnapshot(
        shared: shared ?? this.shared,
        zane: zane ?? this.zane,
        nirvana: nirvana ?? this.nirvana,
        entries: entries ?? this.entries,
        summaries: summaries ?? this.summaries,
        settings: settings ?? this.settings,
        project: project ?? this.project,
        task: task ?? this.task,
        conversationSummary: conversationSummary ?? this.conversationSummary,
      );

  WesiAiConversationSummary? summaryFor(String conversationId) {
    for (final summary in summaries) {
      if (summary.conversationId == conversationId) return summary;
    }
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 2,
        'shared': shared,
        'zane': zane,
        'nirvana': nirvana,
        if (entries.isNotEmpty)
          'entries': entries.map((entry) => entry.toJson()).toList(),
        if (summaries.isNotEmpty)
          'summaries': summaries.map((summary) => summary.toJson()).toList(),
        'settings': settings.toJson(),
        if (project.isNotEmpty) 'project': project,
        if (task.isNotEmpty) 'task': task,
        if (conversationSummary.isNotEmpty)
          'conversationSummary': conversationSummary,
      };

  factory WesiAiMemorySnapshot.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key, {int max = 80}) => (json[key] as List? ?? const <dynamic>[])
        .take(max)
        .map((value) => '$value'.trim())
        .where((value) => value.isNotEmpty && value.length <= 4000)
        .toList(growable: false);

    final entries = <WesiAiMemoryEntry>[];
    final rawEntries = json['entries'];
    if (rawEntries is List) {
      for (final raw in rawEntries.take(500)) {
        if (raw is! Map) continue;
        try {
          entries.add(WesiAiMemoryEntry.fromJson(Map<String, dynamic>.from(raw)));
        } catch (_) {}
      }
    }
    final summaries = <WesiAiConversationSummary>[];
    final rawSummaries = json['summaries'];
    if (rawSummaries is List) {
      for (final raw in rawSummaries.take(200)) {
        if (raw is! Map) continue;
        try {
          summaries.add(WesiAiConversationSummary.fromJson(Map<String, dynamic>.from(raw)));
        } catch (_) {}
      }
    }
    var settings = const WesiAiMemorySettings();
    final rawSettings = json['settings'];
    if (rawSettings is Map) {
      try {
        settings = WesiAiMemorySettings.fromJson(Map<String, dynamic>.from(rawSettings));
      } catch (_) {}
    }
    return WesiAiMemorySnapshot(
      shared: strings('shared'),
      zane: strings('zane'),
      nirvana: strings('nirvana'),
      entries: List<WesiAiMemoryEntry>.unmodifiable(entries),
      summaries: List<WesiAiConversationSummary>.unmodifiable(summaries),
      settings: settings,
      project: strings('project', max: 40),
      task: strings('task', max: 40),
      conversationSummary: '${json['conversationSummary'] ?? ''}'.trim(),
    );
  }
}
