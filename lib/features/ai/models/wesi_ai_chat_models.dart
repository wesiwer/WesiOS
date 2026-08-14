enum WesiAiPersona { zane, nirvana, lobby }

enum WesiAiTier { fast, pro, maximum, ultra }

enum WesiAiLobbyMode { both, smart }

enum WesiAiMessageAuthor { user, zane, nirvana, system, tool }

enum WesiAiMessageKind { text, image, video, audio, file, action, status, error }

class WesiAiConversation {
  final String id;
  final String employeeId;
  final String title;
  final WesiAiPersona persona;
  final WesiAiLobbyMode lobbyMode;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool archived;
  final bool pinned;
  final String contextSummary;
  final int contextCompactedMessageCount;

  const WesiAiConversation({
    required this.id,
    required this.employeeId,
    required this.title,
    required this.persona,
    required this.createdAt,
    required this.updatedAt,
    this.lobbyMode = WesiAiLobbyMode.smart,
    this.archived = false,
    this.pinned = false,
    this.contextSummary = '',
    this.contextCompactedMessageCount = 0,
  });

  WesiAiConversation copyWith({
    String? title,
    WesiAiPersona? persona,
    WesiAiLobbyMode? lobbyMode,
    DateTime? updatedAt,
    bool? archived,
    bool? pinned,
    String? contextSummary,
    int? contextCompactedMessageCount,
  }) => WesiAiConversation(
        id: id,
        employeeId: employeeId,
        title: title ?? this.title,
        persona: persona ?? this.persona,
        lobbyMode: lobbyMode ?? this.lobbyMode,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        archived: archived ?? this.archived,
        pinned: pinned ?? this.pinned,
        contextSummary: contextSummary ?? this.contextSummary,
        contextCompactedMessageCount:
            contextCompactedMessageCount ?? this.contextCompactedMessageCount,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'title': title,
        'persona': persona.name,
        'lobbyMode': lobbyMode.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'archived': archived,
        'pinned': pinned,
        'contextSummary': contextSummary,
        'contextCompactedMessageCount': contextCompactedMessageCount,
      };

  factory WesiAiConversation.fromJson(Map<String, dynamic> json) =>
      WesiAiConversation(
        id: json['id'] as String,
        employeeId: json['employeeId'] as String,
        title: json['title'] as String? ?? 'Новый чат',
        persona:
            WesiAiPersona.values.byName(json['persona'] as String? ?? 'zane'),
        lobbyMode: WesiAiLobbyMode.values
            .byName(json['lobbyMode'] as String? ?? 'smart'),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        archived: json['archived'] as bool? ?? false,
        pinned: json['pinned'] as bool? ?? false,
        contextSummary: json['contextSummary'] as String? ?? '',
        contextCompactedMessageCount:
            json['contextCompactedMessageCount'] as int? ?? 0,
      );
}

class WesiAiMessage {
  final String id;
  final String conversationId;
  final String employeeId;
  final WesiAiMessageAuthor author;
  final WesiAiMessageKind kind;
  final String text;
  final DateTime createdAt;
  final String? replyToId;
  final Map<String, dynamic> metadata;

  const WesiAiMessage({required this.id, required this.conversationId, required this.employeeId, required this.author, required this.text, required this.createdAt, this.kind = WesiAiMessageKind.text, this.replyToId, this.metadata = const {}});

  WesiAiMessage copyWith({
    WesiAiMessageAuthor? author,
    WesiAiMessageKind? kind,
    String? text,
    String? replyToId,
    Map<String, dynamic>? metadata,
  }) => WesiAiMessage(
        id: id,
        conversationId: conversationId,
        employeeId: employeeId,
        author: author ?? this.author,
        kind: kind ?? this.kind,
        text: text ?? this.text,
        createdAt: createdAt,
        replyToId: replyToId ?? this.replyToId,
        metadata: metadata ?? this.metadata,
      );

  Map<String, dynamic> toJson() => {'id': id, 'conversationId': conversationId, 'employeeId': employeeId, 'author': author.name, 'kind': kind.name, 'text': text, 'createdAt': createdAt.toIso8601String(), 'replyToId': replyToId, 'metadata': metadata};

  factory WesiAiMessage.fromJson(Map<String, dynamic> json) => WesiAiMessage(id: json['id'] as String, conversationId: json['conversationId'] as String, employeeId: json['employeeId'] as String, author: WesiAiMessageAuthor.values.byName(json['author'] as String), kind: WesiAiMessageKind.values.byName(json['kind'] as String? ?? 'text'), text: json['text'] as String? ?? '', createdAt: DateTime.parse(json['createdAt'] as String), replyToId: json['replyToId'] as String?, metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}));
}

class WesiAiMemorySnapshot {
  final List<String> shared;
  final List<String> zane;
  final List<String> nirvana;
  const WesiAiMemorySnapshot({this.shared = const [], this.zane = const [], this.nirvana = const []});
  Map<String, dynamic> toJson() => {'shared': shared, 'zane': zane, 'nirvana': nirvana};
  factory WesiAiMemorySnapshot.fromJson(Map<String, dynamic> json) => WesiAiMemorySnapshot(shared: List<String>.from(json['shared'] as List? ?? const []), zane: List<String>.from(json['zane'] as List? ?? const []), nirvana: List<String>.from(json['nirvana'] as List? ?? const []));
}
