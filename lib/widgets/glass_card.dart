import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final double? width;
  final double? height;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, mode, _) {
        final isDark = mode == AppThemeMode.dark;
        Widget card = Container(
          width: width,
          height: height,
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.glassBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.glassBorder, width: 1),
            boxShadow: [
              BoxShadow(
                color: (isDark ? Colors.black : const Color(0xFF64748B))
                    .withOpacity(isDark ? 0.2 : 0.1),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        );

        if (onTap != null) {
          card = GestureDetector(onTap: onTap, child: card);
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: card,
          ),
        );
      },
    );
  }
}
