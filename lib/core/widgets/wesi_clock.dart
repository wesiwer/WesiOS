import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../localization/wesi_locale.dart';
import '../theme/app_theme.dart';

enum ClockStyle { digital, analog }

class WesiClock extends StatefulWidget {
  final bool showSeconds;
  final ClockStyle? forceStyle;

  const WesiClock({
    super.key,
    this.showSeconds = true,
    this.forceStyle,
  });

  static const _box = 'wesios_settings';
  static const _styleKey = 'clock_style';

  static ClockStyle get savedStyle {
    try {
      final value = Hive.box(_box).get(_styleKey) as String?;
      if (value == 'analog') return ClockStyle.analog;
    } catch (_) {}
    return ClockStyle.digital;
  }

  static Future<void> setStyle(ClockStyle style) async {
    try {
      await Hive.box(_box).put(
        _styleKey,
        style == ClockStyle.analog ? 'analog' : 'digital',
      );
    } catch (_) {}
  }

  @override
  State<WesiClock> createState() => _WesiClockState();
}

class _WesiClockState extends State<WesiClock> {
  late DateTime _now;
  Timer? _timer;
  late ClockStyle _style;

  static const _monthsRu = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
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
  static const _weekdaysRu = [
    'понедельник',
    'вторник',
    'среда',
    'четверг',
    'пятница',
    'суббота',
    'воскресенье',
  ];
  static const _weekdaysEn = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _style = widget.forceStyle ?? WesiClock.savedStyle;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void didUpdateWidget(covariant WesiClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.forceStyle ?? WesiClock.savedStyle;
    if (next != _style) _style = next;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, _, __) => LayoutBuilder(
        builder: (context, constraints) {
          final ru = WesiLocale.isRussian;
          final month = (ru ? _monthsRu : _monthsEn)[_now.month - 1];
          final weekday =
              (ru ? _weekdaysRu : _weekdaysEn)[_now.weekday - 1];
          final date = ru
              ? '${_now.day} $month ${_now.year}'
              : '$month ${_now.day}, ${_now.year}';

          final screenWidth = MediaQuery.sizeOf(context).width;
          final available = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : math.min(270.0, screenWidth - 32);
          // Ширина месяца — это читаемость чисел, а не украшение: на
          // 86 px в клетку помещалось 6 px, и «17» превращалось в точки.
          final calendarWidth = available < 205 ? 78.0 : 96.0;
          final gap = available < 205 ? 5.0 : 9.0;
          final clockWidth = math.max(72.0, available - calendarWidth - gap);
          final digitalSize = clockWidth < 104
              ? 20.0
              : clockWidth < 132
                  ? 23.0
                  : 27.0;
          final analogSize = math.min(72.0, math.max(58.0, clockWidth * .66));

          final clock = _style == ClockStyle.analog
              ? _AnalogFace(now: _now, size: analogSize)
              : Text(
                  widget.showSeconds
                      ? '${_two(_now.hour)}:${_two(_now.minute)}:${_two(_now.second)}'
                      : '${_two(_now.hour)}:${_two(_now.minute)}',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: digitalSize,
                    fontWeight: FontWeight.w200,
                    color: AppTheme.textPrimary,
                    letterSpacing: .8,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                );

          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              clock,
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      date,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _style == ClockStyle.digital
                        ? Icons.schedule
                        : Icons.watch_later_outlined,
                    size: 12,
                    color: AppTheme.accent,
                  ),
                ],
              ),
              Text(
                weekday,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  color: AppTheme.textMuted.withOpacity(.82),
                ),
              ),
            ],
          );

          return SizedBox(
            width: available,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: clockWidth,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: SizedBox(width: clockWidth, child: info),
                  ),
                ),
                SizedBox(width: gap),
                _MiniMonthCalendar(now: _now, width: calendarWidth),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MiniMonthCalendar extends StatelessWidget {
  final DateTime now;
  final double width;

  const _MiniMonthCalendar({required this.now, required this.width});

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    final first = DateTime(now.year, now.month, 1);
    final days = DateTime(now.year, now.month + 1, 0).day;
    final offset = first.weekday - 1;
    final title = ru
        ? '${_monthRu(now.month)} ${now.year}'
        : '${_monthEn(now.month)} ${now.year}';
    final weekdays = ru
        ? const ['П', 'В', 'С', 'Ч', 'П', 'С', 'В']
        : const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
      width: width,
      padding: EdgeInsets.fromLTRB(
        width < 88 ? 5 : 7,
        6,
        width < 88 ? 5 : 7,
        6,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(.56),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: TextStyle(
              fontSize: width < 88 ? 7.6 : 9,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final day in weekdays)
                Expanded(
                  child: Text(
                    day,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: width < 88 ? 6 : 7,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          GridView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
            ),
            itemCount: 42,
            itemBuilder: (context, index) {
              final day = index - offset + 1;
              if (day < 1 || day > days) return const SizedBox.shrink();
              final today = day == now.day;
              return Container(
                alignment: Alignment.center,
                decoration: today
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.accent,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accent.withOpacity(.25),
                            blurRadius: 5,
                          ),
                        ],
                      )
                    : null,
                child: Text(
                  '$day',
                  style: TextStyle(
                    fontSize: width < 88 ? 7 : 8,
                    height: 1,
                    fontWeight: today ? FontWeight.w800 : FontWeight.w500,
                    color: today ? Colors.white : AppTheme.textSecondary,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  static String _monthRu(int month) => const [
        'янв',
        'фев',
        'мар',
        'апр',
        'май',
        'июн',
        'июл',
        'авг',
        'сен',
        'окт',
        'ноя',
        'дек',
      ][month - 1];

  static String _monthEn(int month) => const [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ][month - 1];
}

class _AnalogFace extends StatelessWidget {
  final DateTime now;
  final double size;

  const _AnalogFace({required this.now, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _AnalogPainter(now)),
    );
  }
}

class _AnalogPainter extends CustomPainter {
  final DateTime now;
  _AnalogPainter(this.now);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppTheme.surface.withOpacity(.9)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      radius - .75,
      Paint()
        ..color = AppTheme.glassBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final tick = Paint()
      ..color = AppTheme.textMuted.withOpacity(.45)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 60; i++) {
      if (i % 5 == 0) continue;
      final angle = (i * 6 - 90) * math.pi / 180;
      canvas.drawLine(
        Offset(
          center.dx + (radius - 5.5) * math.cos(angle),
          center.dy + (radius - 5.5) * math.sin(angle),
        ),
        Offset(
          center.dx + (radius - 2.5) * math.cos(angle),
          center.dy + (radius - 2.5) * math.sin(angle),
        ),
        tick,
      );
    }

    final numberStyle = TextStyle(
      color: AppTheme.textPrimary,
      fontSize: radius * .22,
      fontWeight: FontWeight.w600,
      height: 1,
    );
    for (var hour = 1; hour <= 12; hour++) {
      final angle = (hour * 30 - 90) * math.pi / 180;
      final painter = TextPainter(
        text: TextSpan(text: '$hour', style: numberStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          center.dx + (radius - radius * .28) * math.cos(angle) -
              painter.width / 2,
          center.dy + (radius - radius * .28) * math.sin(angle) -
              painter.height / 2,
        ),
      );
    }

    final second = now.second + now.millisecond / 1000;
    final minute = now.minute + second / 60;
    final hour = (now.hour % 12) + minute / 60;
    final hourAngle = (hour * 30 - 90) * math.pi / 180;
    final minuteAngle = (minute * 6 - 90) * math.pi / 180;
    final secondAngle = (second * 6 - 90) * math.pi / 180;

    void hand(double angle, double length, double stroke, Color color) {
      canvas.drawLine(
        center,
        Offset(
          center.dx + radius * length * math.cos(angle),
          center.dy + radius * length * math.sin(angle),
        ),
        Paint()
          ..color = color
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    hand(hourAngle, .40, 2.8, AppTheme.textPrimary);
    hand(minuteAngle, .58, 2, AppTheme.textPrimary);
    hand(secondAngle, .70, 1.2, AppTheme.accent);
    canvas.drawCircle(center, 2.5, Paint()..color = AppTheme.accent);
  }

  @override
  bool shouldRepaint(covariant _AnalogPainter old) =>
      old.now.second != now.second ||
      old.now.minute != now.minute ||
      old.now.hour != now.hour;
}
