import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/audio_vault_models.dart';
import '../services/audio_player_service.dart';

class AudioVisualizer extends StatefulWidget {
  final VisualizerMode mode;
  final double height;
  const AudioVisualizer({super.key, required this.mode, this.height = 300});

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: ValueListenableBuilder<AudioSpectrumFrame>(
          valueListenable: AudioPlayerService.spectrum,
          builder: (context, frame, _) => AnimatedBuilder(
            animation: _clock,
            builder: (_, __) => CustomPaint(
              painter: _VisualizerPainter(
                frame: frame,
                mode: widget.mode,
                time: _clock.value * math.pi * 40,
                accent: AppTheme.accent,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  final AudioSpectrumFrame frame;
  final VisualizerMode mode;
  final double time;
  final Color accent;

  const _VisualizerPainter({
    required this.frame,
    required this.mode,
    required this.time,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF080B12),
          Color.lerp(const Color(0xFF0A1220), accent, .10)!,
          const Color(0xFF05070B),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, bg);
    switch (mode) {
      case VisualizerMode.water:
        _water(canvas, size);
      case VisualizerMode.membrane:
        _membrane(canvas, size);
      case VisualizerMode.spectrum:
        _spectrum(canvas, size);
      case VisualizerMode.particles:
        _particles(canvas, size);
      case VisualizerMode.tunnel:
        _tunnel(canvas, size);
      case VisualizerMode.aurora:
        _aurora(canvas, size);
      case VisualizerMode.orbit:
        _orbit(canvas, size);
      case VisualizerMode.pulseGrid:
        _grid(canvas, size);
    }
  }

  void _water(Canvas canvas, Size s) {
    final basin = Rect.fromCenter(
      center: Offset(s.width / 2, s.height * .58),
      width: s.width * .88,
      height: s.height * .62,
    );
    canvas.drawOval(
      basin,
      Paint()
        ..color = const Color(0xFF0B111A)
        ..style = PaintingStyle.fill,
    );
    canvas.drawOval(
      basin,
      Paint()
        ..color = Colors.white.withOpacity(.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final surfaceCenter = Offset(s.width / 2, s.height * .56);
    final radiusX = s.width * .405;
    final radiusY = s.height * .19;
    final path = Path();
    const points = 150;
    for (var i = 0; i <= points; i++) {
      final a = i / points * math.pi * 2;
      final bassWave = math.sin(a * 3 + time * 1.7) * radiusY * .28 * frame.bass;
      final midWave = math.sin(a * 8 - time * 2.5) * radiusY * .10 * frame.mid;
      final highRipple = math.sin(a * 21 + time * 4.2) * radiusY * .045 * frame.high;
      final kickShock = math.sin(a * 2 - time * 6) * radiusY * .22 * frame.kick;
      final ripple = bassWave + midWave + highRipple + kickShock;
      final x = surfaceCenter.dx + math.cos(a) * radiusX;
      final y = surfaceCenter.dy + math.sin(a) * (radiusY + ripple);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    final water = Paint()
      ..shader = RadialGradient(
        center: Alignment(-.2, -.35),
        radius: 1.1,
        colors: [
          Colors.white.withOpacity(.25 + frame.high * .18),
          accent.withOpacity(.36 + frame.bass * .2),
          const Color(0xFF03121D).withOpacity(.9),
        ],
      ).createShader(basin);
    canvas.drawPath(path, water);

    final rings = 4 + (frame.bass * 5).round();
    for (var i = 0; i < rings; i++) {
      final phase = ((time * .35 + i / rings) % 1.0);
      final scale = .08 + phase * .78;
      canvas.drawOval(
        Rect.fromCenter(
          center: surfaceCenter,
          width: radiusX * 2 * scale,
          height: radiusY * 2 * scale,
        ),
        Paint()
          ..color = Colors.white.withOpacity((1 - phase) * (.05 + frame.bass * .18))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 + frame.bass * 2,
      );
    }

    final dropletCount = (frame.kick * 38 + frame.bass * 5).round();
    final rnd = math.Random((time * 30).floor());
    for (var i = 0; i < dropletCount; i++) {
      final spread = (rnd.nextDouble() - .5) * s.width * (.15 + frame.kick * .72);
      final h = rnd.nextDouble() * s.height * (.08 + frame.kick * .48);
      final x = surfaceCenter.dx + spread;
      final y = surfaceCenter.dy - h;
      final r = 1.2 + rnd.nextDouble() * (1.5 + frame.kick * 4.5);
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = Colors.white.withOpacity(.25 + frame.kick * .55),
      );
    }

    final speakerR = s.width < s.height ? s.width * .12 : s.height * .12;
    canvas.drawCircle(surfaceCenter, speakerR * (1 + frame.bass * .18),
        Paint()..color = Colors.black.withOpacity(.36));
    canvas.drawCircle(
      surfaceCenter,
      speakerR * (.58 + frame.bass * .25),
      Paint()..color = accent.withOpacity(.10 + frame.bass * .25),
    );
  }

  void _membrane(Canvas c, Size s) {
    final center = Offset(s.width / 2, s.height / 2);
    for (var ring = 12; ring >= 1; ring--) {
      final r = math.min(s.width, s.height) * ring / 26;
      final wobble = 1 + frame.bass * .15 * math.sin(time * 2 + ring);
      c.drawCircle(
        center,
        r * wobble,
        Paint()
          ..color = Color.lerp(accent, Colors.white, ring / 16)!
              .withOpacity(.035 + frame.mid * .035)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 + frame.bass * 1.8,
      );
    }
    c.drawCircle(center, 12 + frame.kick * 42,
        Paint()..color = accent.withOpacity(.35));
  }

  void _spectrum(Canvas c, Size s) {
    if (frame.fft.isEmpty) return;
    const bars = 64;
    final w = s.width / bars;
    for (var i = 0; i < bars; i++) {
      final start = i * 4;
      double v = 0;
      for (var j = start; j < start + 4 && j < frame.fft.length; j++) {
        v += frame.fft[j].abs();
      }
      v = (v / 4 * 5).clamp(0, 1);
      final h = 5 + v * s.height * .82;
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * w + 1, s.height - h, w - 2, h),
          const Radius.circular(3),
        ),
        Paint()..color = Color.lerp(accent, Colors.white, i / bars)!.withOpacity(.75),
      );
    }
  }

  void _particles(Canvas c, Size s) {
    final rnd = math.Random(42);
    for (var i = 0; i < 110; i++) {
      final baseX = rnd.nextDouble() * s.width;
      final baseY = rnd.nextDouble() * s.height;
      final speed = .15 + rnd.nextDouble() * 1.8;
      final x = (baseX + time * speed * (8 + frame.high * 30)) % s.width;
      final y = baseY + math.sin(time * speed + i) * (4 + frame.mid * 28);
      final r = .8 + rnd.nextDouble() * 2.2 + frame.bass * 2.5;
      c.drawCircle(Offset(x, y), r,
          Paint()..color = accent.withOpacity(.18 + rnd.nextDouble() * .55));
    }
  }

  void _tunnel(Canvas c, Size s) {
    final center = Offset(s.width / 2, s.height / 2);
    for (var i = 0; i < 18; i++) {
      final phase = ((i / 18 + time * .035) % 1.0);
      final r = phase * math.max(s.width, s.height) * .72;
      final sides = 6 + (frame.high * 5).round();
      final p = Path();
      for (var k = 0; k <= sides; k++) {
        final a = k / sides * math.pi * 2 + time * .08;
        final rr = r * (1 + frame.bass * .08 * math.sin(k * 2 + time));
        final pt = center + Offset(math.cos(a) * rr, math.sin(a) * rr);
        k == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
      }
      c.drawPath(
        p,
        Paint()
          ..color = accent.withOpacity((1 - phase) * .42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 + frame.kick * 3,
      );
    }
  }

  void _aurora(Canvas c, Size s) {
    for (var layer = 0; layer < 7; layer++) {
      final p = Path()..moveTo(0, s.height * (.15 + layer * .1));
      for (var x = 0.0; x <= s.width; x += 6) {
        final nx = x / s.width;
        final y = s.height * (.18 + layer * .095) +
            math.sin(nx * math.pi * (2 + layer * .4) + time * (.4 + layer * .03)) *
                (12 + frame.mid * 50) +
            math.sin(nx * math.pi * 9 - time * 1.4) * frame.high * 12;
        p.lineTo(x, y);
      }
      c.drawPath(
        p,
        Paint()
          ..color = Color.lerp(accent, Colors.cyanAccent, layer / 7)!
              .withOpacity(.18 + frame.bass * .12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 + frame.bass * 5,
      );
    }
  }

  void _orbit(Canvas c, Size s) {
    final center = Offset(s.width / 2, s.height / 2);
    for (var ring = 0; ring < 9; ring++) {
      final r = math.min(s.width, s.height) * (.08 + ring * .043) * (1 + frame.bass * .15);
      c.drawCircle(center, r,
          Paint()..color = accent.withOpacity(.04 + ring * .018)..style = PaintingStyle.stroke);
      final a = time * (.2 + ring * .055) + ring;
      final pt = center + Offset(math.cos(a) * r, math.sin(a) * r * .55);
      c.drawCircle(pt, 2.5 + frame.high * 5,
          Paint()..color = Color.lerp(accent, Colors.white, ring / 10)!.withOpacity(.85));
    }
    c.drawCircle(center, 14 + frame.kick * 35,
        Paint()..color = accent.withOpacity(.2 + frame.bass * .3));
  }

  void _grid(Canvas c, Size s) {
    const cols = 24;
    const rows = 12;
    final cw = s.width / cols;
    final ch = s.height / rows;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final d = math.sqrt(math.pow(x - cols / 2, 2) + math.pow(y - rows / 2, 2));
        final pulse = (math.sin(d * .85 - time * 2.5) + 1) / 2;
        final audio = frame.bass * (1 - (d / 18).clamp(0, 1)) + frame.high * .25;
        final size = 2 + (pulse * audio) * math.min(cw, ch) * .75;
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset((x + .5) * cw, (y + .5) * ch),
              width: size,
              height: size,
            ),
            const Radius.circular(2),
          ),
          Paint()..color = accent.withOpacity(.12 + pulse * audio * .7),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _VisualizerPainter oldDelegate) => true;
}
