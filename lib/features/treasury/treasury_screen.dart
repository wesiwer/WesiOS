import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class TreasuryScreen extends StatelessWidget {
  const TreasuryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Финансовый кабинет')),
      body: const Center(
        child: Text('Wesi Treasury — скоро', style: TextStyle(color: AppTheme.textMuted)),
      ),
    );
  }
}
