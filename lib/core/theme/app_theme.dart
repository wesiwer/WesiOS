import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Theme mode enum
enum AppThemeMode { dark, light }

/// Theme notifier — singleton for global theme management
class ThemeNotifier extends ValueNotifier<AppThemeMode> {
  ThemeNotifier._() : super(AppThemeMode.dark);
  static final ThemeNotifier instance = ThemeNotifier._();

  bool get isDark => value == AppThemeMode.dark;
  bool get isLight => value == AppThemeMode.light;

  void toggle() {
    value = isDark ? AppThemeMode.light : AppThemeMode.dark;
  }

  void setDark() => value = AppThemeMode.dark;
  void setLight() => value = AppThemeMode.light;
}

/// AppTheme — unified color palette for both dark and light themes
class AppTheme {
  // ─── Dark Theme Colors ───
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
  static const Color _darkCarbonLight = Color(0xFF2A2A3A);
  static const Color _darkCarbonHighlight = Color(0xFF3A3A50);

  // ─── Light Theme Colors ───
  static const Color _lightBackground = Color(0xFFFFFFFF);
  static const Color _lightSurface = Color(0xFFF5F5F7);
  static const Color _lightSurfaceLight = Color(0xFFE8E8EC);
  static const Color _lightTextPrimary = Color(0xFF1A1A2E);
  static const Color _lightTextSecondary = Color(0xFF6B7280);
  static const Color _lightTextMuted = Color(0xFF9CA3AF);
  static const Color _lightGlassBg = Color(0x1A000000);
  static const Color _lightGlassBorder = Color(0x1A000000);
  static const Color _lightCarbonDark = Color(0xFFE8E8F0);
  static const Color _lightCarbonMid = Color(0xFFF0F0F5);
  static const Color _lightCarbonLight = Color(0xFFF8F8FC);
  static const Color _lightCarbonHighlight = Color(0xFFFFFFFF);

  // ─── Accent Colors (same for both) ───
  static const Color accentOrange = Color(0xFFF97316);
  static const Color accentGreen = Color(0xFF84CC16);
  static const Color accentRed = Color(0xFFEF4444);
  static const Color primary = Color(0xFFFFFFFF);
  static const Color lightAccentBlue = Color(0xFF3B82F6); // Light theme accent

  // ─── Current Theme Colors (computed) ───
  static Color get background => ThemeNotifier.instance.isDark ? _darkBackground : _lightBackground;
  static Color get surface => ThemeNotifier.instance.isDark ? _darkSurface : _lightSurface;
  static Color get surfaceLight => ThemeNotifier.instance.isDark ? _darkSurfaceLight : _lightSurfaceLight;
  static Color get textPrimary => ThemeNotifier.instance.isDark ? _darkTextPrimary : _lightTextPrimary;
  static Color get textSecondary => ThemeNotifier.instance.isDark ? _darkTextSecondary : _lightTextSecondary;
  static Color get textMuted => ThemeNotifier.instance.isDark ? _darkTextMuted : _lightTextMuted;
  static Color get glassBackground => ThemeNotifier.instance.isDark ? _darkGlassBg : _lightGlassBg;
  static Color get glassBorder => ThemeNotifier.instance.isDark ? _darkGlassBorder : _lightGlassBorder;
  static Color get carbonDark => ThemeNotifier.instance.isDark ? _darkCarbonDark : _lightCarbonDark;
  static Color get carbonMid => ThemeNotifier.instance.isDark ? _darkCarbonMid : _lightCarbonMid;
  static Color get carbonLight => ThemeNotifier.instance.isDark ? _darkCarbonLight : _lightCarbonLight;
  static Color get carbonHighlight => ThemeNotifier.instance.isDark ? _darkCarbonHighlight : _lightCarbonHighlight;

  static Color get accent => ThemeNotifier.instance.isDark ? accentOrange : lightAccentBlue;

  static BoxDecoration get glassDecoration => BoxDecoration(
    color: glassBackground,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: glassBorder, width: 1),
    boxShadow: [
      BoxShadow(
        color: (ThemeNotifier.instance.isDark ? Colors.black : Colors.grey).withOpacity(0.2),
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
        primary: isDark ? primary : lightAccentBlue,
        secondary: accent,
        surface: surface,
        error: accentRed,
        onPrimary: isDark ? background : Colors.white,
        onSecondary: isDark ? background : Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: textPrimary),
        displayMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textPrimary),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: textPrimary),
        bodyLarge: TextStyle(fontSize: 16, color: textPrimary),
        bodyMedium: TextStyle(fontSize: 14, color: textSecondary),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary),
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
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
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
    );
  }

  static SystemUiOverlayStyle get systemOverlayStyle {
    return ThemeNotifier.instance.isDark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: background,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: background,
          );
  }
}
