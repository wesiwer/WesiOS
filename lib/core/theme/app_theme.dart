import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Theme mode enum
enum AppThemeMode { dark, light }

/// Theme notifier — singleton for global theme management.
///
/// Выбор сохраняется в Hive (`wesios_settings` / `app_theme`) и
/// восстанавливается при старте через [load].
///
/// Смену launcher-иконки (auto) подписывает `main.dart` через
/// [ThemeNotifier.instance.addListener] → AppIconService.apply(),
/// чтобы не плодить циклический import theme ↔ icon.
class ThemeNotifier extends ValueNotifier<AppThemeMode> {
  ThemeNotifier._() : super(AppThemeMode.dark);
  static final ThemeNotifier instance = ThemeNotifier._();

  static const String _boxName = 'wesios_settings';
  static const String _key = 'app_theme';

  bool get isDark => value == AppThemeMode.dark;
  bool get isLight => value == AppThemeMode.light;

  void toggle() {
    setMode(isDark ? AppThemeMode.light : AppThemeMode.dark);
  }

  void setDark() => setMode(AppThemeMode.dark);
  void setLight() => setMode(AppThemeMode.light);

  void setMode(AppThemeMode mode) {
    if (value == mode) return;
    value = mode;
    _persist(mode);
    AppTheme.applySystemOverlay();
  }

  /// Вызывать после открытия Hive-бокса, до первого кадра UI.
  static void load() {
    try {
      final raw = Hive.box(_boxName).get(_key) as String?;
      if (raw == 'light') {
        instance.value = AppThemeMode.light;
      } else {
        instance.value = AppThemeMode.dark;
      }
    } catch (_) {
      instance.value = AppThemeMode.dark;
    }
    AppTheme.applySystemOverlay();
  }

  Future<void> _persist(AppThemeMode mode) async {
    try {
      await Hive.box(_boxName).put(_key, mode == AppThemeMode.light ? 'light' : 'dark');
    } catch (_) {}
  }
}

/// AppTheme — unified color palette for both dark and light themes
class AppTheme {
  static const Color _darkBackground = Color(0xFF09090B);
  static const Color _darkSurface = Color(0xFF18181B);
  static const Color _darkSurfaceLight = Color(0xFF27272A);
  static const Color _darkTextPrimary = Color(0xFFFFFFFF);
  static const Color _darkTextSecondary = Color(0xFFA1A1AA);
  static const Color _darkTextMuted = Color(0xFF71717A);
  static const Color _darkGlassBg = Color(0x1AFFFFFF);
  static const Color _darkGlassBorder = Color(0x33FFFFFF);
  static const Color _darkCarbonDark = Color(0xFF0A0A0F);
  static const Color _darkCarbonMid = Color(0xFF1A1A24);
  static const Color _darkCarbonLight = Color(0xFF2A2A38);

  static const Color _lightBackground = Color(0xFFF8FAFC);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightSurfaceLight = Color(0xFFF1F5F9);
  static const Color _lightTextPrimary = Color(0xFF0F172A);
  static const Color _lightTextSecondary = Color(0xFF475569);
  static const Color _lightTextMuted = Color(0xFF94A3B8);
  static const Color _lightGlassBg = Color(0x0A0F172A);
  static const Color _lightGlassBorder = Color(0x1A0F172A);
  static const Color _lightCarbonDark = Color(0xFFE2E8F0);
  static const Color _lightCarbonMid = Color(0xFFF1F5F9);
  static const Color _lightCarbonLight = Color(0xFFF8FAFC);

  static const Color accent = Color(0xFF6366F1);
  static const Color accentRed = Color(0xFFEF4444);
  static const Color accentGreen = Color(0xFF22C55E);
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color accentCyan = Color(0xFF06B6D4);

  static Color get background =>
      ThemeNotifier.instance.isDark ? _darkBackground : _lightBackground;
  static Color get surface =>
      ThemeNotifier.instance.isDark ? _darkSurface : _lightSurface;
  static Color get surfaceLight =>
      ThemeNotifier.instance.isDark ? _darkSurfaceLight : _lightSurfaceLight;
  static Color get textPrimary =>
      ThemeNotifier.instance.isDark ? _darkTextPrimary : _lightTextPrimary;
  static Color get textSecondary =>
      ThemeNotifier.instance.isDark ? _darkTextSecondary : _lightTextSecondary;
  static Color get textMuted =>
      ThemeNotifier.instance.isDark ? _darkTextMuted : _lightTextMuted;
  static Color get glassBackground =>
      ThemeNotifier.instance.isDark ? _darkGlassBg : _lightGlassBg;
  static Color get glassBorder =>
      ThemeNotifier.instance.isDark ? _darkGlassBorder : _lightGlassBorder;
  static Color get carbonDark =>
      ThemeNotifier.instance.isDark ? _darkCarbonDark : _lightCarbonDark;
  static Color get carbonMid =>
      ThemeNotifier.instance.isDark ? _darkCarbonMid : _lightCarbonMid;
  static Color get carbonLight =>
      ThemeNotifier.instance.isDark ? _darkCarbonLight : _lightCarbonLight;

