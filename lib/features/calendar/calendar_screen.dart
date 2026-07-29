import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/widgets/module_scaffold.dart';

/// Календарь. Сетка месяца — настоящая и рабочая: листается, показывает
/// сегодняшний день, даёт выбрать дату. Привязка событий/задач к датам —
/// следующий шаг, поэтому модуль помечен как частично готовый, а панель
/// событий явно нарисована заглушкой.
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

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selected = DateTime(now.year, now.month, now.day);
    _visibleMonth = DateTime(now.year, now.month);
  }

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
            ? 'Отметки на датах: задачи из «Задач», платежи из Treasury'
            : 'Day markers: items from Tasks, payments from Treasury',
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
          style: const TextStyle(
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
            style: const TextStyle(color: AppTheme.accentOrange, fontSize: 12),
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
        child: Center(
          child: Text(
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
        ),
      ),
    );
  }

  Widget _selectedDayPanel(bool ru) {
    final months = ru ? _monthsRu : _monthsEn;
    final label = ru
        ? '${_selected.day} ${months[_selected.month - 1].toLowerCase()} ${_selected.year}'
        : '${months[_selected.month - 1]} ${_selected.day}, ${_selected.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        StubBlock(
          icon: Icons.event_note,
          height: 100,
          label: ru
              ? 'События этого дня появятся здесь, когда календарь свяжут\nс задачами и регулярными платежами'
              : 'Events for this day will appear here once the calendar is\nlinked to tasks and recurring payments',
        ),
      ],
    );
  }
}
