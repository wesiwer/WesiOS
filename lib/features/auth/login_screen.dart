import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_button.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ShaderMask(
              shaderCallback: (bounds) {
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withOpacity(0.9),
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
            HoverButton(
              onTap: () => Navigator.pushReplacementNamed(context, '/home'),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 48),
              backgroundColor: AppTheme.surface,
              hoverColor: AppTheme.surfaceLight,
              child: const Text(
                'Войти',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
