import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Подсказка при наведении.
/// Overlay с IgnorePointer — не перехватывает курсор → нет мерцания на границе.
class WesiTooltip extends StatefulWidget {
  final String message;
  final Widget child;
  final Duration showDelay;

  const WesiTooltip({
    super.key,
    required this.message,
    required this.child,
    this.showDelay = const Duration(milliseconds: 350),
  });

  @override
  State<WesiTooltip> createState() => _WesiTooltipState();
}

class _WesiTooltipState extends State<WesiTooltip> {
  OverlayEntry? _overlayEntry;
  bool _pending = false;

  void _show() {
    if (_overlayEntry != null || !mounted) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;

    // Справа от элемента, чуть ниже верха — не перекрывает hit-зону child
    final left = offset.dx + size.width + 10;
    final top = offset.dy + (size.height / 2) - 18;

    _overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        left: left.clamp(8.0, MediaQuery.sizeOf(context).width - 220),
        top: top.clamp(8.0, MediaQuery.sizeOf(context).height - 60),
        child: IgnorePointer(
          // критично: overlay не участвует в hit-test → нет enter/exit цикла
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 220),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.carbonDark.withOpacity(0.96),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.accentOrange.withOpacity(0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Text(
                widget.message,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hide() {
    _pending = false;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onEnter() {
    _pending = true;
    Future.delayed(widget.showDelay, () {
      if (_pending && mounted) _show();
    });
  }

  void _onExit() => _hide();

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _onEnter(),
      onExit: (_) => _onExit(),
      child: widget.child,
    );
  }
}
