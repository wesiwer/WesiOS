enum CalendarRepeat { none, daily, weekly, monthly, yearly }

class CalendarEvent {
  final String id;
  final String title;
  final String notes;
  final DateTime startAt;
  final int durationMinutes;
  final bool allDay;
  final CalendarRepeat repeat;
  final int? reminderMinutesBefore;
  final bool enabled;

  const CalendarEvent({
    required this.id,
    required this.title,
    this.notes = '',
    required this.startAt,
    this.durationMinutes = 60,
    this.allDay = false,
    this.repeat = CalendarRepeat.none,
    this.reminderMinutesBefore,
    this.enabled = true,
  });

  DateTime get endAt => startAt.add(Duration(minutes: durationMinutes));

  CalendarEvent copyWith({
    String? id,
    String? title,
    String? notes,
    DateTime? startAt,
    int? durationMinutes,
    bool? allDay,
    CalendarRepeat? repeat,
    int? reminderMinutesBefore,
    bool clearReminder = false,
    bool? enabled,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      startAt: startAt ?? this.startAt,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      allDay: allDay ?? this.allDay,
      repeat: repeat ?? this.repeat,
      reminderMinutesBefore: clearReminder
          ? null
          : (reminderMinutesBefore ?? this.reminderMinutesBefore),
      enabled: enabled ?? this.enabled,
    );
  }

  bool occursOn(DateTime day) {
    if (!enabled) return false;
    final target = DateTime(day.year, day.month, day.day);
    final first = DateTime(startAt.year, startAt.month, startAt.day);
    if (target.isBefore(first)) return false;

    switch (repeat) {
      case CalendarRepeat.none:
        return target == first;
      case CalendarRepeat.daily:
        return true;
      case CalendarRepeat.weekly:
        return target.weekday == first.weekday;
      case CalendarRepeat.monthly:
        return target.day ==
            _clampedDay(startAt.day, target.year, target.month);
      case CalendarRepeat.yearly:
        if (target.month != startAt.month) return false;
        return target.day ==
            _clampedDay(startAt.day, target.year, target.month);
    }
  }

  DateTime occurrenceStart(DateTime day) => DateTime(
        day.year,
        day.month,
        day.day,
        allDay ? 9 : startAt.hour,
        allDay ? 0 : startAt.minute,
      );

  List<DateTime> nextOccurrences(
    DateTime now, {
    int count = 24,
    int scanDays = 1096,
  }) {
    if (!enabled || count <= 0) return const [];
    if (repeat == CalendarRepeat.none) {
      return startAt.isAfter(now) ? [startAt] : const [];
    }

    final result = <DateTime>[];
    final today = DateTime(now.year, now.month, now.day);
    for (var offset = 0;
        offset <= scanDays && result.length < count;
        offset++) {
      final day = today.add(Duration(days: offset));
      if (!occursOn(day)) continue;
      final occurrence = occurrenceStart(day);
      if (occurrence.isAfter(now)) result.add(occurrence);
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'notes': notes,
        'startAt': startAt.toIso8601String(),
        'durationMinutes': durationMinutes,
        'allDay': allDay,
        'repeat': repeat.name,
        'reminderMinutesBefore': reminderMinutesBefore,
        'enabled': enabled,
      };

  factory CalendarEvent.fromJson(Map<dynamic, dynamic> json) {
    final repeatName = '${json['repeat'] ?? 'none'}';
    final repeat = CalendarRepeat.values.firstWhere(
      (value) => value.name == repeatName,
      orElse: () => CalendarRepeat.none,
    );
    return CalendarEvent(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      notes: '${json['notes'] ?? ''}',
      startAt: DateTime.tryParse('${json['startAt'] ?? ''}') ?? DateTime.now(),
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 60,
      allDay: json['allDay'] == true,
      repeat: repeat,
      reminderMinutesBefore: (json['reminderMinutesBefore'] as num?)?.toInt(),
      enabled: json['enabled'] != false,
    );
  }

  static int _clampedDay(int requested, int year, int month) {
    final last = DateTime(year, month + 1, 0).day;
    return requested > last ? last : requested;
  }
}
