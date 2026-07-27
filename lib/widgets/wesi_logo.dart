import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class WesiLogo extends StatelessWidget {
  final double size;
  final VoidCallback? onTap;

  const WesiLogo({super.key, this.size = 40, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onSecondaryTap: () => _showFounderStory(context),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: size,
          height: size,
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
              color: AppTheme.carbonHighlight,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(-1, -1),
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
                    Colors.white.withOpacity(0.7),
                    Colors.white.withOpacity(0.4),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ).createShader(bounds);
              },
              child: Text(
                'W',
                style: TextStyle(
                  fontSize: size * 0.45,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showFounderStory(BuildContext context) {
    Navigator.pushNamed(context, '/founder');
  }
}
