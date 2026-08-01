import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../theme/app_theme.dart';
import '../localization/wesi_locale.dart';

/// Стиль часов на главной.
enum ClockStyle { digital, analog }

/// Живые часы с датой для главного экрана.
///
/// Два режима: цифровые и аналоговый циферблат с цифрами.
/// Переключение — долгий тап (обрабатывает родитель) или кнопка рядом.
/// Выбор пишется в Hive и переживает рестарт.
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
      final v = Hive.box(_box).get(_styleKey) as String?;
      if (v == 'analog') return ClockStyle.analog;
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
    _style = widget.forceStyle ?? WesiClock.savedStyle;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void didUpdateWidget(covariant WesiClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Подхватываем смену стиля извне (long-press на родителе).
    final next = widget.forceStyle ?? WesiClock.savedStyle;
    if (next != _style) _style = next;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  Future<void> _toggleStyle() async {
    final next = _style == ClockStyle.digital
        ? ClockStyle.analog
        : ClockStyle.digital;
    await WesiClock.setStyle(next);
    if (mounted) setState(() => _style = next);
  }

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    final month = (ru ? _monthsRu : _monthsEn)[_now.month - 1];
    final weekday = (ru ? _weekdaysRu : _weekdaysEn)[_now.weekday - 1];
    final date = ru
        ? '${_now.day} $month ${_now.year}'
        : '$month ${_now.day}, ${_now.year}';

    final width = MediaQuery.sizeOf(context).width;
    final digitalSize = width < 380
        ? 22.0
        : width < 480
            ? 26.0
            : 32.0;

    // Аналоговый циферблат чуть крупнее, чтобы цифры читались
    final analogSize = width < 400 ? 64.0 : 72.0;

    final clock = _style == ClockStyle.analog
        ? _AnalogFace(now: _now, size: analogSize)
        : Text(
            widget.showSeconds
                ? '${_two(_now.hour)}:${_two(_now.minute)}:${_two(_now.second)}'
                : '${_two(_now.hour)}:${_two(_now.minute)}',
            style: TextStyle(
              fontSize: digitalSize,
              fontWeight: FontWeight.w200,
              color: AppTheme.textPrimary,
              letterSpacing: 1.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            clock,
            SizedBox(height: 2),
            Text(
              date,
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
            Text(
              weekday,
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.textMuted.withOpacity(0.8),
              ),
            ),
          ],
        ),
        SizedBox(width: 8),
        GestureDetector(
          onTap: _toggleStyle,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.glassBorder,
                width: 1,
              ),
            ),
            child: Icon(
              _style == ClockStyle.digital
                  ? Icons.access_time
                  : Icons.timer,
              size: 16,
              color: AppTheme.accent,
            ),
          ),
        ),
      ],
    );
  }
}

/// Аналоговый циферблат с цифрами 1–12.
class _AnalogFace extends StatelessWidget {
  final DateTime now;
  final double size;

  const _AnalogFace({required this.now, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AnalogPainter(now),
      ),
    );
  }
}

class _AnalogPainter extends CustomPainter {
  final DateTime now;
  _AnalogPainter(this.now);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;

    // Фон
    final bg = Paint()
      ..color = AppTheme.surface.withOpacity(0.9)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(c, r, bg);

    // Ободок
    final border = Paint()
      ..color = AppTheme.glassBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(c, r - 0.75, border);

    // Минутные деления (тонкие)
    final minorTick = Paint()
      ..color = AppTheme.textMuted.withOpacity(0.45)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 60; i++) {
      if (i % 5 == 0) continue; // часовые — цифры
      final a = (i * 6 - 90) * math.pi / 180;
      final outer = Offset(
        c.dx + (r - 2.5) * math.cos(a),
        c.dy + (r - 2.5) * math.sin(a),
      );
      final inner = Offset(
        c.dx + (r - 5.5) * math.cos(a),
        c.dy + (r - 5.5) * math.sin(a),
      );
      canvas.drawLine(inner, outer, minorTick);
    }

    // Цифры 1–12
    final textStyle = TextStyle(
      color: AppTheme.textPrimary,
      fontSize: r * 0.22,
      fontWeight: FontWeight.w600,
      height: 1.0,
    );
    for (var h = 1; h <= 12; h++) {
      final a = (h * 30 - 90) * math.pi / 180;
      final label = '$h';
      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final pos = Offset(
        c.dx + (r - r * 0.28) * math.cos(a) - tp.width / 2,
        c.dy + (r - r * 0.28) * math.sin(a) - tp.height / 2,
      );
      tp.paint(canvas, pos);
    }

    // Углы стрелок
    final sec = now.second + now.millisecond / 1000;
    final min = now.minute + sec / 60;
    final hour = (now.hour % 12) + min / 60;

    final hourA = (hour * 30 - 90) * math.pi / 180;
    final minA = (min * 6 - 90) * math.pi / 180;
    final secA = (sec * 6 - 90) * math.pi / 180;

    // Часовая
    final hourPaint = Paint()
      ..color = AppTheme.textPrimary
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      c,
      Offset(c.dx + r * 0.40 * math.cos(hourA),
          c.dy + r * 0.40 * math.sin(hourA)),
      hourPaint,
    );

    // Минутная
    final minPaint = Paint()
      ..color = AppTheme.textPrimary
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      c,
      Offset(c.dx + r * 0.58 * math.cos(minA),
          c.dy + r * 0.58 * math.sin(minA)),
      minPaint,
    );

    // Секундная
    final secPaint = Paint()
      ..color = AppTheme.accent
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      c,
      Offset(c.dx + r * 0.70 * math.cos(secA),
          c.dy + r * 0.70 * math.sin(secA)),
      secPaint,
    );

    // Центральная точка
    canvas.drawCircle(c, 2.5, Paint()..color = AppTheme.accent);
  }

  @override
  bool shouldRepaint(covariant _AnalogPainter old) =>
      old.now.second != now.second ||
      old.now.minute != now.minute ||
      old.now.hour != now.hour;
}
