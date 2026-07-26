import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Задачи')),
      body: const Center(child: Text('Система задач - в разработке')),
    );
  }
}
