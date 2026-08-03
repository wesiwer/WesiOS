import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_theme.dart';
// AnimatedThemeProvider is public in app_theme.dart
import 'core/localization/wesi_locale.dart';
import 'core/routes/app_router.dart';
import 'core/security/shield_lock_screen.dart';
import 'core/services/currency_service.dart';
import 'core/widgets/update_error_dialog.dart';
import 'core/widgets/window_controls.dart';
import 'features/calculator/calculator_screen.dart';
import 'features/splash/splash_screen.dart';
import 'features/first_run/first_run_screen.dart';
import 'features/treasury/widgets/engine_download_overlay.dart';

bool get isDesktop {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
}

class WesiOSApp extends StatelessWidget {
  final bool isFirstRun;
  const WesiOSApp({super.key, this.isFirstRun = false});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, mode, _) {
        final theme = AppTheme.themeData;
        return MaterialApp(
          title: 'WesiOS',
          debugShowCheckedModeBanner: false,
          theme: theme,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ru'), Locale('en')],
          locale: WesiLocale.isRussian ? const Locale('ru') : const Locale('en'),
          onGenerateRoute: AppRouter.onGenerateRoute,
          home: isFirstRun ? const FirstRunScreen() : const SplashScreen(),
          builder: (context, child) {
            // Здесь стоял TweenAnimationBuilder, у которого begin и end были
            // ОДНИМ И ТЕМ ЖЕ значением — то есть анимации не происходило
            // вовсе, а перестроение всего дерева на 600 мс происходило.
            // Плавность всё равно недостижима, пока виджеты читают цвета
            // статическими геттерами AppTheme.*, а не отсюда: провайдер ниже
            // не читает никто, кроме этой строки.
            return AnimatedThemeProvider(
              theme: AnimatedAppTheme.lerp(
                  ThemeNotifier.instance.isDark ? 0.0 : 1.0),
              child: Builder(
                builder: (context) {
                  return Stack(
                    children: [
                      if (child != null)
                        ValueListenableBuilder<bool>(
                          valueListenable: CurrencyService.privacyMode,
                          builder: (context, _, __) => ShieldGate(child: child),
                        ),
                      Positioned.fill(
                        child: Overlay(
                          initialEntries: [
                            OverlayEntry(
                              builder: (_) => ValueListenableBuilder<bool>(
                                valueListenable: CalculatorOverlay.visible,
                                builder: (context, visible, _) => visible
                                    ? const CalculatorScreen(asOverlay: true)
                                    : const SizedBox.shrink(),
                              ),
                            ),
                            if (isDesktop)
                              OverlayEntry(
                                  builder: (_) => const EngineDownloadOverlay()),
                            OverlayEntry(builder: (_) => const ShieldOverlay()),
                            // Ошибки OTA — поверх всего, кроме title bar.
                            OverlayEntry(builder: (_) => const UpdateErrorHost()),
                            if (isDesktop)
                              OverlayEntry(
                                builder: (_) => const Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: WindowControls(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
