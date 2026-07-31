import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../core/constants/app_version.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_wordmark.dart';

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
      CurvedAnimation(
          parent: _fadeController,
          curve: const Interval(0, 0.3, curve: Curves.easeOut)),
    );

    _scaleAnimation = Tween(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
          parent: _fadeController,
          curve: const Interval(0, 0.5, curve: Curves.easeOutCubic)),
    );

    _glowAnimation = Tween(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
          parent: _fadeController,
          curve: const Interval(0.1, 0.9, curve: Curves.easeInOut)),
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
          // Яркий оранжевый ambient glow
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.1,
                    colors: [
                      AppTheme.accentOrange
                          .withOpacity(0.45 * _glowAnimation.value),
                      AppTheme.accentOrange
                          .withOpacity(0.18 * _glowAnimation.value),
                      AppTheme.accentOrange
                          .withOpacity(0.05 * _glowAnimation.value),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.35, 0.65, 1.0],
                  ),
                ),
              );
            },
          ),
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
                        const WesiWordmark(size: 46),
                        const SizedBox(height: 8),
                        Text(
                          'Business Operating System',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 48),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          child: Text(
                            _loadingTexts[_currentTextIndex],
                            key: ValueKey<int>(_currentTextIndex),
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.textMuted,
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Progress bar
                        SizedBox(
                          width: 220,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _fadeController.value,
                              backgroundColor: AppTheme.surfaceLight,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppTheme.accentOrange),
                              minHeight: 3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        // Кольца НИЖЕ шкалы: толще, меньше, без центральной W
                        SizedBox(
                          width: 110,
                          height: 110,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              RotationTransition(
                                turns: _ringController1,
                                child: CustomPaint(
                                  size: const Size(110, 110),
                                  painter: RingPainter(
                                    radius: 48,
                                    strokeWidth: 5,
                                    color: AppTheme.accentOrange,
                                    segments: 3,
                                    gapAngle: 0.35,
                                  ),
                                ),
                              ),
                              RotationTransition(
                                turns: ReverseAnimation(_ringController2),
                                child: CustomPaint(
                                  size: const Size(110, 110),
                                  painter: RingPainter(
                                    radius: 34,
                                    strokeWidth: 4.5,
                                    color: AppTheme.accentOrange.withOpacity(0.85),
                                    segments: 4,
                                    gapAngle: 0.28,
                                  ),
                                ),
                              ),
                              RotationTransition(
                                turns: _ringController3,
                                child: CustomPaint(
                                  size: const Size(110, 110),
                                  painter: RingPainter(
                                    radius: 20,
                                    strokeWidth: 4,
                                    color: AppTheme.accentOrange.withOpacity(0.7),
                                    segments: 2,
                                    gapAngle: 0.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          AppVersion.display,
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
