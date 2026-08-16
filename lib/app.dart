import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/localization/wesi_locale.dart';
import 'core/routes/app_router.dart';
import 'core/security/session_service.dart';
import 'core/security/shield_lock_screen.dart';
import 'core/services/currency_service.dart';
import 'core/sync/sync_endpoint.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/update_error_dialog.dart';
import 'core/widgets/window_controls.dart';
import 'features/ai/runtime/wesi_ai_answer_attention.dart';
import 'features/ai/widgets/wesi_ai_answer_ready_host.dart';
import 'features/audio/widgets/audio_mini_player.dart';
import 'features/calculator/calculator_screen.dart';
import 'features/splash/splash_screen.dart';
import 'features/team/services/team_service.dart';
import 'features/treasury/widgets/engine_download_overlay.dart';

bool get isDesktop {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
}

final GlobalKey<NavigatorState> wesiNavigatorKey = GlobalKey<NavigatorState>();

class WesiOSApp extends StatelessWidget {
  const WesiOSApp({super.key});

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
          navigatorKey: wesiNavigatorKey,
          navigatorObservers: <NavigatorObserver>[
            WesiAiAnswerAttention.navigatorObserver,
          ],
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
          home: const SplashScreen(),
          builder: (context, child) {
            return AnimatedThemeProvider(
              theme: AnimatedAppTheme.lerp(
                  ThemeNotifier.instance.isDark ? 0.0 : 1.0),
              child: _SessionEnforcementGate(
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
                              OverlayEntry(builder: (_) => const AudioMiniPlayer()),
                              if (isDesktop)
                                OverlayEntry(
                                    builder: (_) => const EngineDownloadOverlay()),
                              OverlayEntry(builder: (_) => const ShieldOverlay()),
                              OverlayEntry(builder: (_) => const UpdateErrorHost()),
                              OverlayEntry(
                                builder: (_) => WesiAiAnswerReadyHost(
                                  navigatorKey: wesiNavigatorKey,
                                ),
                              ),
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
              ),
            );
          },
        );
      },
    );
  }
}

/// Глобальная граница авторизации.
///
/// Серверный WesiOS session id отзывной. Если сотрудника удалили или один из
/// его сеансов завершили с другого устройства, [SessionService] получает
/// 401/403 и очищает [SyncEndpoint]. Этот виджет находится выше всех экранов,
/// поэтому локально сохранённая карточка сотрудника не может оставить уже
/// открытый интерфейс доступным после отзыва сервера.
class _SessionEnforcementGate extends StatefulWidget {
  final Widget child;

  const _SessionEnforcementGate({required this.child});

  @override
  State<_SessionEnforcementGate> createState() =>
      _SessionEnforcementGateState();
}

class _SessionEnforcementGateState extends State<_SessionEnforcementGate> {
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    SessionService.revision.addListener(_enforce);
    SyncEndpoint.revision.addListener(_enforce);
    WidgetsBinding.instance.addPostFrameCallback((_) => _enforce());
  }

  @override
  void dispose() {
    SessionService.revision.removeListener(_enforce);
    SyncEndpoint.revision.removeListener(_enforce);
    super.dispose();
  }

  void _enforce() {
    if (_handling || TeamService.current == null || SyncEndpoint.isConnected) {
      return;
    }
    _handling = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await TeamService.signOut();
        final navigator = wesiNavigatorKey.currentState;
        if (navigator != null) {
          navigator.pushNamedAndRemoveUntil('/login', (_) => false);
        }
      } finally {
        _handling = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
