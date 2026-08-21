import 'package:flutter/material.dart';

import '../design/gateway_theme.dart';

class WesiAeroWordmark extends StatelessWidget {
  const WesiAeroWordmark({
    super.key,
    this.compact = false,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: 'Wesi Aero',
      image: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 31,
            height: 31,
            child: CustomPaint(
              painter: _WesiMarkPainter(
                stroke: palette.textPrimary,
                accent: palette.accent,
              ),
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: GatewayTokens.space8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'AERO',
                    style: TextStyle(color: palette.textPrimary),
                  ),
                ],
              ),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WesiMarkPainter extends CustomPainter {
  const _WesiMarkPainter({required this.stroke, required this.accent});

  final Color stroke;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final whitePaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final accentPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final body = Path()
      ..moveTo(size.width * 0.08, size.height * 0.24)
      ..lineTo(size.width * 0.27, size.height * 0.78)
      ..lineTo(size.width * 0.48, size.height * 0.42)
      ..lineTo(size.width * 0.66, size.height * 0.78);
    canvas.drawPath(body, whitePaint);

    final finalStroke = Path()
      ..moveTo(size.width * 0.66, size.height * 0.78)
      ..lineTo(size.width * 0.88, size.height * 0.18);
    canvas.drawPath(finalStroke, accentPaint);
  }

  @override
  bool shouldRepaint(covariant _WesiMarkPainter oldDelegate) {
    return oldDelegate.stroke != stroke || oldDelegate.accent != accent;
  }
}
