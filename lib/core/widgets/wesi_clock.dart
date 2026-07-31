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
/// Два режима: цифровые (как раньше) и аналоговый циферблат.
/// Переключение — долгий тап. Выбор пишется в Hive и переживает рестарт.
///
/// Тикает раз в секунду и **только пока виджет на экране**: таймер
/// заводится в initState и гасится в dispose, иначе он продолжал бы будить
/// UI, когда пользователь ушёл на другую вкладку (вкладки живут в
/// IndexedStack и не уничтожаются).
class WesiClock extends StatefulWidget {
  /// Показывать ли секунды в цифровом режиме. На главном они уместны —
  /// экран «живой», но в компактных местах лишняя перерисовка каждую
  /// секунду не нужна.
  final bool showSeconds;

  /// Принудительный стиль. null — берём из настроек пользователя.
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

    // На узких экранах цифровой шрифт не должен быть 34 — иначе шапка
    // давит статус-бар и лого.
    final width = MediaQuery.sizeOf(context).width;
    final digitalSize = width < 380
        ? 22.0
        : width < 480
            ? 26.0
            : 32.0;

    final clock = _style == ClockStyle.analog
        ? _AnalogFace(now: _now, size: width < 400 ? 52.0 : 60.0)
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
        // Часы и дата
        GestureDetector(
          onTap: () {}, // Родитель обработает тап
          behavior: HitTestBehavior.opaque,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              clock,
              const SizedBox(height: 2),
              Text(
                date,
                style: const TextStyle(
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
        ),
        const SizedBox(width: 8),
        // Переключатель стиля часов
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
              color: AppTheme.accentOrange,
            ),
          ),
        ),
      ],
    );
  }
}

/// Простой аналоговый циферблат: круг, часовые/минутные деления, три стрелки.
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

    // Часовые деления
    final tick = Paint()
      ..color = AppTheme.textMuted
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final a = (i * 30 - 90) * math.pi / 180;
      final outer = Offset(
        c.dx + (r - 3) * math.cos(a),
        c.dy + (r - 3) * math.sin(a),
      );
      final inner = Offset(
        c.dx + (r - 8) * math.cos(a),
        c.dy + (r - 8) * math.sin(a),
      );
      canvas.drawLine(inner, outer, tick);
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
      Offset(c.dx + r * 0.45 * math.cos(hourA),
          c.dy + r * 0.45 * math.sin(hourA)),
      hourPaint,
    );

    // Минутная
    final minPaint = Paint()
      ..color = AppTheme.textPrimary
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      c,
      Offset(c.dx + r * 0.68 * math.cos(minA),
          c.dy + r * 0.68 * math.sin(minA)),
      minPaint,
    );

    // Секундная (оранжевая)
    final secPaint = Paint()
      ..color = AppTheme.accentOrange
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      c,
      Offset(c.dx + r * 0.78 * math.cos(secA),
          c.dy + r * 0.78 * math.sin(secA)),
      secPaint,
    );

    // Центральная точка
    canvas.drawCircle(c, 2.5, Paint()..color = AppTheme.accentOrange);
  }

  @override
  bool shouldRepaint(covariant _AnalogPainter old) =>
      old.now.second != now.second ||
      old.now.minute != now.minute ||
      old.now.hour != now.hour;
}
