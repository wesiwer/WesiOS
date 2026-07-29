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

  /// Знак слева от надписи. По умолчанию false — надпись идёт первой, знак
  /// замыкает; так строка читается слева направо как «WesiOS ▶», а сам знак
  /// не спорит за внимание с текстом на старте строки.
  final bool markFirst;

  const WesiWordmark({
    super.key,
    this.size = 32,
    this.showText = true,
    this.textColor = Colors.white,
    this.markFirst = false,
  });

  /// Стиль надписи — вынесен, чтобы заголовки экранов могли использовать
  /// ровно тот же шрифт и трекинг, что и логотип (см. [WesiTitle]).
  static TextStyle textStyle(double size, [Color color = Colors.white]) =>
      TextStyle(
        fontSize: size * 0.78,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: size * 0.06,
      );

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _WesiMarkPainter()),
    );

    if (!showText) return mark;

    final text = Text('WesiOS', style: textStyle(size, textColor));
    final gap = SizedBox(width: size * 0.34);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: markFirst ? [mark, gap, text] : [text, gap, mark],
    );
  }
}

/// Заголовок экрана в фирменном стиле.
///
/// Раньше каждая вкладка задавала свой размер и насыщенность, и названия
/// разъезжались между экранами. Здесь один стиль на всё приложение — тот же,
/// что у надписи в логотипе.
class WesiTitle extends StatelessWidget {
  final String text;
  final double size;
  final Color color;

  const WesiTitle(
    this.text, {
    super.key,
    this.size = 26,
    this.color = AppTheme.textPrimary,
  });

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: WesiWordmark.textStyle(size, color),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
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
