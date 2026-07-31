import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/services/currency_service.dart';
import '../../core/services/recurrence.dart';
import '../../core/widgets/module_scaffold.dart';
import '../tasks/models/task_model.dart';
import '../tasks/services/task_service.dart';
import '../treasury/models/transaction_model.dart';
import '../treasury/services/treasury_service.dart';

/// Календарь. Сетка месяца листается, показывает сегодняшний день и даёт
/// выбрать дату; на датах стоят отметки, а под сеткой — что именно в этот
/// день происходит: сроки задач и регулярные списания.
///
/// Задачи и платежи читаются из тех же сервисов, что и остальные экраны:
/// свой источник данных у календаря однажды разошёлся бы с доской задач.
///
/// Сетка написана вручную, а не через `table_calendar`: нужен ровно месяц
/// в тёмной теме проекта и понедельник первым днём недели, а зависимость
/// в pubspec всё равно числится неиспользуемой (см. STATUS.md) — тянуть её
/// ради одного экрана смысла нет.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _visibleMonth;
  late DateTime _selected;

  static const _monthsRu = [
    'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
  ];
  static const _monthsEn = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  List<TaskModel> _tasks = const [];
  List<TransactionModel> _recurring = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selected = DateTime(now.year, now.month, now.day);
    _visibleMonth = DateTime(now.year, now.month);
    _load();
    // Экран открывается поверх вкладок и не пересоздаётся при возврате:
    // без подписок правка задачи не доехала бы до отметок на датах.
    TaskService.revision.addListener(_load);
    TreasuryService.revision.addListener(_load);
  }

  @override
  void dispose() {
    TaskService.revision.removeListener(_load);
    TreasuryService.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final tasks = await TaskService().getAll();
    final transactions = await TreasuryService().getAllTransactions();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _recurring = transactions.where((t) => t.isRecurring).toList();
    });
  }

  /// Задачи, у которых срок приходится на этот день.
  List<TaskModel> _tasksOn(DateTime day) => _tasks.where((t) {
        final due = t.dueDate;
        if (due == null) return false;
        return due.year == day.year &&
            due.month == day.month &&
            due.day == day.day;
      }).toList();

  /// Регулярные операции, которые списываются в этот день.
  List<TransactionModel> _paymentsOn(DateTime day) =>
      _recurring.where((t) => Recurrence.occursOn(t, day)).toList();

  void _shiftMonth(int delta) {
    setState(() {
      // Через конструктор DateTime, а не сложение дней: он сам нормализует
      // переход через границу года (месяц 13 -> январь следующего).
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    return ModuleScaffold(
      title: ru ? 'Календарь' : 'Calendar',
      subtitle: ru
          ? 'Даты, планирование и связь событий с задачами и финансами'
          : 'Dates, planning, and linking events to tasks and finances',
      icon: Icons.calendar_month,
      stage: ModuleStage.partial,
      plannedFeatures: [
        ru
            ? 'События и напоминания с привязкой к конкретному дню'
            : 'Events and reminders attached to a specific day',
        ru
            ? 'Повторяющиеся события (еженедельные планёрки, оплаты)'
            : 'Recurring events (weekly standups, payments)',
        ru
            ? 'Режимы недели и года в дополнение к месяцу'
            : 'Week and year views alongside the month grid',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _monthHeader(ru),
          const SizedBox(height: 14),
          _weekdayRow(ru),
          const SizedBox(height: 8),
          _monthGrid(),
          const SizedBox(height: 20),
          _selectedDayPanel(ru),
        ],
      ),
    );
  }

  Widget _monthHeader(bool ru) {
    final name = (ru ? _monthsRu : _monthsEn)[_visibleMonth.month - 1];
    return Row(
      children: [
        Text(
          '$name ${_visibleMonth.year}',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const Spacer(),
        _navButton(Icons.chevron_left, () => _shiftMonth(-1)),
        const SizedBox(width: 4),
        TextButton(
          onPressed: () {
            final now = DateTime.now();
            setState(() {
              _visibleMonth = DateTime(now.year, now.month);
              _selected = DateTime(now.year, now.month, now.day);
            });
          },
          child: Text(
            ru ? 'Сегодня' : 'Today',
            style: TextStyle(color: AppTheme.accentOrange, fontSize: 12),
          ),
        ),
        const SizedBox(width: 4),
        _navButton(Icons.chevron_right, () => _shiftMonth(1)),
      ],
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Icon(icon, size: 18, color: AppTheme.textSecondary),
      ),
    );
  }

  Widget _weekdayRow(bool ru) {
    final labels = ru
        ? const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']
        : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Row(
      children: [
        for (int i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  // Выходные приглушены — взгляд сразу цепляет рабочую неделю.
                  color: i >= 5
                      ? AppTheme.accentRed.withOpacity(0.7)
                      : AppTheme.textMuted,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _monthGrid() {
    final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    // weekday: Пн=1..Вс=7 — сдвигаем так, чтобы неделя начиналась с Пн.
    final leadingBlanks = firstOfMonth.weekday - 1;
    // День 0 следующего месяца = последний день текущего. Заодно корректно
    // отрабатывает февраль високосного года без отдельной ветки.
    final daysInMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final totalCells = leadingBlanks + daysInMonth;
    final rows = (totalCells / 7).ceil();
    final today = DateTime.now();

    return Column(
      children: [
        for (int row = 0; row < rows; row++)
          Row(
            children: [
              for (int col = 0; col < 7; col++)
                Expanded(
                  child: Builder(builder: (_) {
                    final cellIndex = row * 7 + col;
                    final dayNumber = cellIndex - leadingBlanks + 1;
                    if (dayNumber < 1 || dayNumber > daysInMonth) {
                      return const SizedBox(height: 42);
                    }
                    final date = DateTime(
                        _visibleMonth.year, _visibleMonth.month, dayNumber);
                    return _dayCell(date, today, col >= 5);
                  }),
                ),
            ],
          ),
      ],
    );
  }

  Widget _dayCell(DateTime date, DateTime today, bool isWeekend) {
    final isToday = _isSameDay(date, today);
    final isSelected = _isSameDay(date, _selected);

    final tasks = _tasksOn(date);
    final payments = _paymentsOn(date);
    // Просроченной считается только незавершённая задача с прошедшим сроком:
    // иначе календарь краснел бы от уже сделанного.
    final hasOverdue = tasks.any((t) =>
        t.status != TaskStatus.done && date.isBefore(today) && !isToday);

    return GestureDetector(
      onTap: () => setState(() => _selected = date),
      child: Container(
        height: 42,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accentOrange.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppTheme.accentOrange.withOpacity(0.6)
                : (isToday
                    ? AppTheme.accentOrange.withOpacity(0.35)
                    : Colors.transparent),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    isToday || isSelected ? FontWeight.w800 : FontWeight.w400,
                color: isSelected || isToday
                    ? AppTheme.accentOrange
                    : (isWeekend ? AppTheme.textMuted : AppTheme.textPrimary),
              ),
            ),
            // Точки, а не числа: в ячейке 42 px цифра рядом с датой читается
            // как часть даты. Цвет отделяет задачи от денег.
            if (tasks.isNotEmpty || payments.isNotEmpty) ...[
              const SizedBox(height: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (tasks.isNotEmpty)
                    _dot(hasOverdue ? AppTheme.accentRed : AppTheme.primary),
                  if (tasks.isNotEmpty && payments.isNotEmpty)
                    const SizedBox(width: 3),
                  if (payments.isNotEmpty) _dot(AppTheme.accentOrange),
                ],
              ),
            ] else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color) => Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Widget _selectedDayPanel(bool ru) {
    final months = ru ? _monthsRu : _monthsEn;
    final label = ru
        ? '${_selected.day} ${months[_selected.month - 1].toLowerCase()} ${_selected.year}'
        : '${months[_selected.month - 1]} ${_selected.day}, ${_selected.year}';

    final tasks = _tasksOn(_selected);
    final payments = _paymentsOn(_selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            if (tasks.isNotEmpty || payments.isNotEmpty)
              Text(
                ru
                    ? '${tasks.length + payments.length} событ.'
                    : '${tasks.length + payments.length} events',
                style: TextStyle(
                    fontSize: 11, color: AppTheme.textMuted),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (tasks.isEmpty && payments.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Text(
              ru ? 'В этот день ничего не запланировано' : 'Nothing on this day',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          )
        else ...[
          ...tasks.map((t) => _eventRow(
                icon: Icons.check_circle_outline,
                color: t.status == TaskStatus.done
                    ? AppTheme.accentGreen
                    : AppTheme.primary,
                title: t.title,
                trailing: _statusLabel(t.status, ru),
                onTap: () => Navigator.pushNamed(context, '/tasks'),
              )),
          ...payments.map((t) => _eventRow(
                icon: t.type == TransactionType.income
                    ? Icons.arrow_downward
                    : Icons.arrow_upward,
                color: t.type == TransactionType.income
                    ? AppTheme.accentGreen
                    : AppTheme.accentOrange,
                title: t.title,
                trailing: CurrencyService.format(t.amount),
                onTap: () =>
                    Navigator.pushNamed(context, '/treasury/operations'),
              )),
        ],
      ],
    );
  }

  String _statusLabel(TaskStatus status, bool ru) {
    if (!ru) return status.name;
    return switch (status) {
      TaskStatus.backlog => 'бэклог',
      TaskStatus.inProgress => 'в работе',
      TaskStatus.review => 'на проверке',
      TaskStatus.done => 'готово',
    };
  }

  Widget _eventRow({
    required IconData icon,
    required Color color,
    required String title,
    required String trailing,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, color: AppTheme.textPrimary),
                ),
              ),
              const SizedBox(width: 10),
              Text(trailing,
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.textMuted)),
            ],
          ),
        ),
      );
}
