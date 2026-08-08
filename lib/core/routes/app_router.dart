import 'package:flutter/material.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/treasury/treasury_screen.dart';
import '../../features/treasury/forecast_chart_screen.dart';
import '../../features/treasury/treasury_dashboard_screen.dart';
import '../../features/treasury/sandbox_screen.dart';
import '../../features/treasury/operations_screen.dart';
import '../../features/tasks/tasks_screen.dart';
import '../../features/roadmap/roadmap_screen.dart';
import '../../features/analytics/analytics_screen.dart';
import '../../features/knowledge/knowledge_base_screen.dart';
import '../../features/shield/shield_screen.dart';
import '../../features/keys/keys_screen.dart';
import '../../features/ai/ai_assistant_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/calculator/calculator_screen.dart';
import '../../features/audio/audio_vault_screen.dart';
import '../../features/crm/crm_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/founder/founder_story_screen.dart';
import '../../features/sysadmin/sysadmin_screen.dart';
import '../../features/team/contacts_screen.dart';
import '../../features/chats/chats_screen.dart';
import '../../features/team/models/team_permissions.dart';
import '../../features/team/services/team_service.dart';
import '../sync/sync_endpoint.dart';

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      case '/welcome':
        // Старый onboarding больше не является обходом обязательного входа.
        return _slideUpRoute(const LoginScreen());
      case '/login':
        return _slideUpRoute(const LoginScreen());
      case '/home':
        return _fadeRoute(const _AccessGate(child: HomeScreen()));
      case '/treasury':
        return _slideUpRoute(const _AccessGate(
          module: TeamModules.treasury,
          child: TreasuryScreen(),
        ));
      case '/treasury/forecast':
        return _slideUpRoute(const _AccessGate(
          module: TeamModules.forecast,
          child: TreasuryForecastScreen(),
        ));
      case '/treasury/dashboard':
        return _slideUpRoute(const _AccessGate(
          module: TeamModules.treasury,
          child: TreasuryDashboardScreen(),
        ));
      case '/treasury/sandbox':
        return _slideUpRoute(const _AccessGate(
          module: TeamModules.sandbox,
          child: SandboxScreen(),
        ));
      case '/treasury/operations':
        return _slideUpRoute(const _AccessGate(
          module: TeamModules.treasury,
          child: OperationsScreen(),
        ));
      case '/tasks':
        return _slideUpRoute(const _AccessGate(
          module: TeamModules.tasks,
          child: TasksScreen(),
        ));
      case '/roadmap':
        return _slideUpRoute(const _AccessGate(
          module: TeamModules.roadmap,
          child: RoadmapScreen(),
        ));
      case '/analytics':
        return _slideUpRoute(const _AccessGate(
          module: TeamModules.analytics,
          child: AnalyticsScreen(),
        ));
      case '/knowledge':
        return _slideUpRoute(const _AccessGate(
          module: TeamModules.knowledge,
          child: KnowledgeBaseScreen(),
        ));
      case '/ai':
        return _slideUpRoute(const _AccessGate(
          module: TeamModules.ai,
          child: AiAssistantScreen(),
        ));
      case '/shield':
        return _slideUpRoute(const _AccessGate(
          module: TeamModules.shield,
          child: ShieldScreen(),
        ));
      case '/keys':
        return _slideUpRoute(const _AccessGate(
          module: TeamModules.keys,
          child: KeysScreen(),
        ));
      case '/sysadmin':
      case '/sysadmin/console':
        return _slideUpRoute(const _AccessGate(
          module: TeamModules.sysadmin,
          child: SysadminScreen(),
        ));
      case '/settings':
        return _slideUpRoute(const _AccessGate(child: SettingsScreen()));
      case '/profile':
        return _slideUpRoute(const _AccessGate(child: ProfileScreen()));
      case '/calculator':
        return PageRouteBuilder(
          opaque: false,
          barrierDismissible: true,
          pageBuilder: (_, __, ___) =>
              const _AccessGate(child: CalculatorScreen()),
          transitionsBuilder: (_, anim, __, child) {
            return FadeTransition(
              opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 220),
        );
      case '/audio':
        return _slideUpRoute(const _AccessGate(
          module: TeamModules.audio,
          child: AudioVaultScreen(),
        ));
      case '/crm':
        return _slideUpRoute(const _AccessGate(
          module: TeamModules.crm,
          child: CrmScreen(),
        ));
      case '/calendar':
        return _slideUpRoute(const _AccessGate(
          module: TeamModules.calendar,
          child: CalendarScreen(),
        ));
      case '/contacts':
        return _slideUpRoute(const _AccessGate(
          module: TeamModules.contacts,
          child: ContactsScreen(),
        ));
      case '/chats':
        return _slideUpRoute(const _AccessGate(
          module: TeamModules.chats,
          child: ChatsScreen(),
        ));
      case '/founder':
        return _fadeRoute(const _AccessGate(child: FounderStoryScreen()));
      default:
        return MaterialPageRoute(
          builder: (_) => const _AccessGate(child: HomeScreen()),
        );
    }
  }

  static PageRouteBuilder _fadeRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  static PageRouteBuilder _slideUpRoute(Widget page) {
    return PageRouteBuilder(
      opaque: false,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final slideUp = Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
        final fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: const Interval(0, 0.5)),
        );
        return SlideTransition(
          position: slideUp,
          child: FadeTransition(opacity: fadeIn, child: child),
        );
      },
      transitionDuration: const Duration(milliseconds: 400),
    );
  }
}

/// Центральный fail-closed guard для всех внутренних экранов.
///
/// UI-фильтры в Home/More остаются для удобства, но безопасность не зависит
/// от того, не забыли ли разработчики скрыть конкретную кнопку.
class _AccessGate extends StatelessWidget {
  final Widget child;
  final String? module;

  const _AccessGate({required this.child, this.module});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: TeamService.revision,
      builder: (context, _, __) {
        return ValueListenableBuilder<int>(
          valueListenable: SyncEndpoint.revision,
          builder: (context, _, __) {
            final employee = TeamService.current;
            if (employee == null || !SyncEndpoint.isConnected) {
              return const LoginScreen();
            }

            final requiredModule = module;
            if (requiredModule != null &&
                !employee.permissions.allows(requiredModule)) {
              return const HomeScreen();
            }
            return child;
          },
        );
      },
    );
  }
}
