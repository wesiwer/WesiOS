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
import '../../features/ai/ai_assistant_v2_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/profile/profile_with_telegram.dart';
import '../../features/profile/telegram_link_screen.dart';
import '../../features/calculator/calculator_screen.dart';
import '../../features/audio/audio_vault_v2_screen.dart';
import '../../features/crm/crm_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/time_center/time_center_screen.dart';
import '../../features/founder/founder_story_screen.dart';
import '../../features/sysadmin/sysadmin_screen.dart';
import '../../features/team/contacts_screen.dart';
import '../../features/chats/chats_screen.dart';
import '../../features/organizations/organizations_screen.dart';
import '../../features/organizations/inter_org_transfer_screen.dart';
import '../../features/organizations/my_finance_screen.dart';
import '../../features/organizations/services/organization_context.dart';
import '../../features/team/models/team_permissions.dart';
import '../../features/team/services/team_service.dart';
import '../sync/sync_endpoint.dart';

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final uri = Uri.tryParse(settings.name ?? '');
    final routeName = uri != null && uri.path.isNotEmpty ? uri.path : settings.name;
    final deepLinkOrganizationId = uri?.queryParameters['organizationId'];

    Widget orgAware(Widget child) => _DeepLinkOrganizationGate(
          organizationId: deepLinkOrganizationId,
          child: child,
        );

    switch (routeName) {
      case '/':
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      case '/welcome':
        return _slideUpRoute(const LoginScreen());
      case '/login':
        return _slideUpRoute(const LoginScreen());
      case '/home':
        return _fadeRoute(_AccessGate(child: orgAware(HomeScreen())));
      case '/treasury':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.treasury,
          child: orgAware(TreasuryScreen()),
        ));
      case '/treasury/forecast':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.forecast,
          child: orgAware(TreasuryForecastScreen()),
        ));
      case '/treasury/dashboard':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.treasury,
          child: TreasuryDashboardScreen(),
        ));
      case '/treasury/sandbox':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.sandbox,
          child: SandboxScreen(),
        ));
      case '/treasury/operations':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.treasury,
          child: OperationsScreen(),
        ));
      case '/organizations':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.treasury,
          child: const OrganizationsScreen(),
        ));
      case '/organizations/transfer':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.treasury,
          child: const InterOrgTransferScreen(),
        ));
      case '/my-finance':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.treasury,
          child: const MyFinanceScreen(),
        ));
      case '/tasks':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.tasks,
          child: orgAware(TasksScreen()),
        ));
      case '/roadmap':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.roadmap,
          child: const RoadmapScreen(),
        ));
      case '/analytics':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.analytics,
          child: AnalyticsScreen(),
        ));
      case '/knowledge':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.knowledge,
          child: KnowledgeBaseScreen(),
        ));
      case '/ai':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.ai,
          child: orgAware(const AiAssistantV2Screen()),
        ));
      case '/shield':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.shield,
          child: ShieldScreen(),
        ));
      case '/keys':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.keys,
          child: KeysScreen(),
        ));
      case '/sysadmin':
      case '/sysadmin/console':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.sysadmin,
          child: const SysadminScreen(),
        ));
      case '/settings':
        return _slideUpRoute(_AccessGate(child: SettingsScreen()));
      case '/profile':
        return _slideUpRoute(_AccessGate(child: const ProfileWithTelegram()));
      case '/profile/telegram':
        return _slideUpRoute(_AccessGate(child: const TelegramLinkScreen()));
      case '/calculator':
        return PageRouteBuilder(
          opaque: false,
          barrierDismissible: true,
          pageBuilder: (_, __, ___) => _AccessGate(child: CalculatorScreen()),
          transitionsBuilder: (_, anim, __, child) {
            return FadeTransition(
              opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 220),
        );
      case '/audio':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.audio,
          child: const AudioVaultV2Screen(),
        ));
      case '/crm':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.crm,
          child: const CrmScreen(),
        ));
      case '/calendar':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.calendar,
          child: CalendarScreen(),
        ));
      case '/time':
        return _slideUpRoute(_AccessGate(child: const TimeCenterScreen()));
      case '/contacts':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.contacts,
          child: const ContactsScreen(),
        ));
      case '/chats':
        return _slideUpRoute(_AccessGate(
          module: TeamModules.chats,
          child: const ChatsScreen(),
        ));
      case '/founder':
        return _fadeRoute(_AccessGate(child: FounderStoryScreen()));
      default:
        return MaterialPageRoute(builder: (_) => _AccessGate(child: HomeScreen()));
    }
  }

  static PageRouteBuilder _fadeRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
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
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
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
            if (requiredModule != null && !employee.permissions.allows(requiredModule)) {
              return const HomeScreen();
            }
            return child;
          },
        );
      },
    );
  }
}

class _DeepLinkOrganizationGate extends StatefulWidget {
  const _DeepLinkOrganizationGate({
    required this.child,
    required this.organizationId,
  });

  final Widget child;
  final String? organizationId;

  @override
  State<_DeepLinkOrganizationGate> createState() =>
      _DeepLinkOrganizationGateState();
}

class _DeepLinkOrganizationGateState extends State<_DeepLinkOrganizationGate> {
  String? _applied;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _apply());
  }

  @override
  void didUpdateWidget(covariant _DeepLinkOrganizationGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organizationId != widget.organizationId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _apply());
    }
  }

  Future<void> _apply() async {
    final id = widget.organizationId?.trim() ?? '';
    if (id.isEmpty || id == _applied || !SyncEndpoint.isConnected) return;
    try {
      await OrganizationContext.selectOrganization(id);
      _applied = id;
    } catch (_) {
      // Deep links never broaden access. If the organization is no longer
      // available, the existing validated context remains active.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
