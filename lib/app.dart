import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'core/theme/app_theme.dart';
import 'core/routes/app_router.dart';
import 'core/widgets/window_controls.dart';
import 'features/splash/splash_screen.dart';
import 'features/first_run/first_run_screen.dart';

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
      onGenerateRoute: AppRouter.onGenerateRoute,
      home: isFirstRun ? const FirstRunScreen() : const SplashScreen(),
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            if (isDesktop)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: WindowControls(),
              ),
          ],
        );
      },
    );
  }
}
