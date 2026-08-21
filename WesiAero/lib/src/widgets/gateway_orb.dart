import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/gateway_theme.dart';
import '../models/gateway_models.dart';

class GatewayOrb extends StatefulWidget {
  const GatewayOrb({
    required this.status,
    required this.onPressed,
    super.key,
    this.size = 268,
    this.reducedMotion = false,
  });

  final TunnelStatus status;
  final VoidCallback? onPressed;
  final double size;
  final bool reducedMotion;

  @override
  State<GatewayOrb> createState() => _GatewayOrbState();
}

class _GatewayOrbState extends State<GatewayOrb>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  bool _hovered = false;
  bool _pressed = false;

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
      duration: const Duration(seconds: 5),
    );
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant GatewayOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reducedMotion == widget.reducedMotion) return;
    if (widget.reducedMotion) {
      _controller.stop();
      _controller.value = 0.18;
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
    final activeColor = switch (widget.status) {
      TunnelStatus.connected => palette.connected,
      TunnelStatus.error => palette.danger,
      TunnelStatus.disconnecting => palette.warning,
      _ => palette.accent,
    };
    final busy = widget.status == TunnelStatus.connecting ||
        widget.status == TunnelStatus.disconnecting;

    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      label: switch (widget.status) {
        TunnelStatus.connected => 'Отключить защищённое соединение',
        TunnelStatus.connecting => 'Подключение выполняется',
        TunnelStatus.disconnecting => 'Отключение выполняется',
        _ => 'Подключить защищённое соединение',
      },
      child: MouseRegion(
        cursor: widget.onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTapDown: widget.onPressed == null
              ? null
              : (_) => setState(() => _pressed = true),
          onTapCancel: widget.onPressed == null
              ? null
              : () => setState(() => _pressed = false),
          onTapUp: widget.onPressed == null
              ? null
              : (_) => setState(() => _pressed = false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _pressed
                ? 0.965
                : _hovered && !widget.reducedMotion
                    ? 1.025
                    : 1,
            duration: GatewayTokens.quick,
            curve: Curves.easeOutCubic,
            child: RepaintBoundary(
              child: SizedBox.square(
                dimension: widget.size,
                child: CustomPaint(
                  painter: _OrbPainter(
                    animation: _controller,
                    color: activeColor,
                    status: widget.status,
                    isDark: Theme.of(context).brightness == Brightness.dark,
                  ),
                  isComplex: true,
                  willChange: _shouldAnimate,
                  child: Center(
                    child: AnimatedContainer(
                      duration: GatewayTokens.expressive,
                      curve: Curves.easeOutCubic,
                      width: widget.size * 0.52,
                      height: widget.size * 0.52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.surface.withValues(alpha: 0.86),
                        border: Border.all(
                          color: activeColor.withValues(alpha: 0.38),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.15),
                            blurRadius: 36,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: AnimatedSwitcher(
                        duration: GatewayTokens.normal,
                        transitionBuilder: (child, animation) => ScaleTransition(
                          scale: CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutBack,
                          ),
                          child: FadeTransition(opacity: animation, child: child),
                        ),
                        child: busy
                            ? SizedBox.square(
                                key: const ValueKey('busy'),
                                dimension: widget.size * 0.16,
                                child: CircularProgressIndicator(
                                  color: activeColor,
                                  strokeWidth: 3,
                                  strokeCap: StrokeCap.round,
                                ),
                              )
                            : Icon(
                                Icons.power_settings_new_rounded,
                                key: ValueKey(widget.status),
                                size: widget.size * 0.21,
                                color: activeColor,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.animation,
    required this.color,
    required this.status,
    required this.isDark,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final TunnelStatus status;
  final bool isDark;

  Size? _cachedSize;
  Offset _center = Offset.zero;
  double _shortest = 0;
  double _outerRadius = 0;
  Rect _outerRect = Rect.zero;

  final Paint _auraPaint = Paint();
  final Paint _basePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _gradientPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _innerPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  final Paint _particlePaint = Paint();

  bool get _connected => status == TunnelStatus.connected;
  bool get _busy => status == TunnelStatus.connecting ||
      status == TunnelStatus.disconnecting;

  void _ensureResources(Size size) {
    if (_cachedSize == size) return;
    _cachedSize = size;
    _center = size.center(Offset.zero);
    _shortest = size.shortestSide;
    _outerRadius = _shortest * 0.44;
    _outerRect = Rect.fromCircle(center: _center, radius: _outerRadius);

    _auraPaint.maskFilter = MaskFilter.blur(
      BlurStyle.normal,
      _shortest * (_connected ? 0.095 : 0.065),
    );
    _basePaint
      ..strokeWidth = _shortest * 0.018
      ..color = color.withValues(alpha: 0.16);
    _gradientPaint
      ..strokeWidth = _shortest * 0.022
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.14),
          color,
          color.withValues(alpha: 0.55),
          color.withValues(alpha: 0.14),
        ],
        stops: const [0, 0.36, 0.66, 1],
      ).createShader(_outerRect);
    _innerPaint.color =
        Colors.white.withValues(alpha: isDark ? 0.12 : 0.16);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _ensureResources(size);

    final phase = animation.value;
    final rotation = phase * math.pi * 2;
    final pulse =
        (math.sin(rotation * (_connected ? 1 : 1.6)) + 1) / 2;

    _auraPaint.color = color.withValues(
      alpha: (_connected ? 0.10 : 0.055) + pulse * 0.055,
    );
    canvas.drawCircle(
      _center,
      _outerRadius * (0.94 + pulse * 0.035),
      _auraPaint,
    );

    canvas.drawCircle(_center, _outerRadius, _basePaint);

    final arcRotation = rotation * (_busy ? 1 : 0.12);
    final arcSweep = _busy ? math.pi * 1.24 : math.pi * 1.72;
    canvas.save();
    canvas.translate(_center.dx, _center.dy);
    canvas.rotate(rotation);
    canvas.translate(-_center.dx, -_center.dy);
    canvas.drawArc(
      _outerRect,
      -math.pi / 2 + arcRotation - rotation,
      arcSweep,
      false,
      _gradientPaint,
    );
    canvas.restore();

    canvas.drawCircle(_center, _outerRadius * 0.78, _innerPaint);

    for (var index = 0; index < 8; index += 1) {
      final particleAngle = rotation * (_connected ? 0.22 : 0.48) +
          index * math.pi * 2 / 8;
      final radius =
          _outerRadius * (1.10 + (index.isEven ? 0.025 : 0));
      final point = _center +
          Offset(math.cos(particleAngle), math.sin(particleAngle)) * radius;
      _particlePaint.color =
          color.withValues(alpha: 0.18 + (index % 3) * 0.08);
      canvas.drawCircle(
        point,
        index.isEven ? 1.8 : 1.2,
        _particlePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) {
    return oldDelegate.animation != animation ||
        oldDelegate.color != color ||
        oldDelegate.status != status ||
        oldDelegate.isDark != isDark;
  }
}
