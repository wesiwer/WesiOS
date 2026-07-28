import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../theme/app_theme.dart';

/// Высота title bar для отступов контента
const double kTitleBarHeight = 36;

/// Кастомный title bar без логотипа/надписи WesiOS.
/// Кнопки окна с мгновенным откликом (Listener, не GestureDetector).
class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> with WindowListener {
  bool _isMaximized = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  Future<void> _checkMaximized() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted) setState(() => _isMaximized = maximized);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kTitleBarHeight,
      child: Row(
        children: [
          // Drag zone — вся левая часть, без лого
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () async {
                if (_isMaximized) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              child: const SizedBox.expand(),
            ),
          ),
          // Window buttons — вне drag-зоны, мгновенный отклик
          _WinBtn(
            icon: Icons.remove,
            tooltip: 'Свернуть',
            onTap: () => windowManager.minimize(),
          ),
          _WinBtn(
            icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
            tooltip: _isMaximized ? 'Восстановить' : 'Развернуть',
            onTap: () async {
              if (_isMaximized) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          _WinBtn(
            icon: Icons.close,
            tooltip: 'Закрыть',
            isClose: true,
            onTap: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}

class _WinBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isClose;
  final String tooltip;

  const _WinBtn({
    required this.icon,
    required this.onTap,
    this.isClose = false,
    this.tooltip = '',
  });

  @override
  State<_WinBtn> createState() => _WinBtnState();
}

class _WinBtnState extends State<_WinBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => widget.onTap(),
          child: Container(
            width: 46,
            height: kTitleBarHeight,
            color: _hovered
                ? (widget.isClose
                    ? const Color(0xFFE81123)
                    : Colors.white.withOpacity(0.12))
                : Colors.transparent,
            child: Icon(
              widget.icon,
              size: 14,
              color: _hovered && widget.isClose
                  ? Colors.white
                  : AppTheme.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
