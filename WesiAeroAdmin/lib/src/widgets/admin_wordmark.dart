import 'package:flutter/material.dart';

import '../design/admin_theme.dart';

class WesiAeroAdminWordmark extends StatelessWidget {
  const WesiAeroAdminWordmark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: 'Wesi Aero Admin',
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
            Text(
              'AERO',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
            ),
            const SizedBox(width: GatewayTokens.space8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: palette.connected.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: palette.connected.withValues(alpha: 0.28),
                ),
              ),
              child: Text(
                'ADMIN',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: palette.connected,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
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
    final main = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final highlight = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.08, size.height * 0.24)
        ..lineTo(size.width * 0.27, size.height * 0.78)
        ..lineTo(size.width * 0.48, size.height * 0.42)
        ..lineTo(size.width * 0.66, size.height * 0.78),
      main,
    );
    canvas.drawLine(
      Offset(size.width * 0.66, size.height * 0.78),
      Offset(size.width * 0.88, size.height * 0.18),
      highlight,
    );
  }

  @override
  bool shouldRepaint(covariant _WesiMarkPainter oldDelegate) =>
      oldDelegate.stroke != stroke || oldDelegate.accent != accent;
}
