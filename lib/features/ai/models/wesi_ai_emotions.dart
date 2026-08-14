enum WesiAiEmotion {
  joy,
  trust,
  anticipation,
  surprise,
  sadness,
  anxiety,
  anger,
  aversion,
}

class WesiAiEmotionTrace {
  final String id;
  final String subject;
  final String summary;
  final double weight;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool unresolved;

  const WesiAiEmotionTrace({
    required this.id,
    required this.subject,
    required this.summary,
    required this.weight,
    required this.createdAt,
    required this.updatedAt,
    this.unresolved = true,
  });

  WesiAiEmotionTrace copyWith({
    double? weight,
    DateTime? updatedAt,
    bool? unresolved,
  }) =>
      WesiAiEmotionTrace(
        id: id,
        subject: subject,
        summary: summary,
        weight: weight ?? this.weight,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        unresolved: unresolved ?? this.unresolved,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'summary': summary,
        'weight': weight,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'unresolved': unresolved,
      };

  factory WesiAiEmotionTrace.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return WesiAiEmotionTrace(
      id: '${json['id'] ?? ''}',
      subject: '${json['subject'] ?? ''}',
      summary: '${json['summary'] ?? ''}',
      weight: (json['weight'] as num?)?.toDouble().clamp(0, 1) ?? 0,
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}') ?? now,
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? now,
      unresolved: json['unresolved'] != false,
    );
  }
}

class WesiAiPersonaEmotionState {
  final Map<WesiAiEmotion, double> levels;
  final List<WesiAiEmotionTrace> traces;
  final DateTime updatedAt;
  final String? stance;

  const WesiAiPersonaEmotionState({
    this.levels = const {},
    this.traces = const [],
    required this.updatedAt,
    this.stance,
  });

  factory WesiAiPersonaEmotionState.neutral([DateTime? now]) =>
      WesiAiPersonaEmotionState(updatedAt: now ?? DateTime.now());

  double level(WesiAiEmotion emotion) => levels[emotion] ?? 0;

  List<MapEntry<WesiAiEmotion, double>> get active {
    final items = levels.entries.where((e) => e.value >= 0.12).toList();
    items.sort((a, b) => b.value.compareTo(a.value));
    return items;
  }

  WesiAiPersonaEmotionState decayed([DateTime? now]) {
    final at = now ?? DateTime.now();
    final elapsed = at.difference(updatedAt);
    if (elapsed <= Duration.zero) return this;

    // Immediate mood fades relatively quickly, while relational traces fade
    // much slower. Roughly: most mood is gone after a day unless reinforced.
    final hours = elapsed.inMinutes / 60.0;
    final moodFactor = _pow(0.5, hours / 10.0);
    final traceFactor = _pow(0.5, hours / 72.0);
    final nextLevels = <WesiAiEmotion, double>{};
    for (final entry in levels.entries) {
      final value = (entry.value * moodFactor).clamp(0.0, 1.0);
      if (value >= 0.03) nextLevels[entry.key] = value;
    }
    final nextTraces = traces
        .map((trace) => trace.copyWith(
              weight: (trace.weight * traceFactor).clamp(0.0, 1.0),
              updatedAt: at,
            ))
        .where((trace) => trace.weight >= 0.05)
        .toList(growable: false);
    return WesiAiPersonaEmotionState(
      levels: nextLevels,
      traces: nextTraces,
      updatedAt: at,
      stance: stance,
    );
  }

  WesiAiPersonaEmotionState copyWith({
    Map<WesiAiEmotion, double>? levels,
    List<WesiAiEmotionTrace>? traces,
    DateTime? updatedAt,
    String? stance,
    bool clearStance = false,
  }) =>
      WesiAiPersonaEmotionState(
        levels: levels ?? this.levels,
        traces: traces ?? this.traces,
        updatedAt: updatedAt ?? this.updatedAt,
        stance: clearStance ? null : (stance ?? this.stance),
      );

  Map<String, dynamic> toJson() => {
        'levels': {for (final e in levels.entries) e.key.name: e.value},
        'traces': traces.map((e) => e.toJson()).toList(growable: false),
        'updatedAt': updatedAt.toIso8601String(),
        if (stance != null) 'stance': stance,
      };

  factory WesiAiPersonaEmotionState.fromJson(Object? raw) {
    if (raw is! Map) return WesiAiPersonaEmotionState.neutral();
    final json = Map<String, dynamic>.from(raw);
    final rawLevels = json['levels'];
    final levels = <WesiAiEmotion, double>{};
    if (rawLevels is Map) {
      for (final entry in rawLevels.entries) {
        WesiAiEmotion? emotion;
        for (final candidate in WesiAiEmotion.values) {
          if (candidate.name == '${entry.key}') {
            emotion = candidate;
            break;
          }
        }
        final value = entry.value;
        if (emotion != null && value is num) {
          levels[emotion] = value.toDouble().clamp(0, 1);
        }
      }
    }
    final traces = <WesiAiEmotionTrace>[];
    final rawTraces = json['traces'];
    if (rawTraces is List) {
      for (final item in rawTraces) {
        if (item is Map) {
          traces.add(WesiAiEmotionTrace.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return WesiAiPersonaEmotionState(
      levels: levels,
      traces: traces,
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? DateTime.now(),
      stance: '${json['stance'] ?? ''}'.trim().isEmpty ? null : '${json['stance']}',
    );
  }
}

class WesiAiEmotionSnapshot {
  final WesiAiPersonaEmotionState zane;
  final WesiAiPersonaEmotionState nirvana;

  const WesiAiEmotionSnapshot({required this.zane, required this.nirvana});

  factory WesiAiEmotionSnapshot.neutral([DateTime? now]) {
    final at = now ?? DateTime.now();
    return WesiAiEmotionSnapshot(
      zane: WesiAiPersonaEmotionState.neutral(at),
      nirvana: WesiAiPersonaEmotionState.neutral(at),
    );
  }

  WesiAiEmotionSnapshot decayed([DateTime? now]) => WesiAiEmotionSnapshot(
        zane: zane.decayed(now),
        nirvana: nirvana.decayed(now),
      );

  Map<String, dynamic> toJson() => {
        'zane': zane.toJson(),
        'nirvana': nirvana.toJson(),
      };

  factory WesiAiEmotionSnapshot.fromJson(Object? raw) {
    if (raw is! Map) return WesiAiEmotionSnapshot.neutral();
    final json = Map<String, dynamic>.from(raw);
    return WesiAiEmotionSnapshot(
      zane: WesiAiPersonaEmotionState.fromJson(json['zane']),
      nirvana: WesiAiPersonaEmotionState.fromJson(json['nirvana']),
    );
  }
}

double _pow(double base, double exponent) {
  // Avoid adding dart:math to every consumer. Precision is ample for mood
  // decay; exponentiation by exp/log is delegated here via a small approximation.
  if (exponent <= 0) return 1;
  final whole = exponent.floor();
  final fraction = exponent - whole;
  var result = 1.0;
  for (var i = 0; i < whole; i++) result *= base;
  if (fraction > 0) {
    // Linear interpolation is intentionally gentle; this is a UX decay curve,
    // not a scientific simulation.
    result *= 1 - ((1 - base) * fraction);
  }
  return result.clamp(0.0, 1.0);
}
