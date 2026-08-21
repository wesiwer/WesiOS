import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../design/gateway_theme.dart';
import '../models/gateway_models.dart';
import '../state/gateway_scope.dart';
import '../widgets/ambient_background.dart';
import '../widgets/wesi_aero_wordmark.dart';
import 'dashboard_screen.dart';
import 'routing_screen.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static const _destinations = [
    _Destination('Aero', Icons.power_settings_new_rounded),
    _Destination('Серверы', Icons.public_rounded),
    _Destination('Маршруты', Icons.route_rounded),
    _Destination('Настройки', Icons.tune_rounded),
  ];

  static const _screens = [
    DashboardScreen(key: ValueKey('dashboard')),
    ServersScreen(key: ValueKey('servers')),
    RoutingScreen(key: ValueKey('routing')),
    SettingsScreen(key: ValueKey('settings')),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = GatewayScope.of(context);
    return AmbientBackground(
      reducedMotion: controller.reducedMotion,
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
                            _DesktopRail(
                              destinations: _destinations,
                              selectedIndex: controller.navigationIndex,
                              onSelect: controller.selectNavigation,
                            ),
                            VerticalDivider(
                              width: 1,
                              color: context.palette.border,
                            ),
                            Expanded(
                              child: _AnimatedScreen(
                                index: controller.navigationIndex,
                                screens: _screens,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(
                              child: _AnimatedScreen(
                                index: controller.navigationIndex,
                                screens: _screens,
                              ),
                            ),
                            _MobileNavigation(
                              destinations: _destinations,
                              selectedIndex: controller.navigationIndex,
                              onSelect: controller.selectNavigation,
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
    final controller = GatewayScope.of(context);
    final palette = context.palette;
    final connected = controller.snapshot.status == TunnelStatus.connected;
    final content = Container(
      height: desktop ? 64 : 58,
      padding: EdgeInsets.only(
        left: desktop ? GatewayTokens.space24 : GatewayTokens.space16,
        right: desktop && Platform.isWindows ? 0 : GatewayTokens.space8,
      ),
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.72),
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          const WesiAeroWordmark(),
          const Spacer(),
          AnimatedContainer(
            duration: GatewayTokens.normal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (connected ? palette.connected : palette.surfaceRaised)
                  .withValues(alpha: connected ? 0.12 : 0.56),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: connected
                    ? palette.connected.withValues(alpha: 0.34)
                    : palette.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  connected ? Icons.shield_rounded : Icons.shield_outlined,
                  size: 16,
                  color: connected ? palette.connected : palette.textMuted,
                ),
                if (desktop) ...[
                  const SizedBox(width: GatewayTokens.space4),
                  Text(
                    connected ? 'ЗАЩИЩЕНО' : 'НЕ ПОДКЛЮЧЕНО',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: connected ? palette.connected : palette.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                        ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: GatewayTokens.space4),
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

    if (desktop && Platform.isWindows) {
      return DragToMoveArea(child: content);
    }
    return content;
  }
}

class _WindowControls extends StatelessWidget {
  const _WindowControls();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowButton(
          tooltip: 'Свернуть',
          icon: Icons.remove_rounded,
          onPressed: windowManager.minimize,
        ),
        _WindowButton(
          tooltip: 'Развернуть',
          icon: Icons.crop_square_rounded,
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        _WindowButton(
          tooltip: 'Закрыть',
          icon: Icons.close_rounded,
          hoverColor: palette.danger,
          onPressed: windowManager.close,
        ),
      ],
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.hoverColor,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onPressed;
  final Color? hoverColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        hoverColor: hoverColor?.withValues(alpha: 0.82),
        child: SizedBox(
          width: 46,
          height: 64,
          child: Icon(icon, size: 17),
        ),
      ),
    );
  }
}

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelect,
      extended: MediaQuery.sizeOf(context).width >= 1120,
      minWidth: 76,
      minExtendedWidth: 208,
      groupAlignment: -0.72,
      leading: const SizedBox(height: GatewayTokens.space16),
      destinations: destinations
          .map(
            (destination) => NavigationRailDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.icon),
              label: Text(destination.label),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _MobileNavigation extends StatelessWidget {
  const _MobileNavigation({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: selectedIndex,
          onTap: onSelect,
          items: destinations
              .map(
                (destination) => BottomNavigationBarItem(
                  icon: Icon(destination.icon),
                  label: destination.label,
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _AnimatedScreen extends StatelessWidget {
  const _AnimatedScreen({required this.index, required this.screens});

  final int index;
  final List<Widget> screens;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: GatewayTokens.expressive,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.025),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: KeyedSubtree(key: ValueKey(index), child: screens[index]),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon);

  final String label;
  final IconData icon;
}
