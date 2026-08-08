enum BeatStage {
  idea,
  draft,
  production,
  mixing,
  mastering,
  ready,
  negotiating,
  leased,
  sold,
  exclusive,
  archived,
}

enum BeatFileKind { mp3, wav, trackout, cover, contract, document, other }

enum VisualizerMode {
  water,
  membrane,
  spectrum,
  particles,
  tunnel,
  aurora,
  orbit,
  pulseGrid,
}

class BeatFileRef {
  final String id;
  final String name;
  final String path;
  final BeatFileKind kind;
  final int bytes;
  final DateTime createdAt;

  const BeatFileRef({
    required this.id,
    required this.name,
    required this.path,
    required this.kind,
    required this.bytes,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'kind': kind.name,
        'bytes': bytes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BeatFileRef.fromJson(Map<String, dynamic> json) => BeatFileRef(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        path: '${json['path'] ?? ''}',
        kind: BeatFileKind.values.firstWhere(
          (e) => e.name == json['kind'],
          orElse: () => BeatFileKind.other,
        ),
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      );
}

class BeatComment {
  final String id;
  final String text;
  final String authorId;
  final DateTime createdAt;

  const BeatComment({
    required this.id,
    required this.text,
    required this.authorId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'authorId': authorId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BeatComment.fromJson(Map<String, dynamic> json) => BeatComment(
        id: '${json['id'] ?? ''}',
        text: '${json['text'] ?? ''}',
        authorId: '${json['authorId'] ?? ''}',
        createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      );
}

class BeatLease {
  final String id;
  final String artistName;
  final String socialUrl;
  final DateTime startsAt;
  final DateTime endsAt;
  final double amount;
  final String currency;
  final String notes;
  final String? reminderTaskId;

  const BeatLease({
    required this.id,
    required this.artistName,
    required this.socialUrl,
    required this.startsAt,
    required this.endsAt,
    required this.amount,
    required this.currency,
    required this.notes,
    this.reminderTaskId,
  });

  BeatLease copyWith({String? reminderTaskId}) => BeatLease(
        id: id,
        artistName: artistName,
        socialUrl: socialUrl,
        startsAt: startsAt,
        endsAt: endsAt,
        amount: amount,
        currency: currency,
        notes: notes,
        reminderTaskId: reminderTaskId ?? this.reminderTaskId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'artistName': artistName,
        'socialUrl': socialUrl,
        'startsAt': startsAt.toIso8601String(),
        'endsAt': endsAt.toIso8601String(),
        'amount': amount,
        'currency': currency,
        'notes': notes,
        'reminderTaskId': reminderTaskId,
      };

  factory BeatLease.fromJson(Map<String, dynamic> json) => BeatLease(
        id: '${json['id'] ?? ''}',
        artistName: '${json['artistName'] ?? ''}',
        socialUrl: '${json['socialUrl'] ?? ''}',
        startsAt: DateTime.tryParse('${json['startsAt']}') ?? DateTime.now(),
        endsAt: DateTime.tryParse('${json['endsAt']}') ?? DateTime.now(),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        currency: '${json['currency'] ?? 'RUB'}',
        notes: '${json['notes'] ?? ''}',
        reminderTaskId: json['reminderTaskId'] as String?,
      );
}

class BeatEntry {
  final String id;
  final String title;
  final String authorEmployeeId;
  final int bpm;
  final String musicalKey;
  final String genre;
  final String mood;
  final List<String> tags;
  final BeatStage stage;
  final String notes;
  final String? mp3Path;
  final String? wavPath;
  final String? trackoutPath;
  final String? coverPath;
  final List<BeatFileRef> attachments;
  final List<BeatComment> comments;
  final BeatLease? lease;
  final bool favorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BeatEntry({
    required this.id,
    required this.title,
    required this.authorEmployeeId,
    this.bpm = 0,
    this.musicalKey = '',
    this.genre = '',
    this.mood = '',
    this.tags = const [],
    this.stage = BeatStage.idea,
    this.notes = '',
    this.mp3Path,
    this.wavPath,
    this.trackoutPath,
    this.coverPath,
    this.attachments = const [],
    this.comments = const [],
    this.lease,
    this.favorite = false,
    required this.createdAt,
    required this.updatedAt,
  });

  BeatEntry copyWith({
    String? title,
    String? authorEmployeeId,
    int? bpm,
    String? musicalKey,
    String? genre,
    String? mood,
    List<String>? tags,
    BeatStage? stage,
    String? notes,
    String? mp3Path,
    String? wavPath,
    String? trackoutPath,
    String? coverPath,
    List<BeatFileRef>? attachments,
    List<BeatComment>? comments,
    BeatLease? lease,
    bool clearLease = false,
    bool? favorite,
  }) =>
      BeatEntry(
        id: id,
        title: title ?? this.title,
        authorEmployeeId: authorEmployeeId ?? this.authorEmployeeId,
        bpm: bpm ?? this.bpm,
        musicalKey: musicalKey ?? this.musicalKey,
        genre: genre ?? this.genre,
        mood: mood ?? this.mood,
        tags: tags ?? this.tags,
        stage: stage ?? this.stage,
        notes: notes ?? this.notes,
        mp3Path: mp3Path ?? this.mp3Path,
        wavPath: wavPath ?? this.wavPath,
        trackoutPath: trackoutPath ?? this.trackoutPath,
        coverPath: coverPath ?? this.coverPath,
        attachments: attachments ?? this.attachments,
        comments: comments ?? this.comments,
        lease: clearLease ? null : (lease ?? this.lease),
        favorite: favorite ?? this.favorite,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  String? get playablePath => mp3Path ?? wavPath;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'authorEmployeeId': authorEmployeeId,
        'bpm': bpm,
        'musicalKey': musicalKey,
        'genre': genre,
        'mood': mood,
        'tags': tags,
        'stage': stage.name,
        'notes': notes,
        'mp3Path': mp3Path,
        'wavPath': wavPath,
        'trackoutPath': trackoutPath,
        'coverPath': coverPath,
        'attachments': attachments.map((e) => e.toJson()).toList(),
        'comments': comments.map((e) => e.toJson()).toList(),
        'lease': lease?.toJson(),
        'favorite': favorite,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory BeatEntry.fromJson(Map<String, dynamic> json) => BeatEntry(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        authorEmployeeId: '${json['authorEmployeeId'] ?? ''}',
        bpm: (json['bpm'] as num?)?.toInt() ?? 0,
        musicalKey: '${json['musicalKey'] ?? ''}',
        genre: '${json['genre'] ?? ''}',
        mood: '${json['mood'] ?? ''}',
        tags: (json['tags'] as List? ?? const []).map((e) => '$e').toList(),
        stage: BeatStage.values.firstWhere(
          (e) => e.name == json['stage'],
          orElse: () => BeatStage.idea,
        ),
        notes: '${json['notes'] ?? ''}',
        mp3Path: json['mp3Path'] as String?,
        wavPath: json['wavPath'] as String?,
        trackoutPath: json['trackoutPath'] as String?,
        coverPath: json['coverPath'] as String?,
        attachments: (json['attachments'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => BeatFileRef.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        comments: (json['comments'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => BeatComment.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        lease: json['lease'] is Map
            ? BeatLease.fromJson(Map<String, dynamic>.from(json['lease']))
            : null,
        favorite: json['favorite'] == true,
        createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
        updatedAt: DateTime.tryParse('${json['updatedAt']}') ?? DateTime.now(),
      );
}
