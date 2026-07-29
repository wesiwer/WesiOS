import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../theme/app_theme.dart';

/// Высота title bar для отступов контента
const double kTitleBarHeight = 36;

/// Есть ли на этой платформе кастомный title bar с кнопками окна.
bool get kHasCustomTitleBar =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// Отступ сверху под кнопки окна.
///
/// [kTitleBarHeight] — константа времени компиляции, одинаковая на всех
/// платформах, поэтому прибавлять её напрямую нельзя: на телефоне никакого
/// title bar нет, и эти 36 px просто съедали экран поверх системного отступа
/// SafeArea. Использовать это вместо `kTitleBarHeight` везде, где отступ
/// нужен ради кнопок окна, а не ради выреза камеры.
double get kTitleBarInset => kHasCustomTitleBar ? kTitleBarHeight : 0;

/// Кастомный title bar без логотипа/надписи WesiOS.
/// Кнопки окна с мгновенным откликом (Listener, не GestureDetector).
class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> with WindowListener {
  // Текущее нативное состояние (для иконки кнопки).
  bool _isFullScreen = true;
  // Что выбрал пользователь — не путать с _isFullScreen: во время
  // _minimize() мы технически временно гасим fullscreen, чтобы обойти отказ
  // Win32 сворачивать fullscreen-окно, но пользователь fullscreen не отменял.
  // Именно это поле решает, возвращаться ли в fullscreen после восстановления
  // из трея.
  bool _wantFullScreen = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkFullScreen();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _isFullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _isFullScreen = false);
  }

  /// На Win32 плагин безусловно отказывается сворачивать fullscreen-окно
  /// (см. main.dart) — при восстановлении из трея нужно вернуть прежний вид
  /// самим, иначе после первого же сворачивания окно навсегда остаётся
  /// обычным, даже если пользователь фактически fullscreen не выключал.
  @override
  void onWindowRestore() {
    if (_wantFullScreen) windowManager.setFullScreen(true);
  }

  Future<void> _checkFullScreen() async {
    try {
      final fullScreen = await windowManager.isFullScreen();
      if (mounted) setState(() => _isFullScreen = fullScreen);
    } catch (_) {}
  }

  /// Сворачивание из fullscreen на Win32 — не встроенная функция плагина
  /// (см. main.dart): нужно сперва явно выйти из fullscreen, и только потом
  /// звать minimize(), иначе вызов молча ничего не делает. _wantFullScreen
  /// не трогаем — это чисто техническое отключение, а не выбор пользователя.
  Future<void> _minimize() async {
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
    }
    await windowManager.minimize();
  }

  Future<void> _toggleFullScreen() async {
    _wantFullScreen = !_wantFullScreen;
    await windowManager.setFullScreen(_wantFullScreen);
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
              // На Windows плагин сам глушит startDragging() в fullscreen —
              // перетаскивать всё равно нечего, пока не вышли в оконный режим.
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: _toggleFullScreen,
              child: const SizedBox.expand(),
            ),
          ),
          // Window buttons — вне drag-зоны, мгновенный отклик
          _WinBtn(
            icon: Icons.remove,
            tooltip: 'Свернуть',
            onTap: _minimize,
          ),
          _WinBtn(
            icon: _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
            tooltip: _isFullScreen
                ? 'Выйти из полноэкранного режима'
                : 'На весь экран',
            onTap: _toggleFullScreen,
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
