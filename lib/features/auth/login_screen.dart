import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('WesiOS Login', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
              child: const Text('Войти'),
            ),
          ],
        ),
      ),
    );
  }
}
