import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../core/theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _ringController1;
  late AnimationController _ringController2;
  late AnimationController _ringController3;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  final List<String> _loadingTexts = [
    'Загружаем вселенную Wesi...',
    'Настраиваем квантовые процессоры...',
    'Пробуждаем AI-аналитика...',
    'Заряжаем батареи мотивации...',
    'Синхронизируем с облаком...',
    'Проверяем баланс вселенной...',
    'Подключаем нейронные связи...',
    'Калибруем финансовый щит...',
    'Запускаем генератор идей...',
    'Готово к сворачиванию гор!',
  ];

  int _currentTextIndex = 0;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );

    _ringController1 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _ringController2 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _ringController3 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _fadeAnimation = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: const Interval(0, 0.3, curve: Curves.easeOut)),
    );

    _scaleAnimation = Tween(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: const Interval(0, 0.5, curve: Curves.easeOutCubic)),
    );

    _glowAnimation = Tween(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: const Interval(0.2, 0.8, curve: Curves.easeInOut)),
    );

    _fadeController.forward();
    _startTextRotation();

    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/welcome');
      }
    });
  }

  void _startTextRotation() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted && _currentTextIndex < _loadingTexts.length - 1) {
        setState(() => _currentTextIndex++);
        return true;
      }
      return false;
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _ringController1.dispose();
    _ringController2.dispose();
    _ringController3.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // Orange ambient glow background
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.3, -0.3),
                    radius: 0.8,
                    colors: [
                      AppTheme.accentOrange.withOpacity(0.15 * _glowAnimation.value),
                      AppTheme.accentOrange.withOpacity(0.05 * _glowAnimation.value),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              );
            },
          ),
          // Secondary glow
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.5, 0.5),
                    radius: 0.6,
                    colors: [
                      AppTheme.accentOrange.withOpacity(0.08 * _glowAnimation.value),
                      Colors.transparent,
                    ],
                  ),
                ),
              );
            },
          ),
          // Main content
          Center(
            child: AnimatedBuilder(
              animation: _fadeController,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Animated rings
                        SizedBox(
                          width: 180,
                          height: 180,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Outer ring - separate, rotating around own axis
                              RotationTransition(
                                turns: _ringController1,
                                child: CustomPaint(
                                  size: const Size(180, 180),
                                  painter: RingPainter(
                                    radius: 85,
                                    strokeWidth: 3,
                                    color: AppTheme.accentOrange,
                                    segments: 3,
                                    gapAngle: 0.4,
                                  ),
                                ),
                              ),
                              // Middle ring - separate, rotating opposite
                              RotationTransition(
                                turns: ReverseAnimation(_ringController2),
                                child: CustomPaint(
                                  size: const Size(180, 180),
                                  painter: RingPainter(
                                    radius: 65,
                                    strokeWidth: 2.5,
                                    color: AppTheme.accentOrange,
                                    segments: 4,
                                    gapAngle: 0.3,
                                  ),
                                ),
                              ),
                              // Inner ring - separate, rotating faster
                              RotationTransition(
                                turns: _ringController3,
                                child: CustomPaint(
                                  size: const Size(180, 180),
                                  painter: RingPainter(
                                    radius: 45,
                                    strokeWidth: 2,
                                    color: AppTheme.accentOrange,
                                    segments: 2,
                                    gapAngle: 0.5,
                                  ),
                                ),
                              ),
                              // Center logo
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      AppTheme.carbonDark,
                                      AppTheme.carbonMid,
                                    ],
                                  ),
                                  border: Border.all(
                                    color: AppTheme.accentOrange,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.accentOrange.withOpacity(0.3),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: Text(
                                    'W',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 48),
                        // WesiOS text
                        const Text(
                          'WesiOS',
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Business Operating System',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 64),
                        // Loading text
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          child: Text(
                            _loadingTexts[_currentTextIndex],
                            key: ValueKey<int>(_currentTextIndex),
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.textMuted,
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Progress bar
                        SizedBox(
                          width: 200,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _fadeController.value,
                              backgroundColor: AppTheme.surfaceLight,
                              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentOrange),
                              minHeight: 3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'v0.1.2 α',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for segmented rings with gaps
class RingPainter extends CustomPainter {
  final double radius;
  final double strokeWidth;
  final Color color;
  final int segments;
  final double gapAngle;

  RingPainter({
    required this.radius,
    required this.strokeWidth,
    required this.color,
    required this.segments,
    required this.gapAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final totalGap = gapAngle * segments;
    final segmentAngle = (2 * math.pi - totalGap) / segments;

    for (int i = 0; i < segments; i++) {
      final startAngle = i * (segmentAngle + gapAngle) - math.pi / 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        segmentAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
