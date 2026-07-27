import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class RoadmapScreen extends StatelessWidget {
  const RoadmapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Диаграмма Ганта')),
      body: const Center(
        child: Text('Roadmap — скоро', style: TextStyle(color: AppTheme.textMuted)),
      ),
    );
  }
}
