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
/// Кнопки окна с мгновенным откликом.
class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> with WindowListener {
  bool _isFullScreen = true;
  bool _isMaximized = false;
  /// Что выбрал пользователь — не путать с _isFullScreen: во время
  /// _minimize() мы технически временно гасим fullscreen, чтобы обойти отказ
  /// Win32 сворачивать fullscreen-окно, но пользователь fullscreen не отменял.
  bool _wantFullScreen = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncState();
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

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  /// На Win32 плагин безусловно отказывается сворачивать fullscreen-окно
  /// (см. main.dart) — при восстановлении из трея нужно вернуть прежний вид
  /// самим, иначе после первого же сворачивания окно навсегда остаётся
  /// обычным, даже если пользователь фактически fullscreen не выключал.
  @override
  void onWindowRestore() {
    if (_wantFullScreen) {
      windowManager.setFullScreen(true);
    }
  }

  Future<void> _syncState() async {
    try {
      final fullScreen = await windowManager.isFullScreen();
      final maximized = await windowManager.isMaximized();
      if (mounted) {
        setState(() {
          _isFullScreen = fullScreen;
          _isMaximized = maximized;
        });
      }
    } catch (_) {}
  }

  /// Сворачивание из fullscreen на Win32 — не встроенная функция плагина
  /// (см. main.dart): нужно сперва явно выйти из fullscreen, и только потом
  /// звать minimize(), иначе вызов молча ничего не делает. _wantFullScreen
  /// не трогаем — это чисто техническое отключение, а не выбор пользователя.
  Future<void> _minimize() async {
    try {
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
        // Даём Win32 обработать выход из fullscreen перед minimize.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await windowManager.minimize();
    } catch (e) {
      debugPrint('WindowControls.minimize failed: $e');
    }
  }

  Future<void> _toggleFullScreen() async {
    try {
      _wantFullScreen = !_wantFullScreen;
      if (_wantFullScreen) {
        await windowManager.setFullScreen(true);
      } else {
        await windowManager.setFullScreen(false);
        // После выхода из fullscreen — максимизируем, чтобы не было маленького окна.
        if (!await windowManager.isMaximized()) {
          await windowManager.maximize();
        }
      }
      await _syncState();
    } catch (e) {
      debugPrint('WindowControls.toggleFullScreen failed: $e');
    }
  }

  Future<void> _close() async {
    try {
      await windowManager.close();
    } catch (e) {
      debugPrint('WindowControls.close failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeNotifier.instance.isDark;
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
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
            // Window buttons — вне drag-зоны
            _WinBtn(
              icon: Icons.remove,
              tooltip: 'Свернуть',
              isDark: isDark,
              onTap: _minimize,
            ),
            _WinBtn(
              icon: _isFullScreen
                  ? Icons.fullscreen_exit
                  : (_isMaximized ? Icons.filter_none : Icons.crop_square),
              tooltip: _isFullScreen
                  ? 'Выйти из полноэкранного режима'
                  : (_isMaximized ? 'Восстановить' : 'На весь экран'),
              isDark: isDark,
              onTap: _toggleFullScreen,
            ),
            _WinBtn(
              icon: Icons.close,
              tooltip: 'Закрыть',
              isClose: true,
              isDark: isDark,
              onTap: _close,
            ),
          ],
        ),
      ),
    );
  }
}

class _WinBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isClose;
  final bool isDark;
  final String tooltip;

  const _WinBtn({
    required this.icon,
    required this.onTap,
    required this.isDark,
    this.isClose = false,
    this.tooltip = '',
  });

  @override
  State<_WinBtn> createState() => _WinBtnState();
}

class _WinBtnState extends State<_WinBtn> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final hoverBg = widget.isClose
        ? const Color(0xFFE81123)
        : (widget.isDark
            ? Colors.white.withOpacity(0.12)
            : Colors.black.withOpacity(0.08));
    final iconColor =
        (_hovered && widget.isClose) ? Colors.white : AppTheme.textMuted;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTap();
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: Container(
            width: 46,
            height: kTitleBarHeight,
            color: _hovered || _pressed ? hoverBg : Colors.transparent,
            child: Icon(
              widget.icon,
              size: 14,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
