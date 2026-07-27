import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Календарь')),
      body: const Center(
        child: Text('Календарь — скоро', style: TextStyle(color: AppTheme.textMuted)),
      ),
    );
  }
}
