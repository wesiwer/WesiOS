import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/gateway_theme.dart';

class AmbientBackground extends StatefulWidget {
  const AmbientBackground({
    required this.child,
    super.key,
    this.reducedMotion = false,
  });

  final Widget child;
  final bool reducedMotion;

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    if (!widget.reducedMotion) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant AmbientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reducedMotion == widget.reducedMotion) return;
    if (widget.reducedMotion) {
      _controller.stop();
      _controller.value = 0.25;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ColoredBox(
      color: palette.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The grid is static while the theme is unchanged, so it can stay in
          // the raster cache independently from the moving glow layer.
          RepaintBoundary(
            child: CustomPaint(
              painter: _GridPainter(isDark: isDark),
              isComplex: true,
            ),
          ),
          // Drive animation directly through CustomPainter.repaint. This keeps
          // the exact same glow motion while avoiding a widget build/layout on
          // every display frame.
          RepaintBoundary(
            child: CustomPaint(
              painter: _GlowPainter(
                animation: _controller,
                accent: palette.accent,
                connected: palette.connected,
                isDark: isDark,
              ),
              isComplex: true,
              willChange: !widget.reducedMotion,
            ),
          ),
          RepaintBoundary(child: widget.child),
        ],
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({
    required this.animation,
    required this.accent,
    required this.connected,
    required this.isDark,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color accent;
  final Color connected;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final angle = animation.value * math.pi * 2;
    final accentCenter = Offset(
      size.width * (0.76 + math.sin(angle) * 0.08),
      size.height * (0.14 + math.cos(angle * 0.7) * 0.05),
    );
    final connectedCenter = Offset(
      size.width * (0.18 + math.cos(angle * 0.8) * 0.06),
      size.height * (0.78 + math.sin(angle * 0.55) * 0.05),
    );

    final accentPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: isDark ? 0.15 : 0.08),
          accent.withValues(alpha: 0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: accentCenter,
          radius: size.shortestSide * 0.62,
        ),
      );
    final connectedPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          connected.withValues(alpha: isDark ? 0.07 : 0.04),
          connected.withValues(alpha: 0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: connectedCenter,
          radius: size.shortestSide * 0.48,
        ),
      );

    canvas.drawRect(Offset.zero & size, accentPaint);
    canvas.drawRect(Offset.zero & size, connectedPaint);
  }

  @override
  bool shouldRepaint(covariant _GlowPainter oldDelegate) {
    return oldDelegate.animation != animation ||
        oldDelegate.accent != accent ||
        oldDelegate.connected != connected ||
        oldDelegate.isDark != isDark;
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : const Color(0xFF1E3A5F))
          .withValues(alpha: isDark ? 0.018 : 0.028)
      ..strokeWidth = 1;
    const grid = 48.0;
    for (var x = 0.0; x < size.width; x += grid) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += grid) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
