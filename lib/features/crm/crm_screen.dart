import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class CrmScreen extends StatelessWidget {
  const CrmScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('CRM')),
      body: const Center(child: Text('База клиентов - в разработке')),
    );
  }
}
