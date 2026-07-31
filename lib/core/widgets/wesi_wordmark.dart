import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Логотип WesiOS: геометрический знак + название.
///
/// Знак — монограмма W, у которой последний штрих уходит выше остальных:
/// буква читается, но силуэт одновременно похож на восходящий график.
/// Цвета зависят от темы: dark — белый + оранжевый акцент; light —
/// серо-синий (slate) + голубой акцент.
class WesiWordmark extends StatelessWidget {
  /// Высота знака. Текст масштабируется от неё.
  final double size;

  /// Показывать ли надпись рядом со знаком.
  final bool showText;

  /// Цвет надписи. `null` — [AppTheme.textPrimary] (адаптируется к теме).
  final Color? textColor;

  /// Знак слева от надписи. По умолчанию false — надпись идёт первой.
  final bool markFirst;

  const WesiWordmark({
    super.key,
    this.size = 32,
    this.showText = true,
    this.textColor,
    this.markFirst = false,
  });

  static TextStyle textStyle(double size, [Color? color]) => TextStyle(
        fontSize: size * 0.78,
        fontWeight: FontWeight.w800,
        color: color ?? AppTheme.textPrimary,
        letterSpacing: size * 0.06,
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, mode, _) {
        final mark = SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _WesiMarkPainter(
              stroke: AppTheme.logoStroke,
              accent: AppTheme.logoAccent,
            ),
          ),
        );

        if (!showText) return mark;

        final text = Text(
          'WesiOS',
          style: textStyle(size, textColor ?? AppTheme.textPrimary),
        );
        final gap = SizedBox(width: size * 0.34);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: markFirst ? [mark, gap, text] : [text, gap, mark],
        );
      },
    );
  }
}

/// Заголовок экрана в фирменном стиле.
class WesiTitle extends StatelessWidget {
  final String text;
  final double size;
  final Color? color;

  const WesiTitle(
    this.text, {
    super.key,
    this.size = 26,
    this.color,
  });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppThemeMode>(
        valueListenable: ThemeNotifier.instance,
        builder: (context, _, __) => Text(
          text,
          style: WesiWordmark.textStyle(size, color ?? AppTheme.textPrimary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
}

/// Рисует знак векторно: остаётся чётким на любом размере и совпадает
/// с геометрией app_icon.
class _WesiMarkPainter extends CustomPainter {
  final Color stroke;
  final Color accent;

  _WesiMarkPainter({required this.stroke, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final w = s * 0.155;

    final top = s * 0.20;
    final bottom = s * 0.80;
    final x0 = s * 0.06;
    final x1 = s * 0.94;
    final span = x1 - x0;

    final p0 = Offset(x0, top);
    final p1 = Offset(x0 + span * 0.235, bottom);
    final p2 = Offset(s * 0.5, top + (bottom - top) * 0.42);
    final p3 = Offset(x1 - span * 0.235, bottom);
    final p4 = Offset(x1, top - (bottom - top) * 0.42);

    final mainPaint = Paint()
      ..color = stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final accentPaint = Paint()
      ..color = accent
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(
      Path()
        ..moveTo(p0.dx, p0.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy),
      mainPaint,
    );
    canvas.drawLine(p3, p4, accentPaint);
  }

  @override
  bool shouldRepaint(covariant _WesiMarkPainter oldDelegate) =>
      oldDelegate.stroke != stroke || oldDelegate.accent != accent;
}
