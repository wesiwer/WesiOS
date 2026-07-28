import 'package:flutter/material.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/auth/welcome_screen.dart';
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
import '../../features/settings/settings_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/calculator/calculator_screen.dart';
import '../../features/audio/audio_vault_screen.dart';
import '../../features/crm/crm_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/founder/founder_story_screen.dart';

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      case '/welcome':
        return _slideUpRoute(const WelcomeScreen());
      case '/login':
        return _slideUpRoute(const LoginScreen());
      case '/home':
        return _fadeRoute(const HomeScreen());
      case '/treasury':
        return _slideUpRoute(const TreasuryScreen());
      case '/treasury/forecast':
        return _slideUpRoute(const TreasuryForecastScreen());
      case '/treasury/dashboard':
        return _slideUpRoute(const TreasuryDashboardScreen());
      case '/treasury/sandbox':
        return _slideUpRoute(const SandboxScreen());
      case '/treasury/operations':
        return _slideUpRoute(const OperationsScreen());
      case '/tasks':
        return _slideUpRoute(const TasksScreen());
      case '/roadmap':
        return _slideUpRoute(const RoadmapScreen());
      case '/analytics':
        return _slideUpRoute(const AnalyticsScreen());
      case '/knowledge':
        return _slideUpRoute(const KnowledgeBaseScreen());
      case '/settings':
        return _slideUpRoute(const SettingsScreen());
      case '/profile':
        return _slideUpRoute(const ProfileScreen());
      case '/calculator':
        // Калькулятор сам рисует backdrop — без BackdropFilter в роутере
        return PageRouteBuilder(
          opaque: false,
          barrierDismissible: true,
          pageBuilder: (_, __, ___) => const CalculatorScreen(),
          transitionsBuilder: (_, anim, __, child) {
            return FadeTransition(
              opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 220),
        );
      case '/audio':
        return _slideUpRoute(const AudioVaultScreen());
      case '/crm':
        return _slideUpRoute(const CrmScreen());
      case '/calendar':
        return _slideUpRoute(const CalendarScreen());
      case '/founder':
        return _fadeRoute(const FounderStoryScreen());
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(child: Text('Route not found: ${settings.name}')),
          ),
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
