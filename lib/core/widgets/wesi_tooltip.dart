import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// WesiOS Tooltip — показывает подсказку при наведении.
/// 
/// Использование:
/// ```dart
/// WesiTooltip(
///   message: 'Система, которая меняет мир',
///   child: IconButton(...),
/// )
/// ```
class WesiTooltip extends StatefulWidget {
  final String message;
  final Widget child;
  final Duration showDelay;

  const WesiTooltip({
    super.key,
    required this.message,
    required this.child,
    this.showDelay = const Duration(milliseconds: 400),
  });

  @override
  State<WesiTooltip> createState() => _WesiTooltipState();
}

class _WesiTooltipState extends State<WesiTooltip> {
  bool _isVisible = false;
  OverlayEntry? _overlayEntry;

  void _showTooltip() {
    if (_overlayEntry != null) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx + size.width / 2 - 100,
        top: offset.dy - 45,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 200,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.carbonDark.withOpacity(0.95),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.accentOrange.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accentOrange.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Text(
              widget.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isVisible = true);
  }

  void _hideTooltip() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    setState(() => _isVisible = false);
  }

  @override
  void dispose() {
    _hideTooltip();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => Future.delayed(widget.showDelay, () {
        if (mounted) _showTooltip();
      }),
      onExit: (_) => _hideTooltip(),
      child: widget.child,
    );
  }
}
