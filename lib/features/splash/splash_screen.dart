import 'package:flutter/material.dart';
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
      duration: const Duration(seconds: 5),
    );

    _ringController1 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _ringController2 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);

    _ringController3 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
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

    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/welcome');
      }
    });
  }

  void _startTextRotation() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 500));
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
          // Carbon fiber background with orange glow
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.carbonDark,
                  AppTheme.background,
                  AppTheme.carbonMid,
                ],
              ),
            ),
          ),
          // Orange ambient glow — bottom right
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Positioned(
                bottom: -100,
                right: -100,
                child: Container(
                  width: 400,
                  height: 400,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppTheme.accentOrange.withOpacity(0.08 * _glowAnimation.value),
                        AppTheme.accentOrange.withOpacity(0.02 * _glowAnimation.value),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              );
            },
          ),
          // Orange ambient glow — top left subtle
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Positioned(
                top: -80,
                left: -80,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppTheme.accentOrange.withOpacity(0.05 * _glowAnimation.value),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          // Soft white highlight
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withOpacity(0.03),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
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
                        // Animated rings + Logo
                        SizedBox(
                          width: 160,
                          height: 160,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Outer ring — rotates clockwise
                              RotationTransition(
                                turns: _ringController1,
                                child: Container(
                                  width: 160,
                                  height: 160,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppTheme.accentOrange.withOpacity(0.3),
                                      width: 1.5,
                                    ),
                                    gradient: SweepGradient(
                                      colors: [
                                        Colors.transparent,
                                        AppTheme.accentOrange.withOpacity(0.4),
                                        Colors.transparent,
                                      ],
                                      stops: const [0.0, 0.5, 1.0],
                                    ),
                                  ),
                                ),
                              ),
                              // Middle ring — rotates counter-clockwise
                              RotationTransition(
                                turns: ReverseAnimation(_ringController2),
                                child: Container(
                                  width: 130,
                                  height: 130,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppTheme.accentOrange.withOpacity(0.25),
                                      width: 1.2,
                                    ),
                                    gradient: SweepGradient(
                                      colors: [
                                        Colors.transparent,
                                        AppTheme.accentOrange.withOpacity(0.3),
                                        Colors.transparent,
                                      ],
                                      stops: const [0.0, 0.5, 1.0],
                                    ),
                                  ),
                                ),
                              ),
                              // Inner ring — rotates clockwise faster
                              RotationTransition(
                                turns: _ringController3,
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppTheme.accentOrange.withOpacity(0.2),
                                      width: 1,
                                    ),
                                  ),
                                ),
                              ),
                              // Carbon logo center
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      AppTheme.carbonDark,
                                      AppTheme.carbonMid,
                                      AppTheme.carbonLight,
                                    ],
                                  ),
                                  border: Border.all(
                                    color: AppTheme.accentOrange.withOpacity(0.4),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.accentOrange.withOpacity(0.15),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.5),
                                      blurRadius: 30,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: ShaderMask(
                                    shaderCallback: (bounds) {
                                      return LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Colors.white.withOpacity(0.95),
                                          AppTheme.accentOrange.withOpacity(0.8),
                                          Colors.white.withOpacity(0.6),
                                        ],
                                        stops: const [0.0, 0.5, 1.0],
                                      ).createShader(bounds);
                                    },
                                    child: const Text(
                                      'W',
                                      style: TextStyle(
                                        fontSize: 40,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),
                        // WesiOS text — carbon style with orange accent
                        ShaderMask(
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withOpacity(0.95),
                                Colors.white.withOpacity(0.7),
                                AppTheme.accentOrange.withOpacity(0.5),
                              ],
                            ).createShader(bounds);
                          },
                          child: const Text(
                            'WesiOS',
                            style: TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 6,
                            ),
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
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            _loadingTexts[_currentTextIndex],
                            key: ValueKey(_currentTextIndex),
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.textMuted,
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Progress
                        SizedBox(
                          width: 200,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _fadeController.value,
                              backgroundColor: AppTheme.surfaceLight,
                              valueColor: const AlwaysStoppedAnimation(AppTheme.accentOrange),
                              minHeight: 3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'v0.1 α',
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
