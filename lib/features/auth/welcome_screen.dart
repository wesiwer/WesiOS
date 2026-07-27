import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_button.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _fadeAnimation = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.5, curve: Curves.easeOut)),
    );

    _scaleAnimation = Tween(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic)),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // Carbon background
          Container(
            decoration: const BoxDecoration(
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
          // Soft highlight
          Positioned(
            top: -50,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withOpacity(0.02),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Spacer(),
                  // Easter Egg Logo
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _fadeAnimation.value,
                        child: Transform.scale(
                          scale: _scaleAnimation.value,
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.carbonHighlight,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
                                  blurRadius: 40,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/wesi_logo_easter.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                  // WesiOS — carbon text
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _fadeAnimation.value,
                        child: ShaderMask(
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withOpacity(0.95),
                                Colors.white.withOpacity(0.5),
                                AppTheme.carbonHighlight.withOpacity(0.3),
                              ],
                            ).createShader(bounds);
                          },
                          child: const Text(
                            'WesiOS',
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 8,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Business Operating System',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                      letterSpacing: 3,
                    ),
                  ),
                  const Spacer(),
                  // Start button with hover
                  HoverButton(
                    onTap: () => Navigator.pushReplacementNamed(context, '/login'),
                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 48),
                    backgroundColor: AppTheme.surface,
                    hoverColor: AppTheme.surfaceLight,
                    child: const Text(
                      'Начать работу',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'v1.0',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
