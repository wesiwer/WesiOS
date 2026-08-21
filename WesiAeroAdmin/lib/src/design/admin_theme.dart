import 'package:flutter/material.dart';

abstract final class GatewayTokens {
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space48 = 48;

  static const double radiusSmall = 10;
  static const double radiusMedium = 14;
  static const double radiusLarge = 20;
  static const double radiusHero = 28;

  static const Duration quick = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 280);
  static const Duration expressive = Duration(milliseconds: 420);

  static const double mobileBreakpoint = 720;
  static const double desktopBreakpoint = 960;
  static const double maxContentWidth = 1240;
}

@immutable
class GatewayPalette extends ThemeExtension<GatewayPalette> {
  const GatewayPalette({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.glass,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentForeground,
    required this.connected,
    required this.connectedForeground,
    required this.danger,
    required this.warning,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color glass;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentForeground;
  final Color connected;
  final Color connectedForeground;
  final Color danger;
  final Color warning;

  static const dark = GatewayPalette(
    background: Color(0xFF09090B),
    surface: Color(0xFF18181B),
    surfaceRaised: Color(0xFF27272A),
    glass: Color(0x1AFFFFFF),
    border: Color(0x33FFFFFF),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFD4D4D8),
    textMuted: Color(0xFFA1A1AA),
    accent: Color(0xFFF97316),
    accentForeground: Color(0xFF1C0B02),
    connected: Color(0xFF38BDF8),
    connectedForeground: Color(0xFF061621),
    danger: Color(0xFFF87171),
    warning: Color(0xFFFBBF24),
  );

  static const light = GatewayPalette(
    background: Color(0xFFF8F9FC),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFEEF1F6),
    glass: Color(0xCCFFFFFF),
    border: Color(0x240F172A),
    textPrimary: Color(0xFF172033),
    textSecondary: Color(0xFF465166),
    textMuted: Color(0xFF667085),
    accent: Color(0xFF2563EB),
    accentForeground: Color(0xFFFFFFFF),
    connected: Color(0xFF607F9E),
    connectedForeground: Color(0xFFFFFFFF),
    danger: Color(0xFFB42318),
    warning: Color(0xFF9A6700),
  );

  @override
  GatewayPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? glass,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentForeground,
    Color? connected,
    Color? connectedForeground,
    Color? danger,
    Color? warning,
  }) {
    return GatewayPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      glass: glass ?? this.glass,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      accentForeground: accentForeground ?? this.accentForeground,
      connected: connected ?? this.connected,
      connectedForeground: connectedForeground ?? this.connectedForeground,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
    );
  }

  @override
  GatewayPalette lerp(covariant GatewayPalette? other, double t) {
    if (other == null) return this;
    return GatewayPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentForeground:
          Color.lerp(accentForeground, other.accentForeground, t)!,
      connected: Color.lerp(connected, other.connected, t)!,
      connectedForeground:
          Color.lerp(connectedForeground, other.connectedForeground, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

abstract final class GatewayTheme {
  static ThemeData dark() => _build(Brightness.dark, GatewayPalette.dark);
  static ThemeData light() => _build(Brightness.light, GatewayPalette.light);

  static ThemeData _build(Brightness brightness, GatewayPalette palette) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: palette.background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: palette.accent,
        onPrimary: palette.accentForeground,
        secondary: palette.connected,
        onSecondary: palette.connectedForeground,
        error: palette.danger,
        onError: Colors.white,
        surface: palette.surface,
        onSurface: palette.textPrimary,
      ),
      extensions: const <ThemeExtension<dynamic>>[
        GatewayPalette.dark,
      ],
    );

    final textTheme = base.textTheme.copyWith(
      displayLarge: TextStyle(
        color: palette.textPrimary,
        fontSize: 36,
        height: 1.05,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
      ),
      headlineLarge: TextStyle(
        color: palette.textPrimary,
        fontSize: 28,
        height: 1.12,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      headlineMedium: TextStyle(
        color: palette.textPrimary,
        fontSize: 22,
        height: 1.18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
      ),
      titleLarge: TextStyle(
        color: palette.textPrimary,
        fontSize: 18,
        height: 1.25,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: palette.textPrimary,
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        color: palette.textPrimary,
        fontSize: 16,
        height: 1.45,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: TextStyle(
        color: palette.textSecondary,
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: TextStyle(
        color: palette.textPrimary,
        fontSize: 14,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        color: palette.textMuted,
        fontSize: 13,
        height: 1.2,
        fontWeight: FontWeight.w600,
      ),
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(GatewayTokens.radiusMedium),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(GatewayTokens.radiusMedium),
      borderSide: BorderSide(color: palette.border),
    );

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[palette],
      textTheme: textTheme,
      iconTheme: IconThemeData(color: palette.textSecondary, size: 22),
      dividerColor: palette.border,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: palette.textPrimary,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: palette.glass,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GatewayTokens.radiusLarge),
          side: BorderSide(color: palette.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceRaised.withValues(alpha: isDark ? 0.58 : 0.8),
        hintStyle: textTheme.bodyMedium?.copyWith(color: palette.textMuted),
        labelStyle: textTheme.bodyMedium,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: palette.accent, width: 1.4),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: palette.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: palette.accentForeground,
          backgroundColor: palette.accent,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: shape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(color: palette.border),
          shape: shape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStatePropertyAll(BorderSide(color: palette.border)),
          shape: WidgetStatePropertyAll(shape),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? palette.accentForeground
                : palette.textSecondary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? palette.accent
                : palette.glass,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: palette.glass,
        selectedColor: palette.accent.withValues(alpha: 0.22),
        side: BorderSide(color: palette.border),
        shape: shape,
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.accentForeground
              : palette.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.accent
              : palette.surfaceRaised,
        ),
        trackOutlineColor: WidgetStatePropertyAll(palette.border),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        backgroundColor: palette.surface.withValues(alpha: 0.92),
        selectedItemColor: palette.accent,
        unselectedItemColor: palette.textMuted,
        selectedLabelStyle: textTheme.labelMedium,
        unselectedLabelStyle: textTheme.labelMedium,
      ),
      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        backgroundColor: palette.surface.withValues(alpha: 0.74),
        indicatorColor: palette.accent.withValues(alpha: 0.18),
        selectedIconTheme: IconThemeData(color: palette.accent),
        unselectedIconTheme: IconThemeData(color: palette.textMuted),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: palette.accent,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium,
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GatewayTokens.radiusLarge),
          side: BorderSide(color: palette.border),
        ),
        titleTextStyle: textTheme.headlineMedium,
        contentTextStyle: textTheme.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.surfaceRaised,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: palette.textPrimary,
        ),
        shape: shape,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(GatewayTokens.radiusSmall),
          border: Border.all(color: palette.border),
        ),
        textStyle: textTheme.labelMedium?.copyWith(color: palette.textPrimary),
      ),
    );
  }
}

extension GatewayThemeContext on BuildContext {
  GatewayPalette get palette =>
      Theme.of(this).extension<GatewayPalette>() ?? GatewayPalette.dark;
}
