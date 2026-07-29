import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/localization/wesi_locale.dart';
import 'core/routes/app_router.dart';
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

    return MaterialApp(
      title: 'WesiOS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      // Без этих делегатов встроенные виджеты Material (календарь
      // showDatePicker, диалоги выбора времени и т.п.) остаются на английском
      // независимо от языка интерфейса — свой WesiLocale на них не влияет.
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
        return Stack(
          children: [
            if (child != null) child,
            // Собственный Overlay обязателен: `builder` находится ВЫШЕ Navigator,
            // поэтому Overlay.of() отсюда не виден, а Tooltip его требует —
            // без этого подсказки на кнопках окна падают с
            // «No Overlay widget found» (в debug — ассертом при build).
            Positioned.fill(
              child: Overlay(
                initialEntries: [
                  // Калькулятор — глобальный оверлей поверх IndexedStack:
                  // закреплённый переживает переключение вкладок.
                  OverlayEntry(
                    builder: (_) => ValueListenableBuilder<bool>(
                      valueListenable: CalculatorOverlay.visible,
                      builder: (context, visible, _) => visible
                          ? const CalculatorScreen(asOverlay: true)
                          : const SizedBox.shrink(),
                    ),
                  ),
                  // Прогресс закачки движков прогноза — виден поверх ЛЮБОГО
                  // экрана, не только Forecast, ровно тем же приёмом, что
                  // и калькулятор выше.
                  if (isDesktop)
                    OverlayEntry(builder: (_) => const EngineDownloadOverlay()),
                  // Кнопки окна остаются выше калькулятора и всегда кликабельны
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
    );
  }
}
