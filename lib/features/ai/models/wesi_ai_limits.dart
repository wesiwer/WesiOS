class WesiAiLimitSnapshot {
  final String key;
  final String provider;
  final String model;
  final bool configured;
  final double? remainingPercent;
  final DateTime? resetAt;
  final DateTime? observedAt;

  const WesiAiLimitSnapshot({
    required this.key,
    required this.provider,
    required this.model,
    required this.configured,
    this.remainingPercent,
    this.resetAt,
    this.observedAt,
  });

  bool get hasUsageData => remainingPercent != null;
  double? get remainingFraction => remainingPercent == null
      ? null
      : (remainingPercent!.clamp(0, 100) / 100).toDouble();

  factory WesiAiLimitSnapshot.fromJson(String key, Object? raw) {
    if (raw is! Map) {
      return WesiAiLimitSnapshot(
        key: key,
        provider: '',
        model: '',
        configured: false,
      );
    }
    final json = Map<String, dynamic>.from(raw);
    DateTime? parseDate(Object? value) {
      final text = '${value ?? ''}'.trim();
      return text.isEmpty ? null : DateTime.tryParse(text)?.toLocal();
    }

    final percentRaw = json['remainingPercent'];
    final percent = percentRaw is num ? percentRaw.toDouble() : null;
    return WesiAiLimitSnapshot(
      key: key,
      provider: '${json['provider'] ?? ''}',
      model: '${json['model'] ?? ''}',
      configured: json['configured'] == true,
      remainingPercent: percent?.clamp(0, 100).toDouble(),
      resetAt: parseDate(json['resetAt']),
      observedAt: parseDate(json['observedAt']),
    );
  }
}

class WesiAiLimits {
  final Map<String, WesiAiLimitSnapshot> entries;

  const WesiAiLimits(this.entries);

  WesiAiLimitSnapshot? operator [](String key) => entries[key];

  factory WesiAiLimits.fromJson(Object? raw) {
    if (raw is! Map) return const WesiAiLimits({});
    final map = Map<String, dynamic>.from(raw);
    return WesiAiLimits({
      for (final entry in map.entries)
        entry.key: WesiAiLimitSnapshot.fromJson(entry.key, entry.value),
    });
  }
}
