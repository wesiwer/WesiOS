import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_clock.dart';
import 'models/time_center_models.dart';
import 'services/time_center_service.dart';

class TimeCenterScreen extends StatefulWidget {
  const TimeCenterScreen({super.key});

  @override
  State<TimeCenterScreen> createState() => _TimeCenterScreenState();
}

class _TimeCenterScreenState extends State<TimeCenterScreen> {
  final TimeCenterService _service = TimeCenterService();

  List<TimeAlarm> _alarms = const [];
  List<TimeReminder> _reminders = const [];
  TimeTimerState _timer = const TimeTimerState();
  TimeStopwatchState _stopwatch = const TimeStopwatchState();
  Timer? _ticker;
  bool _loading = true;
  bool _timerReconciling = false;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    TimeCenterService.revision.addListener(_load);
    _load();
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      if (_timer.running || _stopwatch.running) {
        setState(() {});
        if (_timer.running && _timer.remainingAt(DateTime.now()) <= 0) {
          unawaited(_finishTimer());
        }
      }
    });
  }

  @override
  void dispose() {
    TimeCenterService.revision.removeListener(_load);
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final alarms = await _service.getAlarms();
    final reminders = await _service.getReminders();
    final timer = await _service.reconcileTimer();
    final stopwatch = await _service.getStopwatch();
    if (!mounted) return;
    setState(() {
      _alarms = alarms;
      _reminders = reminders;
      _timer = timer;
      _stopwatch = stopwatch;
      _loading = false;
    });
  }

  Future<void> _finishTimer() async {
    if (_timerReconciling) return;
    _timerReconciling = true;
    try {
      final next = await _service.reconcileTimer();
      if (mounted) setState(() => _timer = next);
    } finally {
      _timerReconciling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          title: Text(_ru ? 'Центр времени' : 'Time Center'),
          actions: [
            IconButton(
              tooltip: _ru ? 'Календарь' : 'Calendar',
              onPressed: () => Navigator.pushNamed(context, '/calendar'),
              icon: const Icon(Icons.calendar_month_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withOpacity(.34),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppTheme.glassBorder),
                  ),
                  child: const WesiClock(),
                ),
              ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(
                    icon: const Icon(Icons.alarm_rounded),
                    text: _ru ? 'Будильники' : 'Alarms',
                  ),
                  Tab(
                    icon: const Icon(Icons.notifications_active_outlined),
                    text: _ru ? 'Напоминания' : 'Reminders',
                  ),
                  Tab(
                    icon: const Icon(Icons.hourglass_bottom_rounded),
                    text: _ru ? 'Таймер' : 'Timer',
                  ),
                  Tab(
                    icon: const Icon(Icons.timer_outlined),
                    text: _ru ? 'Секундомер' : 'Stopwatch',
                  ),
                ],
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        children: [
                          _alarmsTab(),
                          _remindersTab(),
                          _timerTab(),
                          _stopwatchTab(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _alarmsTab() {
    return _tabList(
      title: _ru ? 'Будильники' : 'Alarms',
      subtitle: _ru
          ? 'Однократные или по выбранным дням недели'
          : 'One-shot or repeating on selected weekdays',
      onAdd: () => _editAlarm(),
      emptyIcon: Icons.alarm_off_rounded,
      emptyText: _ru ? 'Будильников пока нет' : 'No alarms yet',
      children: _alarms.map(_alarmTile).toList(),
    );
  }

  Widget _alarmTile(TimeAlarm alarm) {
    final next = alarm.nextOccurrences(DateTime.now(), count: 1);
    final time = TimeOfDay.fromDateTime(alarm.firstAt);
    return _panel(
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              _timeLabel(time),
              style: TextStyle(
                color:
                    alarm.enabled ? AppTheme.textPrimary : AppTheme.textMuted,
                fontSize: 23,
                fontWeight: FontWeight.w300,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alarm.label.trim().isEmpty
                      ? (_ru ? 'Будильник' : 'Alarm')
                      : alarm.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  alarm.repeats
                      ? _weekdaysLabel(alarm.repeatWeekdays)
                      : next.isEmpty
                          ? (_ru ? 'Завершён' : 'Finished')
                          : _dateTimeLabel(next.first),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Switch(
            value: alarm.enabled,
            onChanged: (value) => _service.setAlarmEnabled(alarm, value),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') _editAlarm(alarm);
              if (value == 'delete') _service.deleteAlarm(alarm.id);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'edit', child: Text(_ru ? 'Изменить' : 'Edit')),
              PopupMenuItem(
                  value: 'delete', child: Text(_ru ? 'Удалить' : 'Delete')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _remindersTab() {
    return _tabList(
      title: _ru ? 'Напоминания' : 'Reminders',
      subtitle: _ru
          ? 'Разовые и повторяющиеся уведомления'
          : 'One-time and recurring notifications',
      onAdd: () => _editReminder(),
      emptyIcon: Icons.notifications_none_rounded,
      emptyText: _ru ? 'Напоминаний пока нет' : 'No reminders yet',
      children: _reminders.map(_reminderTile).toList(),
    );
  }

  Widget _reminderTile(TimeReminder reminder) {
    final next = reminder.nextOccurrences(DateTime.now(), count: 1);
    return _panel(
      child: Row(
        children: [
          Icon(
            Icons.notifications_active_outlined,
            color: reminder.enabled ? AppTheme.accent : AppTheme.textMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reminder.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  next.isEmpty
                      ? (_ru ? 'Завершено' : 'Finished')
                      : '${_dateTimeLabel(next.first)} · ${_reminderRepeatLabel(reminder.repeat)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
                if (reminder.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    reminder.notes,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: reminder.enabled,
            onChanged: (value) => _service.setReminderEnabled(reminder, value),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') _editReminder(reminder);
              if (value == 'delete') _service.deleteReminder(reminder.id);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'edit', child: Text(_ru ? 'Изменить' : 'Edit')),
              PopupMenuItem(
                  value: 'delete', child: Text(_ru ? 'Удалить' : 'Delete')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timerTab() {
    final now = DateTime.now();
    final remaining = _timer.remainingAt(now);
    final total = _timer.durationMs <= 0 ? 1 : _timer.durationMs;
    final progress = (1 - remaining / total).clamp(0.0, 1.0);
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _panel(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              Text(
                _formatClockMs(remaining),
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 46,
                  fontWeight: FontWeight.w200,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                minHeight: 7,
                value: progress,
                borderRadius: BorderRadius.circular(99),
              ),
              const SizedBox(height: 22),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      final next = _timer.running
                          ? await _service.pauseTimer()
                          : await _service.startTimer();
                      if (mounted) setState(() => _timer = next);
                    },
                    icon: Icon(_timer.running ? Icons.pause : Icons.play_arrow),
                    label: Text(_timer.running
                        ? (_ru ? 'Пауза' : 'Pause')
                        : (_ru ? 'Старт' : 'Start')),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final next = await _service.resetTimer();
                      if (mounted) setState(() => _timer = next);
                    },
                    icon: const Icon(Icons.restart_alt),
                    label: Text(_ru ? 'Сброс' : 'Reset'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _timer.running ? null : _customTimer,
                    icon: const Icon(Icons.tune_rounded),
                    label: Text(_ru ? 'Настроить' : 'Custom'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _ru ? 'Быстрый таймер' : 'Quick timer',
          style: TextStyle(
              color: AppTheme.textSecondary, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final minutes in const [1, 5, 10, 25, 45, 60])
              ActionChip(
                label: Text('$minutes ${_ru ? 'мин' : 'min'}'),
                onPressed:
                    _timer.running ? null : () => _setTimerMinutes(minutes),
              ),
          ],
        ),
      ],
    );
  }

  Widget _stopwatchTab() {
    final elapsed = _stopwatch.elapsedAt(DateTime.now());
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _panel(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              Text(
                _formatStopwatchMs(elapsed),
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 43,
                  fontWeight: FontWeight.w200,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      final next = await _service.toggleStopwatch();
                      if (mounted) setState(() => _stopwatch = next);
                    },
                    icon: Icon(
                        _stopwatch.running ? Icons.pause : Icons.play_arrow),
                    label: Text(_stopwatch.running
                        ? (_ru ? 'Пауза' : 'Pause')
                        : (_ru ? 'Старт' : 'Start')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _stopwatch.running
                        ? () async {
                            final next = await _service.addLap();
                            if (mounted) setState(() => _stopwatch = next);
                          }
                        : null,
                    icon: const Icon(Icons.flag_outlined),
                    label: Text(_ru ? 'Круг' : 'Lap'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final next = await _service.resetStopwatch();
                      if (mounted) setState(() => _stopwatch = next);
                    },
                    icon: const Icon(Icons.restart_alt),
                    label: Text(_ru ? 'Сброс' : 'Reset'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_stopwatch.lapsMs.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            _ru ? 'Круги' : 'Laps',
            style: TextStyle(
                color: AppTheme.textSecondary, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _stopwatch.lapsMs.length; i++) _lapTile(i),
        ],
      ],
    );
  }

  Widget _lapTile(int index) {
    final current = _stopwatch.lapsMs[index];
    final previous =
        index + 1 < _stopwatch.lapsMs.length ? _stopwatch.lapsMs[index + 1] : 0;
    final split = current - previous;
    final number = _stopwatch.lapsMs.length - index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _panel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Text('${_ru ? 'Круг' : 'Lap'} $number',
                style: TextStyle(color: AppTheme.textSecondary)),
            const Spacer(),
            Text('+${_formatStopwatchMs(split)}',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            const SizedBox(width: 16),
            Text(_formatStopwatchMs(current),
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
      ),
    );
  }

  Widget _tabList({
    required String title,
    required String subtitle,
    required VoidCallback onAdd,
    required IconData emptyIcon,
    required String emptyText,
    required List<Widget> children,
  }) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style:
                          TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(_ru ? 'Добавить' : 'Add'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Column(
              children: [
                Icon(emptyIcon, size: 42, color: AppTheme.textMuted),
                const SizedBox(height: 10),
                Text(emptyText, style: TextStyle(color: AppTheme.textMuted)),
              ],
            ),
          )
        else
          ...children.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: item,
              )),
      ],
    );
  }

  Widget _panel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(.36),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: child,
    );
  }

  Future<void> _editAlarm([TimeAlarm? original]) async {
    final now = DateTime.now();
    var date = original?.firstAt ?? now.add(const Duration(hours: 1));
    var time = TimeOfDay.fromDateTime(date);
    final days = <int>{...?original?.repeatWeekdays};
    final label = TextEditingController(text: original?.label ?? '');

    final result = await showDialog<TimeAlarm>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(original == null
              ? (_ru ? 'Новый будильник' : 'New alarm')
              : (_ru ? 'Будильник' : 'Alarm')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: label,
                    decoration:
                        InputDecoration(labelText: _ru ? 'Название' : 'Label'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.schedule),
                          label: Text(_timeLabel(time)),
                          onPressed: () async {
                            final picked = await showTimePicker(
                                context: context, initialTime: time);
                            if (picked != null)
                              setDialogState(() => time = picked);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (days.isEmpty)
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.event),
                            label: Text(_dateLabel(date)),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: date.isBefore(now) ? now : date,
                                firstDate:
                                    DateTime(now.year, now.month, now.day),
                                lastDate: DateTime(now.year + 5),
                              );
                              if (picked != null)
                                setDialogState(() => date = picked);
                            },
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_ru ? 'Повтор по дням' : 'Repeat on days',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (var weekday = 1; weekday <= 7; weekday++)
                        FilterChip(
                          selected: days.contains(weekday),
                          label: Text(_weekdayShort(weekday)),
                          onSelected: (selected) => setDialogState(() {
                            if (selected) {
                              days.add(weekday);
                            } else {
                              days.remove(weekday);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    days.isEmpty
                        ? (_ru
                            ? 'Без выбранных дней — один раз'
                            : 'No days selected — one time')
                        : (_ru
                            ? 'Будет повторяться каждую неделю'
                            : 'Repeats every week'),
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_ru ? 'Отмена' : 'Cancel')),
            FilledButton(
              onPressed: () {
                var first = DateTime(
                    date.year, date.month, date.day, time.hour, time.minute);
                if (days.isNotEmpty) {
                  first = DateTime(
                      now.year, now.month, now.day, time.hour, time.minute);
                } else if (!first.isAfter(now)) {
                  first = first.add(const Duration(days: 1));
                }
                Navigator.pop(
                  context,
                  TimeAlarm(
                    id: original?.id ??
                        'alarm_${DateTime.now().microsecondsSinceEpoch}',
                    label: label.text.trim(),
                    firstAt: first,
                    repeatWeekdays: days,
                    enabled: original?.enabled ?? true,
                  ),
                );
              },
              child: Text(_ru ? 'Сохранить' : 'Save'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    if (result != null) await _service.saveAlarm(result);
  }

  Future<void> _editReminder([TimeReminder? original]) async {
    final now = DateTime.now();
    var date = original?.at ?? now.add(const Duration(hours: 1));
    var time = TimeOfDay.fromDateTime(date);
    var repeat = original?.repeat ?? ReminderRepeat.none;
    final title = TextEditingController(text: original?.title ?? '');
    final notes = TextEditingController(text: original?.notes ?? '');

    final result = await showDialog<TimeReminder>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(original == null
              ? (_ru ? 'Новое напоминание' : 'New reminder')
              : (_ru ? 'Напоминание' : 'Reminder')),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    autofocus: original == null,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                        labelText: _ru ? 'Что напомнить' : 'Title'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    maxLines: 2,
                    decoration:
                        InputDecoration(labelText: _ru ? 'Заметка' : 'Note'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.event),
                          label: Text(_dateLabel(date)),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: date.isBefore(now) ? now : date,
                              firstDate: DateTime(now.year, now.month, now.day),
                              lastDate: DateTime(now.year + 10),
                            );
                            if (picked != null)
                              setDialogState(() => date = picked);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.schedule),
                          label: Text(_timeLabel(time)),
                          onPressed: () async {
                            final picked = await showTimePicker(
                                context: context, initialTime: time);
                            if (picked != null)
                              setDialogState(() => time = picked);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ReminderRepeat>(
                    value: repeat,
                    decoration:
                        InputDecoration(labelText: _ru ? 'Повтор' : 'Repeat'),
                    items: ReminderRepeat.values
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(_reminderRepeatLabel(value)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => repeat = value);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_ru ? 'Отмена' : 'Cancel')),
            FilledButton(
              onPressed: title.text.trim().isEmpty
                  ? null
                  : () {
                      var at = DateTime(date.year, date.month, date.day,
                          time.hour, time.minute);
                      if (!at.isAfter(now) && repeat == ReminderRepeat.none) {
                        at = at.add(const Duration(days: 1));
                      }
                      Navigator.pop(
                        context,
                        TimeReminder(
                          id: original?.id ??
                              'reminder_${DateTime.now().microsecondsSinceEpoch}',
                          title: title.text.trim(),
                          notes: notes.text.trim(),
                          at: at,
                          repeat: repeat,
                          enabled: original?.enabled ?? true,
                        ),
                      );
                    },
              child: Text(_ru ? 'Сохранить' : 'Save'),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    notes.dispose();
    if (result != null) await _service.saveReminder(result);
  }

  Future<void> _setTimerMinutes(int minutes) async {
    final next = await _service.setTimerDuration(Duration(minutes: minutes));
    if (mounted) setState(() => _timer = next);
  }

  Future<void> _customTimer() async {
    final currentSeconds = (_timer.durationMs / 1000).round();
    final hours = TextEditingController(text: '${currentSeconds ~/ 3600}');
    final minutes =
        TextEditingController(text: '${(currentSeconds ~/ 60) % 60}');
    final seconds = TextEditingController(text: '${currentSeconds % 60}');
    final duration = await showDialog<Duration>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_ru ? 'Настроить таймер' : 'Custom timer'),
        content: Row(
          children: [
            Expanded(
                child: TextField(
                    controller: hours,
                    keyboardType: TextInputType.number,
                    decoration:
                        InputDecoration(labelText: _ru ? 'Часы' : 'Hours'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: minutes,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: _ru ? 'Минуты' : 'Minutes'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: seconds,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: _ru ? 'Секунды' : 'Seconds'))),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_ru ? 'Отмена' : 'Cancel')),
          FilledButton(
            onPressed: () {
              final h = int.tryParse(hours.text) ?? 0;
              final m = int.tryParse(minutes.text) ?? 0;
              final s = int.tryParse(seconds.text) ?? 0;
              final total = h * 3600 + m * 60 + s;
              if (total > 0) Navigator.pop(context, Duration(seconds: total));
            },
            child: Text(_ru ? 'Готово' : 'Done'),
          ),
        ],
      ),
    );
    hours.dispose();
    minutes.dispose();
    seconds.dispose();
    if (duration != null) {
      final next = await _service.setTimerDuration(duration);
      if (mounted) setState(() => _timer = next);
    }
  }

  String _timeLabel(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

  String _dateTimeLabel(DateTime date) =>
      '${_dateLabel(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  String _weekdayShort(int weekday) {
    const ru = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return (_ru ? ru : en)[weekday - 1];
  }

  String _weekdaysLabel(Set<int> days) {
    if (days.length == 7) return _ru ? 'Каждый день' : 'Every day';
    if (days.length == 5 && days.containsAll(const [1, 2, 3, 4, 5])) {
      return _ru ? 'По будням' : 'Weekdays';
    }
    final sorted = days.toList()..sort();
    return sorted.map(_weekdayShort).join(' · ');
  }

  String _reminderRepeatLabel(ReminderRepeat repeat) {
    if (_ru) {
      return switch (repeat) {
        ReminderRepeat.none => 'Один раз',
        ReminderRepeat.daily => 'Каждый день',
        ReminderRepeat.weekly => 'Каждую неделю',
        ReminderRepeat.monthly => 'Каждый месяц',
        ReminderRepeat.yearly => 'Каждый год',
      };
    }
    return switch (repeat) {
      ReminderRepeat.none => 'Once',
      ReminderRepeat.daily => 'Daily',
      ReminderRepeat.weekly => 'Weekly',
      ReminderRepeat.monthly => 'Monthly',
      ReminderRepeat.yearly => 'Yearly',
    };
  }

  String _formatClockMs(int ms) {
    final totalSeconds = (ms / 1000).ceil().clamp(0, 24 * 60 * 60);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds ~/ 60) % 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatStopwatchMs(int ms) {
    final safe = ms < 0 ? 0 : ms;
    final totalSeconds = safe ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds ~/ 60) % 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
