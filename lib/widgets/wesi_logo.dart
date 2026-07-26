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
        onHover: (_) => _showHoverTooltip(context),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppTheme.accentOrange.withOpacity(0.5),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentOrange.withOpacity(0.2),
                blurRadius: size * 0.4,
              ),
            ],
          ),
          child: Center(
            child: Text(
              'W',
              style: TextStyle(
                fontSize: size * 0.5,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showHoverTooltip(BuildContext context) {
    // Tooltip will be shown via Tooltip widget or custom overlay
  }

  void _showFounderStory(BuildContext context) {
    Navigator.pushNamed(context, '/founder');
  }
}
