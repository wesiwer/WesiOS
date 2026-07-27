import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class HoverButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final Color? hoverColor;
  final double? hoverScale;

  const HoverButton({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.borderRadius,
    this.backgroundColor,
    this.hoverColor,
    this.hoverScale,
  });

  @override
  State<HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<HoverButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: widget.padding ?? const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isHovered
                ? (widget.hoverColor ?? AppTheme.surfaceLight)
                : (widget.backgroundColor ?? AppTheme.surface),
            borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered ? AppTheme.accentOrange.withOpacity(0.5) : AppTheme.glassBorder,
              width: _isHovered ? 1.5 : 1,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: AppTheme.accentOrange.withOpacity(0.1),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: AnimatedScale(
            scale: _isHovered ? (widget.hoverScale ?? 1.05) : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class HoverIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color;

  const HoverIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 24,
    this.color,
  });

  @override
  State<HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<HoverIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _isHovered ? AppTheme.surfaceLight : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isHovered ? AppTheme.accentOrange.withOpacity(0.4) : Colors.transparent,
              width: 1,
            ),
          ),
          child: AnimatedScale(
            scale: _isHovered ? 1.15 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: Icon(
              widget.icon,
              size: widget.size,
              color: widget.color ?? AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
