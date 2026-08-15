import 'dart:convert';

enum WesiAiMemoryScope { shared, zane, nirvana, project }

class WesiAiMemoryEntry {
  final String id;
  final String employeeId;
  final WesiAiMemoryScope scope;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? sourceConversationId;
  final String? projectId;
  final bool manual;
  final bool pinned;
  final double importance;

  const WesiAiMemoryEntry({
    required this.id,
    required this.employeeId,
    required this.scope,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.sourceConversationId,
    this.projectId,
    this.manual = false,
    this.pinned = false,
    this.importance = 0.5,
  });

  WesiAiMemoryEntry copyWith({
    String? text,
    DateTime? updatedAt,
    String? sourceConversationId,
    String? projectId,
    bool clearProjectId = false,
    bool? manual,
    bool? pinned,
    double? importance,
  }) =>
      WesiAiMemoryEntry(
        id: id,
        employeeId: employeeId,
        scope: scope,
        text: text ?? this.text,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        sourceConversationId: sourceConversationId ?? this.sourceConversationId,
        projectId: clearProjectId ? null : (projectId ?? this.projectId),
        manual: manual ?? this.manual,
        pinned: pinned ?? this.pinned,
        importance: importance ?? this.importance,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'employeeId': employeeId,
        'scope': scope.name,
        'text': text,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        if (sourceConversationId != null)
          'sourceConversationId': sourceConversationId,
        if (projectId != null) 'projectId': projectId,
        'manual': manual,
        'pinned': pinned,
        'importance': importance,
      };

  factory WesiAiMemoryEntry.fromJson(
    Map<String, dynamic> json, {
    required String expectedEmployeeId,
  }) {
    final id = '${json['id'] ?? ''}'.trim();
    final employeeId = '${json['employeeId'] ?? ''}'.trim();
    final text = '${json['text'] ?? ''}'.trim();
    final createdAt = DateTime.tryParse('${json['createdAt'] ?? ''}');
    final updatedAt = DateTime.tryParse('${json['updatedAt'] ?? ''}');
    WesiAiMemoryScope? scope;
    final rawScope = '${json['scope'] ?? ''}';
    for (final candidate in WesiAiMemoryScope.values) {
      if (candidate.name == rawScope) {
        scope = candidate;
        break;
      }
    }
    final sourceConversationId = '${json['sourceConversationId'] ?? ''}'.trim();
    final projectId = '${json['projectId'] ?? ''}'.trim();
    final importanceRaw = json['importance'];
    final importance = importanceRaw is num
        ? importanceRaw.toDouble().clamp(0.0, 1.0).toDouble()
        : 0.5;

    if (!RegExp(r'^[A-Za-z0-9_-]{8,180}$').hasMatch(id) ||
        employeeId != expectedEmployeeId ||
        scope == null ||
        text.isEmpty ||
        text.length > 2000 ||
        createdAt == null ||
        updatedAt == null ||
        sourceConversationId.length > 180 ||
        projectId.length > 180) {
      throw const FormatException('Invalid Wesi AI memory entry');
    }
    if (scope == WesiAiMemoryScope.project && projectId.isEmpty) {
      throw const FormatException('Project memory requires projectId');
    }
    if (scope != WesiAiMemoryScope.project && projectId.isNotEmpty) {
      throw const FormatException('Non-project memory cannot carry projectId');
    }

    return WesiAiMemoryEntry(
      id: id,
      employeeId: employeeId,
      scope: scope,
      text: text,
      createdAt: createdAt.toLocal(),
      updatedAt: updatedAt.toLocal(),
      sourceConversationId:
          sourceConversationId.isEmpty ? null : sourceConversationId,
      projectId: projectId.isEmpty ? null : projectId,
      manual: json['manual'] == true,
      pinned: json['pinned'] == true,
      importance: importance,
    );
  }
}

class WesiAiMemorySettings {
  final bool autoMemoryEnabled;
  final int retrievalLimit;
  final int maxEntries;

  const WesiAiMemorySettings({
    this.autoMemoryEnabled = true,
    this.retrievalLimit = 12,
    this.maxEntries = 240,
  });

