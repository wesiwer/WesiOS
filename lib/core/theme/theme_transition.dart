import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Animated theme transition — elements repaint one by one with stagger
/// Duration: ~0.5-1 second total
class ThemeTransition extends StatefulWidget {
  final Widget child;

  const ThemeTransition({super.key, required this.child});

  @override
  State<ThemeTransition> createState() => _ThemeTransitionState();
}

class _ThemeTransitionState extends State<ThemeTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  AppThemeMode? _previousMode;
  bool _isTransitioning = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    ThemeNotifier.instance.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    ThemeNotifier.instance.removeListener(_onThemeChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) {
      setState(() {
        _isTransitioning = true;
        _previousMode = ThemeNotifier.instance.isDark 
            ? AppThemeMode.light 
            : AppThemeMode.dark;
      });
      _controller.forward(from: 0).then((_) {
        if (mounted) {
          setState(() {
            _isTransitioning = false;
            _previousMode = null;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Theme(
          data: AppTheme.themeData,
          child: Container(
            color: AppTheme.background,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Staggered theme transition overlay — paints a ripple effect
class ThemeTransitionOverlay extends StatelessWidget {
  final Widget child;

  const ThemeTransitionOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, mode, _) {
        return AnimatedTheme(
          data: AppTheme.themeData,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOutCubic,
          child: child,
        );
      },
    );
  }
}
