enum ReminderRepeat { none, daily, weekly, monthly, yearly }

class TimeAlarm {
  final String id;
  final String label;
  final DateTime firstAt;
  final Set<int> repeatWeekdays;
  final bool enabled;

  const TimeAlarm({
    required this.id,
    required this.label,
    required this.firstAt,
    this.repeatWeekdays = const {},
    this.enabled = true,
  });

  bool get repeats => repeatWeekdays.isNotEmpty;

  TimeAlarm copyWith({
    String? id,
    String? label,
    DateTime? firstAt,
    Set<int>? repeatWeekdays,
    bool? enabled,
  }) {
    return TimeAlarm(
      id: id ?? this.id,
      label: label ?? this.label,
      firstAt: firstAt ?? this.firstAt,
      repeatWeekdays: repeatWeekdays ?? this.repeatWeekdays,
      enabled: enabled ?? this.enabled,
    );
  }

  List<DateTime> nextOccurrences(DateTime now, {int count = 24}) {
    if (!enabled || count <= 0) return const [];
    if (!repeats) return firstAt.isAfter(now) ? [firstAt] : const [];

    final result = <DateTime>[];
    final today = DateTime(now.year, now.month, now.day);
    for (var offset = 0; offset < 370 && result.length < count; offset++) {
      final day = today.add(Duration(days: offset));
      if (!repeatWeekdays.contains(day.weekday)) continue;
      final occurrence = DateTime(
        day.year,
        day.month,
        day.day,
        firstAt.hour,
        firstAt.minute,
      );
      if (occurrence.isAfter(now)) result.add(occurrence);
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'firstAt': firstAt.toIso8601String(),
        'repeatWeekdays': repeatWeekdays.toList()..sort(),
        'enabled': enabled,
      };

  factory TimeAlarm.fromJson(Map<dynamic, dynamic> json) {
    final days = (json['repeatWeekdays'] as List<dynamic>? ?? const [])
        .whereType<num>()
        .map((e) => e.toInt())
        .where((e) => e >= DateTime.monday && e <= DateTime.sunday)
        .toSet();
    return TimeAlarm(
      id: '${json['id'] ?? ''}',
      label: '${json['label'] ?? ''}',
      firstAt: DateTime.tryParse('${json['firstAt'] ?? ''}') ?? DateTime.now(),
      repeatWeekdays: days,
      enabled: json['enabled'] != false,
    );
  }
}

class TimeReminder {
  final String id;
  final String title;
  final String notes;
  final DateTime at;
  final ReminderRepeat repeat;
  final bool enabled;

  const TimeReminder({
    required this.id,
    required this.title,
    this.notes = '',
    required this.at,
    this.repeat = ReminderRepeat.none,
    this.enabled = true,
  });

  TimeReminder copyWith({
    String? id,
    String? title,
    String? notes,
    DateTime? at,
    ReminderRepeat? repeat,
    bool? enabled,
  }) {
    return TimeReminder(
      id: id ?? this.id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      at: at ?? this.at,
      repeat: repeat ?? this.repeat,
      enabled: enabled ?? this.enabled,
    );
  }