  WesiAiMemorySettings copyWith({
    bool? autoMemoryEnabled,
    int? retrievalLimit,
    int? maxEntries,
  }) =>
      WesiAiMemorySettings(
        autoMemoryEnabled: autoMemoryEnabled ?? this.autoMemoryEnabled,
        retrievalLimit:
            (retrievalLimit ?? this.retrievalLimit).clamp(4, 24).toInt(),
        maxEntries: (maxEntries ?? this.maxEntries).clamp(40, 600).toInt(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'autoMemoryEnabled': autoMemoryEnabled,
        'retrievalLimit': retrievalLimit,
        'maxEntries': maxEntries,
      };

  factory WesiAiMemorySettings.fromJson(Map<String, dynamic> json) =>
      WesiAiMemorySettings(
        autoMemoryEnabled: json['autoMemoryEnabled'] != false,
        retrievalLimit: ((json['retrievalLimit'] as num?)?.toInt() ?? 12)
            .clamp(4, 24)
            .toInt(),
        maxEntries: ((json['maxEntries'] as num?)?.toInt() ?? 240)
            .clamp(40, 600)
            .toInt(),
      );
}

class WesiAiConversationMemoryState {
  final String conversationId;
  final String rollingSummary;
  final Map<String, dynamic> taskState;
  final int summarizedMessageCount;
  final bool memoryEnabled;

  const WesiAiConversationMemoryState({
    required this.conversationId,
    this.rollingSummary = '',
    this.taskState = const <String, dynamic>{},
    this.summarizedMessageCount = 0,
    this.memoryEnabled = true,
  });

  WesiAiConversationMemoryState copyWith({
    String? rollingSummary,
    Map<String, dynamic>? taskState,
    int? summarizedMessageCount,
    bool? memoryEnabled,
  }) =>
      WesiAiConversationMemoryState(
        conversationId: conversationId,
        rollingSummary: rollingSummary ?? this.rollingSummary,
        taskState: taskState ?? this.taskState,
        summarizedMessageCount:
            summarizedMessageCount ?? this.summarizedMessageCount,
        memoryEnabled: memoryEnabled ?? this.memoryEnabled,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'conversationId': conversationId,
        'rollingSummary': rollingSummary,
        'taskState': taskState,
        'summarizedMessageCount': summarizedMessageCount,
        'memoryEnabled': memoryEnabled,
      };

  factory WesiAiConversationMemoryState.fromJson(
    Map<String, dynamic> json, {
    required Set<String> knownConversationIds,
  }) {
    final conversationId = '${json['conversationId'] ?? ''}'.trim();
    final summary = '${json['rollingSummary'] ?? ''}'.trim();
    final taskRaw = json['taskState'];
    final count = (json['summarizedMessageCount'] as num?)?.toInt() ?? 0;
    if (!knownConversationIds.contains(conversationId) ||
        summary.length > 24000 ||
        count < 0 ||
        count > 1000000) {
      throw const FormatException('Invalid Wesi AI conversation memory');
    }
    Map<String, dynamic> taskState = const <String, dynamic>{};
    if (taskRaw is Map) {
      try {
        final candidate = Map<String, dynamic>.from(taskRaw);
        final encoded = jsonEncode(candidate);
        if (encoded.length <= 12000) taskState = candidate;
      } catch (_) {}
    }
    return WesiAiConversationMemoryState(
      conversationId: conversationId,
      rollingSummary: summary,
      taskState: taskState,
      summarizedMessageCount: count,
      memoryEnabled: json['memoryEnabled'] != false,
    );
  }
}

class WesiAiMemoryCandidate {
  final WesiAiMemoryScope scope;
  final String text;
  final double importance;

  const WesiAiMemoryCandidate({
    required this.scope,
    required this.text,
    this.importance = 0.5,
  });
}

class WesiAiMemoryProcessResult {
  final String summary;
  final Map<String, dynamic> taskState;
  final List<WesiAiMemoryCandidate> memories;

  const WesiAiMemoryProcessResult({
    required this.summary,
    required this.taskState,
    required this.memories,
  });
}
