import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class HoverButton extends StatefulWidget {
  final Widget child;
  final FutureOr<void> Function()? onTap;
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
  bool _isFocused = false;

  bool get _active => _isHovered || _isFocused;

  void _activate() => widget.onTap?.call();

  @override
  Widget build(BuildContext context) {
    // FocusableActionDetector — кнопка попадает в обход фокуса,
    // поэтому по ней можно ходить стрелками и жать Enter/Space.
    return FocusableActionDetector(
      enabled: widget.onTap != null,
      mouseCursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onShowHoverHighlight: (v) => setState(() => _isHovered = v),
      onShowFocusHighlight: (v) => setState(() => _isFocused = v),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: widget.padding ?? const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _active
                ? (widget.hoverColor ?? AppTheme.surfaceLight)
                : (widget.backgroundColor ?? AppTheme.surface),
            borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
            border: Border.all(
              // Фокус — заметнее наведения, чтобы было видно, где ты стрелками
              color: _isFocused
                  ? AppTheme.accentOrange
                  : _isHovered
                      ? AppTheme.accentOrange.withOpacity(0.5)
                      : AppTheme.glassBorder,
              width: _isFocused ? 2 : (_isHovered ? 1.5 : 1),
            ),
            boxShadow: _active
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
            scale: _active ? (widget.hoverScale ?? 1.05) : 1.0,
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
  final FutureOr<void> Function()? onTap;
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
  bool _isFocused = false;

  bool get _active => _isHovered || _isFocused;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      enabled: widget.onTap != null,
      mouseCursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onShowHoverHighlight: (v) => setState(() => _isHovered = v),
      onShowFocusHighlight: (v) => setState(() => _isFocused = v),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _active ? AppTheme.surfaceLight : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isFocused
                  ? AppTheme.accentOrange
                  : _isHovered
                      ? AppTheme.accentOrange.withOpacity(0.4)
                      : Colors.transparent,
              width: _isFocused ? 2 : 1,
            ),
          ),
          child: AnimatedScale(
            scale: _active ? 1.15 : 1.0,
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
