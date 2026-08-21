import 'package:flutter/material.dart';

import 'design/gateway_theme.dart';
import 'screens/app_shell.dart';
import 'screens/subscription_screen.dart';
import 'state/gateway_controller.dart';
import 'state/gateway_scope.dart';

class WesiAeroApp extends StatefulWidget {
  const WesiAeroApp({
    required this.controller,
    super.key,
  });

  final GatewayController controller;

  @override
  State<WesiAeroApp> createState() => _WesiAeroAppState();
}

class _WesiAeroAppState extends State<WesiAeroApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.controller.themeMode;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant WesiAeroApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    _themeMode = widget.controller.themeMode;
    widget.controller.addListener(_handleControllerChanged);
  }

  void _handleControllerChanged() {
    final next = widget.controller.themeMode;
    if (next == _themeMode) return;
    setState(() => _themeMode = next);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GatewayScope(
      controller: widget.controller,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Wesi Aero',
        theme: GatewayTheme.light(),
        darkTheme: GatewayTheme.dark(),
        themeMode: _themeMode,
        themeAnimationDuration: GatewayTokens.expressive,
        themeAnimationCurve: Curves.easeOutCubic,
        home: const BackdropGroup(
          child: Scaffold(body: _RootGate()),
        ),
      ),
    );
  }
}

class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final controller = GatewayScope.of(context);
    if (controller.commerceLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return AnimatedSwitcher(
      duration: GatewayTokens.expressive,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: controller.needsSubscription
          ? const SubscriptionScreen(key: ValueKey('subscription'))
          : const AppShell(key: ValueKey('app-shell')),
    );
  }
}
