import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../localization/wesi_locale.dart';

/// Живые часы с датой для главного экрана.
///
/// Тикает раз в секунду и **только пока виджет на экране**: таймер заводится
/// в initState и гасится в dispose, иначе он продолжал бы будить UI, когда
/// пользователь ушёл на другую вкладку (вкладки живут в IndexedStack и не
/// уничтожаются).
class WesiClock extends StatefulWidget {
  /// Показывать ли секунды. На главном они уместны — экран «живой»,
  /// но в компактных местах лишняя перерисовка каждую секунду не нужна.
  final bool showSeconds;

  const WesiClock({super.key, this.showSeconds = true});

  @override
  State<WesiClock> createState() => _WesiClockState();
}

class _WesiClockState extends State<WesiClock> {
  late DateTime _now;
  Timer? _timer;

  static const _monthsRu = [
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];
  static const _monthsEn = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _weekdaysRu = [
    'понедельник', 'вторник', 'среда', 'четверг',
    'пятница', 'суббота', 'воскресенье',
  ];
  static const _weekdaysEn = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    final time = widget.showSeconds
        ? '${_two(_now.hour)}:${_two(_now.minute)}:${_two(_now.second)}'
        : '${_two(_now.hour)}:${_two(_now.minute)}';
    final month = (ru ? _monthsRu : _monthsEn)[_now.month - 1];
    final weekday = (ru ? _weekdaysRu : _weekdaysEn)[_now.weekday - 1];
    final date = ru
        ? '${_now.day} $month ${_now.year}'
        : '$month ${_now.day}, ${_now.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          time,
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w200,
            color: AppTheme.textPrimary,
            letterSpacing: 2,
            // Табличные цифры: без этого строка «дышит» по ширине каждую
            // секунду, потому что glyph'ы разной ширины.
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          date,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        Text(
          weekday,
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textMuted.withOpacity(0.8),
          ),
        ),
      ],
    );
  }
}
