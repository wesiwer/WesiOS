import 'package:flutter/material.dart';

import 'design/admin_theme.dart';
import 'screens/admin_shell.dart';
import 'state/admin_controller.dart';
import 'state/admin_scope.dart';

class WesiAeroAdminApp extends StatelessWidget {
  const WesiAeroAdminApp({required this.controller, super.key});

  final AdminController controller;

  @override
  Widget build(BuildContext context) {
    return AdminScope(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Wesi Aero Admin',
          theme: GatewayTheme.light(),
          darkTheme: GatewayTheme.dark(),
          themeMode: controller.themeMode,
          themeAnimationDuration: GatewayTokens.expressive,
          home: const Scaffold(body: AdminShell()),
        ),
      ),
    );
  }
}
