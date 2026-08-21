import 'dart:math' as math;
import 'dart:ui' as ui;

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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  bool get _shouldAnimate =>
      !widget.reducedMotion && _lifecycleState == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant AmbientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reducedMotion == widget.reducedMotion) return;
    if (widget.reducedMotion) {
      _controller.stop();
      _controller.value = 0.25;
    } else {
      _syncTicker();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _syncTicker();
  }

  void _syncTicker() {
    if (_shouldAnimate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      // Preserve the current visual phase while Wesi Aero is not visible.
      _controller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
          RepaintBoundary(
            child: CustomPaint(
              painter: _GridPainter(isDark: isDark),
              isComplex: true,
            ),
          ),
          RepaintBoundary(
            child: CustomPaint(
              painter: _GlowPainter(
                animation: _controller,
                accent: palette.accent,
                connected: palette.connected,
                isDark: isDark,
              ),
              isComplex: true,
              willChange: _shouldAnimate,
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

  Size? _shaderSize;
  ui.Shader? _accentShader;
  ui.Shader? _connectedShader;
  Offset _accentBase = Offset.zero;
  Offset _connectedBase = Offset.zero;
  double _accentRadius = 0;
  double _connectedRadius = 0;
  final Paint _accentPaint = Paint();
  final Paint _connectedPaint = Paint();

  void _ensureShaders(Size size) {
    if (_shaderSize == size &&
        _accentShader != null &&
        _connectedShader != null) {
      return;
    }

    _shaderSize = size;
    _accentBase = Offset(size.width * 0.76, size.height * 0.14);
    _connectedBase = Offset(size.width * 0.18, size.height * 0.78);
    _accentRadius = size.shortestSide * 0.62;
    _connectedRadius = size.shortestSide * 0.48;

    _accentShader = ui.Gradient.radial(
      _accentBase,
      _accentRadius,
      [
        accent.withValues(alpha: isDark ? 0.15 : 0.08),
        accent.withValues(alpha: 0),
      ],
      const [0, 1],
    );
    _connectedShader = ui.Gradient.radial(
      _connectedBase,
      _connectedRadius,
      [
        connected.withValues(alpha: isDark ? 0.07 : 0.04),
        connected.withValues(alpha: 0),
      ],
      const [0, 1],
    );
    _accentPaint.shader = _accentShader;
    _connectedPaint.shader = _connectedShader;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _ensureShaders(size);

    final angle = animation.value * math.pi * 2;
    final accentOffset = Offset(
      size.width * math.sin(angle) * 0.08,
      size.height * math.cos(angle * 0.7) * 0.05,
    );
    final connectedOffset = Offset(
      size.width * math.cos(angle * 0.8) * 0.06,
      size.height * math.sin(angle * 0.55) * 0.05,
    );

    canvas.save();
    canvas.translate(accentOffset.dx, accentOffset.dy);
    canvas.drawCircle(_accentBase, _accentRadius, _accentPaint);
    canvas.restore();

    canvas.save();
    canvas.translate(connectedOffset.dx, connectedOffset.dy);
    canvas.drawCircle(_connectedBase, _connectedRadius, _connectedPaint);
    canvas.restore();
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
