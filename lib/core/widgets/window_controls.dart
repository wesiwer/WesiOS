import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../theme/app_theme.dart';

class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> {
  bool _isMaximized = true;

  @override
  void initState() {
    super.initState();
    _checkMaximized();
  }

  Future<void> _checkMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _isMaximized = maximized);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        if (_isMaximized) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
        _checkMaximized();
      },
      child: Container(
        height: 40,
        color: Colors.transparent,
        child: Row(
          children: [
            const SizedBox(width: 16),
            // App title
            Text(
              'WesiOS',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            // Minimize
            _WindowButton(
              icon: Icons.remove,
              onTap: () => windowManager.minimize(),
            ),
            // Maximize / Restore
            _WindowButton(
              icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
              onTap: () async {
                if (_isMaximized) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
                _checkMaximized();
              },
            ),
            // Close
            _WindowButton(
              icon: Icons.close,
              onTap: () => windowManager.close(),
              isClose: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.onTap,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
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
          width: 48,
          height: 40,
          color: _isHovered
              ? (widget.isClose ? const Color(0xFFE81123) : Colors.white.withOpacity(0.1))
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: 16,
            color: _isHovered && widget.isClose ? Colors.white : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }
}