  List<DateTime> nextOccurrences(DateTime now, {int count = 24}) {
    if (!enabled || count <= 0) return const [];
    if (repeat == ReminderRepeat.none) return at.isAfter(now) ? [at] : const [];

    final result = <DateTime>[];
    var candidate = at;
    var guard = 0;
    while (!candidate.isAfter(now) && guard < 5000) {
      candidate = _advance(candidate, repeat);
      guard++;
    }
    while (result.length < count && guard < 6000) {
      result.add(candidate);
      candidate = _advance(candidate, repeat);
      guard++;
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'notes': notes,
        'at': at.toIso8601String(),
        'repeat': repeat.name,
        'enabled': enabled,
      };

  factory TimeReminder.fromJson(Map<dynamic, dynamic> json) {
    final repeatName = '${json['repeat'] ?? 'none'}';
    final repeat = ReminderRepeat.values.firstWhere(
      (value) => value.name == repeatName,
      orElse: () => ReminderRepeat.none,
    );
    return TimeReminder(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      notes: '${json['notes'] ?? ''}',
      at: DateTime.tryParse('${json['at'] ?? ''}') ?? DateTime.now(),
      repeat: repeat,
      enabled: json['enabled'] != false,
    );
  }

  static DateTime _advance(DateTime value, ReminderRepeat repeat) {
    switch (repeat) {
      case ReminderRepeat.none:
        return value;
      case ReminderRepeat.daily:
        return value.add(const Duration(days: 1));
      case ReminderRepeat.weekly:
        return value.add(const Duration(days: 7));
      case ReminderRepeat.monthly:
        final firstNextMonth = DateTime(value.year, value.month + 1, 1);
        final lastDay =
            DateTime(firstNextMonth.year, firstNextMonth.month + 1, 0).day;
        final day = value.day > lastDay ? lastDay : value.day;
        return DateTime(
          firstNextMonth.year,
          firstNextMonth.month,
          day,
          value.hour,
          value.minute,
        );
      case ReminderRepeat.yearly:
        final lastDay = DateTime(value.year + 1, value.month + 1, 0).day;
        final day = value.day > lastDay ? lastDay : value.day;
        return DateTime(
          value.year + 1,
          value.month,
          day,
          value.hour,
          value.minute,
        );
    }
  }
}

class TimeTimerState {
  final int durationMs;
  final int remainingMs;
  final int? targetAtMs;
  final bool running;

  const TimeTimerState({
    this.durationMs = 300000,
    this.remainingMs = 300000,
    this.targetAtMs,
    this.running = false,
  });

  int remainingAt(DateTime now) {
    if (!running || targetAtMs == null) return remainingMs.clamp(0, durationMs);
    final left = targetAtMs! - now.millisecondsSinceEpoch;
    return left.clamp(0, durationMs);
  }

  bool isFinishedAt(DateTime now) => running && remainingAt(now) <= 0;

  TimeTimerState copyWith({
    int? durationMs,
    int? remainingMs,
    int? targetAtMs,
    bool clearTarget = false,
    bool? running,
  }) {
    return TimeTimerState(
      durationMs: durationMs ?? this.durationMs,
      remainingMs: remainingMs ?? this.remainingMs,
      targetAtMs: clearTarget ? null : (targetAtMs ?? this.targetAtMs),
      running: running ?? this.running,
    );
  }

  Map<String, dynamic> toJson() => {
        'durationMs': durationMs,
        'remainingMs': remainingMs,
        'targetAtMs': targetAtMs,
        'running': running,
      };

  factory TimeTimerState.fromJson(Map<dynamic, dynamic> json) => TimeTimerState(
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 300000,
        remainingMs: (json['remainingMs'] as num?)?.toInt() ?? 300000,
        targetAtMs: (json['targetAtMs'] as num?)?.toInt(),
        running: json['running'] == true,
      );
}

class TimeStopwatchState {
  final int accumulatedMs;
  final int? startedAtMs;
  final List<int> lapsMs;

  const TimeStopwatchState({
    this.accumulatedMs = 0,
    this.startedAtMs,
    this.lapsMs = const [],
  });

  bool get running => startedAtMs != null;

  int elapsedAt(DateTime now) {
    final started = startedAtMs;
    if (started == null) return accumulatedMs;
    return accumulatedMs +
        (now.millisecondsSinceEpoch - started).clamp(0, 1 << 62);
  }

  TimeStopwatchState copyWith({
    int? accumulatedMs,
    int? startedAtMs,
    bool clearStart = false,
    List<int>? lapsMs,
  }) {
    return TimeStopwatchState(
      accumulatedMs: accumulatedMs ?? this.accumulatedMs,
      startedAtMs: clearStart ? null : (startedAtMs ?? this.startedAtMs),
      lapsMs: lapsMs ?? this.lapsMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'accumulatedMs': accumulatedMs,
        'startedAtMs': startedAtMs,
        'lapsMs': lapsMs,
      };

  factory TimeStopwatchState.fromJson(Map<dynamic, dynamic> json) =>
      TimeStopwatchState(
        accumulatedMs: (json['accumulatedMs'] as num?)?.toInt() ?? 0,
        startedAtMs: (json['startedAtMs'] as num?)?.toInt(),
        lapsMs: (json['lapsMs'] as List<dynamic>? ?? const [])
            .whereType<num>()
            .map((e) => e.toInt())
            .toList(),
      );
}
