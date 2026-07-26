import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AudioVaultScreen extends StatelessWidget {
  const AudioVaultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Audio Vault')),
      body: const Center(child: Text('Хранилище битов - в разработке')),
    );
  }
}
