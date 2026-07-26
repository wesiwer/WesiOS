import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Аналитика')),
      body: const Center(child: Text('Визуальная аналитика - в разработке')),
    );
  }
}