  static void applySystemOverlay() {
    final isDark = ThemeNotifier.instance.isDark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: background,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    ));
  }

  static BoxDecoration get glassDecoration => BoxDecoration(
        color: glassBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: glassBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: (ThemeNotifier.instance.isDark ? Colors.black : const Color(0xFF64748B))
                .withOpacity(ThemeNotifier.instance.isDark ? 0.2 : 0.12),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      );

  static ThemeData get themeData {
    final isDark = ThemeNotifier.instance.isDark;
    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: accent,
        secondary: accent,
        surface: surface,
        error: accentRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      textTheme: TextTheme(
        displayLarge:
            TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: textPrimary),
        displayMedium:
            TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textPrimary),
        titleLarge:
            TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary),
        titleMedium:
            TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: textPrimary),
        bodyLarge: TextStyle(fontSize: 16, color: textPrimary),
        bodyMedium: TextStyle(fontSize: 14, color: textSecondary),
        labelLarge:
            TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary),
      ),
      cardTheme: CardTheme(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: accent,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(
        color: glassBorder,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: TextStyle(color: textMuted),
      ),
    );
  }
}

/// Interpolated theme colors for smooth dark↔light transitions.
class AnimatedAppTheme {
  final Color background;
  final Color surface;
  final Color surfaceLight;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color glassBackground;
  final Color glassBorder;
  final Color carbonDark;
  final Color carbonMid;
  final Color carbonLight;

  const AnimatedAppTheme({
    required this.background,
    required this.surface,
    required this.surfaceLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.glassBackground,
    required this.glassBorder,
    required this.carbonDark,
    required this.carbonMid,
    required this.carbonLight,
  });

  static const _dark = AnimatedAppTheme(
    background: AppTheme._darkBackground,
    surface: AppTheme._darkSurface,
    surfaceLight: AppTheme._darkSurfaceLight,
    textPrimary: AppTheme._darkTextPrimary,
    textSecondary: AppTheme._darkTextSecondary,
    textMuted: AppTheme._darkTextMuted,
    glassBackground: AppTheme._darkGlassBg,
    glassBorder: AppTheme._darkGlassBorder,
    carbonDark: AppTheme._darkCarbonDark,
    carbonMid: AppTheme._darkCarbonMid,
    carbonLight: AppTheme._darkCarbonLight,
  );

  static const _light = AnimatedAppTheme(
    background: AppTheme._lightBackground,
    surface: AppTheme._lightSurface,
    surfaceLight: AppTheme._lightSurfaceLight,
    textPrimary: AppTheme._lightTextPrimary,
    textSecondary: AppTheme._lightTextSecondary,
    textMuted: AppTheme._lightTextMuted,
    glassBackground: AppTheme._lightGlassBg,
    glassBorder: AppTheme._lightGlassBorder,
    carbonDark: AppTheme._lightCarbonDark,
    carbonMid: AppTheme._lightCarbonMid,
    carbonLight: AppTheme._lightCarbonLight,
  );

  /// t=0 → dark, t=1 → light
  static AnimatedAppTheme lerp(double t) {
    return AnimatedAppTheme(
      background: Color.lerp(_dark.background, _light.background, t)!,
      surface: Color.lerp(_dark.surface, _light.surface, t)!,
      surfaceLight: Color.lerp(_dark.surfaceLight, _light.surfaceLight, t)!,
      textPrimary: Color.lerp(_dark.textPrimary, _light.textPrimary, t)!,
      textSecondary: Color.lerp(_dark.textSecondary, _light.textSecondary, t)!,
      textMuted: Color.lerp(_dark.textMuted, _light.textMuted, t)!,
      glassBackground: Color.lerp(_dark.glassBackground, _light.glassBackground, t)!,
      glassBorder: Color.lerp(_dark.glassBorder, _light.glassBorder, t)!,
      carbonDark: Color.lerp(_dark.carbonDark, _light.carbonDark, t)!,
      carbonMid: Color.lerp(_dark.carbonMid, _light.carbonMid, t)!,
      carbonLight: Color.lerp(_dark.carbonLight, _light.carbonLight, t)!,
    );
  }

  static AnimatedAppTheme of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<AnimatedThemeProvider>();
    return provider?.theme ?? (ThemeNotifier.instance.isDark ? _dark : _light);
  }
}

class AnimatedThemeProvider extends InheritedWidget {
  final AnimatedAppTheme theme;
  const AnimatedThemeProvider({required this.theme, required super.child});

  @override
  bool updateShouldNotify(AnimatedThemeProvider old) => theme != old.theme;
}
