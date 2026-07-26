import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class KnowledgeBaseScreen extends StatelessWidget {
  const KnowledgeBaseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('База знаний')),
      body: const Center(child: Text('Древовидная база знаний - в разработке')),
    );
  }
}
