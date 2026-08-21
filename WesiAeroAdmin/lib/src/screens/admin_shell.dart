import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../design/admin_theme.dart';
import '../state/admin_scope.dart';
import '../widgets/admin_wordmark.dart';
import '../widgets/ambient_background.dart';
import 'dashboard_screen.dart';
import 'keys_screen.dart';
import 'payments_screen.dart';
import 'plans_screen.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';

class AdminShell extends StatelessWidget {
  const AdminShell({super.key});

  static const _destinations = [
    _Destination('Обзор', Icons.dashboard_outlined),
    _Destination('Серверы', Icons.dns_outlined),
    _Destination('Тарифы', Icons.tune_rounded),
    _Destination('Ключи', Icons.key_outlined),
    _Destination('Оплаты', Icons.payments_outlined),
    _Destination('Настройки', Icons.settings_outlined),
  ];

  static const _screens = [
    DashboardScreen(key: ValueKey('dashboard')),
    ServersScreen(key: ValueKey('servers')),
    PlansScreen(key: ValueKey('plans')),
    KeysScreen(key: ValueKey('keys')),
    PaymentsScreen(key: ValueKey('payments')),
    SettingsScreen(key: ValueKey('settings')),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = AdminScope.of(context);
    return AmbientBackground(
      reducedMotion: false,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= GatewayTokens.desktopBreakpoint;
            return Column(
              children: [
                _TopBar(desktop: desktop),
                Expanded(
                  child: desktop
                      ? Row(
                          children: [
                            NavigationRail(
                              selectedIndex: controller.navigationIndex,
                              onDestinationSelected: controller.selectNavigation,
                              extended: constraints.maxWidth >= 1180,
                              minWidth: 76,
                              minExtendedWidth: 210,
                              groupAlignment: -0.68,
                              destinations: _destinations
                                  .map(
                                    (item) => NavigationRailDestination(
                                      icon: Icon(item.icon),
                                      selectedIcon: Icon(item.icon),
                                      label: Text(item.label),
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                            VerticalDivider(width: 1, color: context.palette.border),
                            Expanded(child: _Body(index: controller.navigationIndex)),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(child: _Body(index: controller.navigationIndex)),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border(top: BorderSide(color: context.palette.border)),
                              ),
                              child: SafeArea(
                                top: false,
                                child: BottomNavigationBar(
                                  currentIndex: controller.navigationIndex,
                                  onTap: controller.selectNavigation,
                                  items: _destinations
                                      .map(
                                        (item) => BottomNavigationBarItem(
                                          icon: Icon(item.icon),
                                          label: item.label,
                                        ),
                                      )
                                      .toList(growable: false),
                                ),
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
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.desktop});

  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final controller = AdminScope.of(context);
    final content = Container(
      height: 64,
      padding: EdgeInsets.only(
        left: desktop ? GatewayTokens.space24 : GatewayTokens.space16,
        right: desktop && Platform.isWindows ? 0 : GatewayTokens.space8,
      ),
      decoration: BoxDecoration(
        color: context.palette.background.withValues(alpha: 0.76),
        border: Border(bottom: BorderSide(color: context.palette.border)),
      ),
      child: Row(
        children: [
          const WesiAeroAdminWordmark(),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (controller.isDemo
                      ? context.palette.warning
                      : context.palette.connected)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              controller.isDemo ? 'DEMO' : 'API · ONLINE',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: controller.isDemo
                        ? context.palette.warning
                        : context.palette.connected,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
            ),
          ),
          const SizedBox(width: GatewayTokens.space4),
          IconButton(
            tooltip: 'Обновить',
            onPressed: controller.busy ? null : controller.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Сменить тему',
            onPressed: controller.toggleTheme,
            icon: Icon(
              controller.themeMode == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
          if (desktop && Platform.isWindows) const _WindowControls(),
        ],
      ),
    );
    return desktop && Platform.isWindows ? DragToMoveArea(child: content) : content;
  }
}

class _WindowControls extends StatelessWidget {
  const _WindowControls();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowButton(icon: Icons.remove_rounded, onPressed: windowManager.minimize),
        _WindowButton(
          icon: Icons.crop_square_rounded,
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        _WindowButton(icon: Icons.close_rounded, onPressed: windowManager.close),
      ],
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({required this.icon, required this.onPressed});

  final IconData icon;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onPressed,
        child: SizedBox(width: 46, height: 64, child: Icon(icon, size: 17)),
      );
}

class _Body extends StatelessWidget {
  const _Body({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final controller = AdminScope.of(context);
    if (controller.loading && controller.snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return AnimatedSwitcher(
      duration: GatewayTokens.expressive,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(index), child: AdminShell._screens[index]),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon);

  final String label;
  final IconData icon;
}
