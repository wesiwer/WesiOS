import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class RoadmapScreen extends StatelessWidget {
  const RoadmapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Roadmap')),
      body: const Center(child: Text('Диаграмма Ганта - в разработке')),
    );
  }
}
