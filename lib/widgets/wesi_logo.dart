import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class WesiLogo extends StatelessWidget {
  final double size;
  final VoidCallback? onTap;

  const WesiLogo({super.key, this.size = 40, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, mode, _) {
        final isDark = mode == AppThemeMode.dark;
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
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          AppTheme.carbonDark,
                          AppTheme.carbonMid,
                          AppTheme.carbonLight,
                        ]
                      : [
                          const Color(0xFFE8EEF8),
                          const Color(0xFFD6E2F5),
                          const Color(0xFFC5D4ED),
                        ],
                ),
                border: Border.all(
                  color: isDark
                      ? AppTheme.carbonHighlight
                      : AppTheme.lightAccentBlue.withOpacity(0.35),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isDark ? Colors.black : const Color(0xFF64748B))
                        .withOpacity(isDark ? 0.4 : 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                  if (isDark)
                    BoxShadow(
                      color: Colors.white.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(-1, -1),
                    ),
                ],
              ),
              child: Center(
                child: Text(
                  'W',
                  style: TextStyle(
                    fontSize: size * 0.45,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF1E3A5F),
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showFounderStory(BuildContext context) {
    Navigator.pushNamed(context, '/founder');
  }
}
