import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/localization/wesi_locale.dart';
import 'core/routes/app_router.dart';
import 'core/security/shield_lock_screen.dart';
import 'core/services/currency_service.dart';
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

    // Тема живёт в ThemeNotifier: один ValueListenableBuilder перестраивает
    // MaterialApp и всё дерево, когда пользователь переключает dark/light.
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'WesiOS',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.themeData,
          // Одна палитра из AppTheme — themeMode не нужен: данные уже
          // соответствуют текущему режиму notifier'а.
          themeMode: ThemeMode.light,
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
            return AnimatedTheme(
              data: AppTheme.themeData,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOutCubic,
              child: Stack(
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
              ),
            );
          },
        );
      },
    );
  }
}
