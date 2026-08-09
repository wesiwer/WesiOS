import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/services/currency_service.dart';
import '../../core/services/recurrence.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/module_scaffold.dart';
import '../tasks/models/task_model.dart';
import '../tasks/services/task_service.dart';
import '../treasury/models/transaction_model.dart';
import '../treasury/services/treasury_service.dart';
import 'models/calendar_event.dart';
import 'services/calendar_event_service.dart';

enum _CalendarView { month, week, year }

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final CalendarEventService _eventsService = CalendarEventService();

  late DateTime _visibleMonth;
  late DateTime _selected;
  _CalendarView _view = _CalendarView.month;

  List<TaskModel> _tasks = const [];
  List<TransactionModel> _recurring = const [];
  List<CalendarEvent> _events = const [];
  bool _loading = true;

  bool get _ru => WesiLocale.isRussian;

  static const _monthsRu = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];
  static const _monthsEn = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selected = _day(now);
    _visibleMonth = DateTime(now.year, now.month);
    TaskService.revision.addListener(_load);
    TreasuryService.revision.addListener(_load);
    CalendarEventService.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    TaskService.revision.removeListener(_load);
    TreasuryService.revision.removeListener(_load);
    CalendarEventService.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final tasks = await TaskService().getAll();
    final transactions = await TreasuryService().getAllTransactions();
    final events = await _eventsService.getAll();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _recurring = transactions.where((item) => item.isRecurring).toList();
      _events = events;
      _loading = false;
    });
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<TaskModel> _tasksOn(DateTime day) => _tasks.where((task) {
        final due = task.dueDate;
        return due != null && _sameDay(due, day);
      }).toList();

  List<TransactionModel> _paymentsOn(DateTime day) =>
      _recurring.where((item) => Recurrence.occursOn(item, day)).toList();

  List<CalendarEvent> _eventsOn(DateTime day) =>
      _events.where((event) => event.occursOn(day)).toList();

  void _selectDay(DateTime date) {
    setState(() {
      _selected = _day(date);
      _visibleMonth = DateTime(date.year, date.month);
    });
  }

  void _shift(int direction) {
    setState(() {
      switch (_view) {
        case _CalendarView.month:
          _visibleMonth =
              DateTime(_visibleMonth.year, _visibleMonth.month + direction);
          final maxDay =
              DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
          final selectedDay = _selected.day > maxDay ? maxDay : _selected.day;
          _selected = DateTime(
            _visibleMonth.year,
            _visibleMonth.month,
            selectedDay,
          );
          break;
        case _CalendarView.week:
          _selected = _selected.add(Duration(days: 7 * direction));
          _visibleMonth = DateTime(_selected.year, _selected.month);
          break;
        case _CalendarView.year:
          _visibleMonth = DateTime(_visibleMonth.year + direction, 1);
          _selected = DateTime(_visibleMonth.year, _selected.month, 1);
          break;
      }
    });
  }

  void _today() {
    final now = _day(DateTime.now());
    setState(() {
      _selected = now;
      _visibleMonth = DateTime(now.year, now.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ModuleScaffold(
      title: _ru ? 'Календарь' : 'Calendar',
      subtitle: _ru
          ? 'События, задачи, финансы и напоминания в одной временной шкале'
          : 'Events, tasks, finance and reminders on one timeline',
      icon: Icons.calendar_month_rounded,
      stage: ModuleStage.ready,
      plannedFeatures: const [],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _toolbar(),
          const SizedBox(height: 14),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2)
          else ...[
            if (_view == _CalendarView.month) _monthView(),
            if (_view == _CalendarView.week) _weekView(),
            if (_view == _CalendarView.year) _yearView(),
            const SizedBox(height: 20),
            _selectedDayPanel(),
          ],
        ],
      ),
    );
  }

  Widget _toolbar() {
    final title = switch (_view) {
      _CalendarView.month =>
        '${(_ru ? _monthsRu : _monthsEn)[_visibleMonth.month - 1]} ${_visibleMonth.year}',
      _CalendarView.week => _weekTitle(),
      _CalendarView.year => '${_visibleMonth.year}',
    };

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: _ru ? 'Назад' : 'Previous',
              onPressed: () => _shift(-1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            TextButton(
                onPressed: _today, child: Text(_ru ? 'Сегодня' : 'Today')),
            IconButton(
              tooltip: _ru ? 'Вперёд' : 'Next',
              onPressed: () => _shift(1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _viewChip(_CalendarView.month, _ru ? 'Месяц' : 'Month'),
                  _viewChip(_CalendarView.week, _ru ? 'Неделя' : 'Week'),
                  _viewChip(_CalendarView.year, _ru ? 'Год' : 'Year'),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _editEvent(),
              icon: const Icon(Icons.add_rounded),
              label: Text(_ru ? 'Событие' : 'Event'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _viewChip(_CalendarView view, String label) {
    return ChoiceChip(
      selected: _view == view,
      label: Text(label),
      onSelected: (_) => setState(() => _view = view),
    );
  }

  Widget _monthView() {
    final labels = _ru
        ? const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']
        : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final first = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final leading = first.weekday - 1;
    final days = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final total = ((leading + days + 6) ~/ 7) * 7;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: _panelDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: i >= 5
                            ? AppTheme.accentRed.withOpacity(.75)
                            : AppTheme.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          GridView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.18,
            ),
            itemCount: total,
            itemBuilder: (_, index) {
              final number = index - leading + 1;
              if (number < 1 || number > days) return const SizedBox.shrink();
              return _dayCell(
                  DateTime(_visibleMonth.year, _visibleMonth.month, number));
            },
          ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime date) {
    final today = _sameDay(date, DateTime.now());
    final selected = _sameDay(date, _selected);
    final events = _eventsOn(date);
    final tasks = _tasksOn(date);
    final payments = _paymentsOn(date);
    final weekend = date.weekday >= DateTime.saturday;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _selectDay(date),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color:
              selected ? AppTheme.accent.withOpacity(.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppTheme.accent.withOpacity(.65)
                : today
                    ? AppTheme.accent.withOpacity(.3)
                    : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(
                color: selected || today
                    ? AppTheme.accent
                    : weekend
                        ? AppTheme.textMuted
                        : AppTheme.textPrimary,
                fontWeight:
                    selected || today ? FontWeight.w800 : FontWeight.w500,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (events.isNotEmpty) _dot(AppTheme.accent),
                if (tasks.isNotEmpty) _dot(AppTheme.primary),
                if (payments.isNotEmpty) _dot(AppTheme.accentGreen),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _weekView() {
    final monday = _selected.subtract(Duration(days: _selected.weekday - 1));
    return Column(
      children: [
        for (var offset = 0; offset < 7; offset++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _weekDayCard(monday.add(Duration(days: offset))),
          ),
      ],
    );
  }

  Widget _weekDayCard(DateTime date) {
    final events = _eventsOn(date);
    final tasks = _tasksOn(date);
    final payments = _paymentsOn(date);
    final selected = _sameDay(date, _selected);
    final count = events.length + tasks.length + payments.length;

    return InkWell(
      onTap: () => _selectDay(date),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: _panelDecoration(
          borderColor: selected ? AppTheme.accent.withOpacity(.55) : null,
          color: selected ? AppTheme.accent.withOpacity(.08) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 58,
              child: Column(
                children: [
                  Text(
                    _weekdayName(date.weekday),
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 10),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      color: selected ? AppTheme.accent : AppTheme.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: count == 0
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _ru ? 'Свободный день' : 'No items',
                        style:
                            TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final event in events.take(2))
                          _miniItem(Icons.event_rounded, AppTheme.accent,
                              event.title),
                        for (final task in tasks.take(2))
                          _miniItem(Icons.task_alt_rounded, AppTheme.primary,
                              task.title),
                        for (final payment in payments.take(1))
                          _miniItem(Icons.payments_outlined,
                              AppTheme.accentGreen, payment.title),
                        if (count > 5)
                          Text(
                            '+${count - 5}',
                            style: TextStyle(
                                color: AppTheme.textMuted, fontSize: 10),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniItem(IconData icon, Color color, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _yearView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 840
            ? 3
            : constraints.maxWidth >= 520
                ? 2
                : 1;
        const gap = 10.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var month = 1; month <= 12; month++)
              SizedBox(
                width: width,
                child: _miniMonth(_visibleMonth.year, month),
              ),
          ],
        );
      },
    );
  }

  Widget _miniMonth(int year, int month) {
    final first = DateTime(year, month, 1);
    final leading = first.weekday - 1;
    final days = DateTime(year, month + 1, 0).day;
    return InkWell(
      onTap: () {
        setState(() {
          _visibleMonth = DateTime(year, month);
          _selected = DateTime(year, month, 1);
          _view = _CalendarView.month;
        });
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: _panelDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (_ru ? _monthsRu : _monthsEn)[month - 1],
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            GridView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.15,
              ),
              itemCount: 42,
              itemBuilder: (_, index) {
                final number = index - leading + 1;
                if (number < 1 || number > days) return const SizedBox.shrink();
                final date = DateTime(year, month, number);
                final busy = _eventsOn(date).isNotEmpty ||
                    _tasksOn(date).isNotEmpty ||
                    _paymentsOn(date).isNotEmpty;
                final today = _sameDay(date, DateTime.now());
                return Container(
                  alignment: Alignment.center,
                  decoration: today
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.accent.withOpacity(.22),
                        )
                      : null,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        '$number',
                        style: TextStyle(
                          color:
                              today ? AppTheme.accent : AppTheme.textSecondary,
                          fontSize: 8,
                          fontWeight: today ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                      if (busy)
                        Positioned(
                          bottom: 1,
                          child: Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: AppTheme.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectedDayPanel() {
    final events = _eventsOn(_selected);
    final tasks = _tasksOn(_selected);
    final payments = _paymentsOn(_selected);
    final count = events.length + tasks.length + payments.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _fullDate(_selected),
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (count > 0)
              Text(
                _ru ? '$count событий' : '$count items',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 10),
              ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: _ru ? 'Добавить событие' : 'Add event',
              onPressed: () => _editEvent(initialDate: _selected),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (count == 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
            decoration: _panelDecoration(),
            child: Column(
              children: [
                Icon(Icons.event_available_outlined,
                    color: AppTheme.textMuted, size: 30),
                const SizedBox(height: 8),
                Text(
                  _ru
                      ? 'На этот день ничего не запланировано'
                      : 'Nothing planned for this day',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
          )
        else ...[
          for (final event in events) _eventTile(event),
          for (final task in tasks)
            _externalTile(
              icon: Icons.task_alt_rounded,
              color: task.status == TaskStatus.done
                  ? AppTheme.accentGreen
                  : AppTheme.primary,
              title: task.title,
              subtitle: _ru ? 'Задача' : 'Task',
              trailing: _taskStatus(task.status),
              onTap: () => Navigator.pushNamed(context, '/tasks'),
            ),
          for (final payment in payments)
            _externalTile(
              icon: Icons.payments_outlined,
              color: payment.type == TransactionType.income
                  ? AppTheme.accentGreen
                  : AppTheme.accent,
              title: payment.title,
              subtitle: _ru ? 'Регулярная операция' : 'Recurring operation',
              trailing: CurrencyService.format(payment.amount),
              onTap: () => Navigator.pushNamed(context, '/treasury/operations'),
            ),
        ],
      ],
    );
  }

  Widget _eventTile(CalendarEvent event) {
    final start = event.occurrenceStart(_selected);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _panelDecoration(),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.event_rounded, color: AppTheme.accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  event.allDay
                      ? (_ru ? 'Весь день' : 'All day')
                      : '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} · ${event.durationMinutes} ${_ru ? 'мин' : 'min'}',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 10),
                ),
                if (event.repeat != CalendarRepeat.none ||
                    event.reminderMinutesBefore != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [
                        if (event.repeat != CalendarRepeat.none)
                          _repeatLabel(event.repeat),
                        if (event.reminderMinutesBefore != null)
                          '${_ru ? 'напомнить' : 'remind'} ${_reminderLabel(event.reminderMinutesBefore!)}',
                      ].join(' · '),
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 9.5),
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') _editEvent(event: event);
              if (value == 'delete') _eventsService.delete(event.id);
              if (value == 'toggle')
                _eventsService.setEnabled(event, !event.enabled);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'edit', child: Text(_ru ? 'Изменить' : 'Edit')),
              PopupMenuItem(
                value: 'toggle',
                child: Text(event.enabled
                    ? (_ru ? 'Выключить' : 'Disable')
                    : (_ru ? 'Включить' : 'Enable')),
              ),
              PopupMenuItem(
                  value: 'delete', child: Text(_ru ? 'Удалить' : 'Delete')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _externalTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String trailing,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: _panelDecoration(),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            color: AppTheme.textMuted, fontSize: 9.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(trailing,
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editEvent({
    CalendarEvent? event,
    DateTime? initialDate,
  }) async {
    final now = DateTime.now();
    var date = initialDate ?? event?.startAt ?? _selected;
    var time = TimeOfDay.fromDateTime(
        event?.startAt ?? now.add(const Duration(hours: 1)));
    var allDay = event?.allDay ?? false;
    var duration = event?.durationMinutes ?? 60;
    var repeat = event?.repeat ?? CalendarRepeat.none;
    var reminder = event?.reminderMinutesBefore ?? -1;
    var enabled = event?.enabled ?? true;
    final title = TextEditingController(text: event?.title ?? '');
    final notes = TextEditingController(text: event?.notes ?? '');

    final result = await showDialog<CalendarEvent>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(event == null
              ? (_ru ? 'Новое событие' : 'New event')
              : (_ru ? 'Событие' : 'Event')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    autofocus: event == null,
                    decoration:
                        InputDecoration(labelText: _ru ? 'Название' : 'Title'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    maxLines: 2,
                    decoration:
                        InputDecoration(labelText: _ru ? 'Описание' : 'Notes'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: date,
                              firstDate: DateTime(now.year - 5),
                              lastDate: DateTime(now.year + 15),
                            );
                            if (picked != null)
                              setDialogState(() => date = picked);
                          },
                          icon: const Icon(Icons.event_outlined),
                          label: Text(_shortDate(date)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: allDay
                              ? null
                              : () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: time,
                                  );
                                  if (picked != null)
                                    setDialogState(() => time = picked);
                                },
                          icon: const Icon(Icons.schedule_outlined),
                          label: Text(allDay
                              ? (_ru ? 'Весь день' : 'All day')
                              : _time(time)),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_ru ? 'Весь день' : 'All day'),
                    value: allDay,
                    onChanged: (value) => setDialogState(() => allDay = value),
                  ),
                  if (!allDay)
                    DropdownButtonFormField<int>(
                      value: duration,
                      decoration: InputDecoration(
                          labelText: _ru ? 'Длительность' : 'Duration'),
                      items: const [15, 30, 60, 90, 120, 180]
                          .map((minutes) => DropdownMenuItem(
                                value: minutes,
                                child: Text('$minutes ${_ru ? 'мин' : 'min'}'),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null)
                          setDialogState(() => duration = value);
                      },
                    ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<CalendarRepeat>(
                    value: repeat,
                    decoration:
                        InputDecoration(labelText: _ru ? 'Повтор' : 'Repeat'),
                    items: CalendarRepeat.values
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(_repeatLabel(value)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => repeat = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    value: reminder,
                    decoration: InputDecoration(
                        labelText: _ru ? 'Напоминание' : 'Reminder'),
                    items: [-1, 0, 5, 10, 30, 60, 1440]
                        .map((minutes) => DropdownMenuItem(
                              value: minutes,
                              child: Text(minutes < 0
                                  ? (_ru ? 'Без напоминания' : 'No reminder')
                                  : _reminderLabel(minutes)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => reminder = value);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_ru ? 'Активно' : 'Enabled'),
                    value: enabled,
                    onChanged: (value) => setDialogState(() => enabled = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_ru ? 'Отмена' : 'Cancel'),
            ),
            FilledButton(
              onPressed: title.text.trim().isEmpty
                  ? null
                  : () {
                      final start = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        allDay ? 9 : time.hour,
                        allDay ? 0 : time.minute,
                      );
                      Navigator.pop(
                        context,
                        CalendarEvent(
                          id: event?.id ??
                              'event_${DateTime.now().microsecondsSinceEpoch}',
                          title: title.text.trim(),
                          notes: notes.text.trim(),
                          startAt: start,
                          durationMinutes: allDay ? 1440 : duration,
                          allDay: allDay,
                          repeat: repeat,
                          reminderMinutesBefore: reminder < 0 ? null : reminder,
                          enabled: enabled,
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
    if (result != null) {
      await _eventsService.save(result);
      _selectDay(result.startAt);
    }
  }

  BoxDecoration _panelDecoration({Color? color, Color? borderColor}) =>
      BoxDecoration(
        color: color ?? AppTheme.surface.withOpacity(.32),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor ?? AppTheme.glassBorder),
      );

  Widget _dot(Color color) => Container(
        width: 4,
        height: 4,
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  String _weekTitle() {
    final monday = _selected.subtract(Duration(days: _selected.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    return '${_shortDate(monday)} — ${_shortDate(sunday)}';
  }

  String _shortDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

  String _fullDate(DateTime date) {
    final month = (_ru ? _monthsRu : _monthsEn)[date.month - 1];
    return _ru
        ? '${date.day} ${month.toLowerCase()} ${date.year}'
        : '$month ${date.day}, ${date.year}';
  }

  String _time(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  String _weekdayName(int weekday) {
    const ru = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return (_ru ? ru : en)[weekday - 1];
  }

  String _repeatLabel(CalendarRepeat repeat) {
    if (_ru) {
      return switch (repeat) {
        CalendarRepeat.none => 'Не повторять',
        CalendarRepeat.daily => 'Каждый день',
        CalendarRepeat.weekly => 'Каждую неделю',
        CalendarRepeat.monthly => 'Каждый месяц',
        CalendarRepeat.yearly => 'Каждый год',
      };
    }
    return switch (repeat) {
      CalendarRepeat.none => 'No repeat',
      CalendarRepeat.daily => 'Daily',
      CalendarRepeat.weekly => 'Weekly',
      CalendarRepeat.monthly => 'Monthly',
      CalendarRepeat.yearly => 'Yearly',
    };
  }

  String _reminderLabel(int minutes) {
    if (minutes == 0) return _ru ? 'в момент события' : 'at event time';
    if (minutes == 1440) return _ru ? 'за 1 день' : '1 day before';
    if (minutes >= 60 && minutes % 60 == 0) {
      return _ru ? 'за ${minutes ~/ 60} ч' : '${minutes ~/ 60} h before';
    }
    return _ru ? 'за $minutes мин' : '$minutes min before';
  }

  String _taskStatus(TaskStatus status) {
    if (!_ru) return status.name;
    return switch (status) {
      TaskStatus.backlog => 'бэклог',
      TaskStatus.inProgress => 'в работе',
      TaskStatus.review => 'проверка',
      TaskStatus.done => 'готово',
    };
  }
}
