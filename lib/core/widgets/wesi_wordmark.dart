import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Логотип WesiOS: геометрический знак + название.
///
/// Знак — монограмма W, у которой последний штрих уходит выше остальных:
/// буква читается, но силуэт одновременно похож на восходящий график, что
/// уместно для финансового продукта. Раньше «логотипом» была просто строка
/// текста, из-за чего у приложения не было узнаваемого знака вообще.
class WesiWordmark extends StatelessWidget {
  /// Высота знака. Текст масштабируется от неё.
  final double size;

  /// Показывать ли надпись рядом со знаком.
  final bool showText;

  final Color textColor;

  const WesiWordmark({
    super.key,
    this.size = 32,
    this.showText = true,
    this.textColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _WesiMarkPainter()),
    );

    if (!showText) return mark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: size * 0.34),
        Text(
          'WesiOS',
          style: TextStyle(
            fontSize: size * 0.78,
            fontWeight: FontWeight.w800,
            color: textColor,
            letterSpacing: size * 0.06,
          ),
        ),
      ],
    );
  }
}

/// Рисует знак векторно, а не картинкой: он остаётся чётким на любом
/// размере и автоматически совпадает с иконкой приложения по геометрии.
class _WesiMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final w = s * 0.155;

    // Те же пропорции, что у app_icon.png.
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

    final white = Paint()
      ..color = Colors.white
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final accent = Paint()
      ..color = AppTheme.accentOrange
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
      white,
    );
    canvas.drawLine(p3, p4, accent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
