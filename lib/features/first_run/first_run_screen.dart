import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/firebase_config_service.dart';
import '../splash/splash_screen.dart';

class FirstRunScreen extends StatefulWidget {
  const FirstRunScreen({super.key});

  @override
  State<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends State<FirstRunScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiKeyCtrl = TextEditingController();
  final _appIdCtrl = TextEditingController();
  final _projectIdCtrl = TextEditingController();
  final _messagingSenderIdCtrl = TextEditingController();
  final _authDomainCtrl = TextEditingController();
  final _storageBucketCtrl = TextEditingController();
  final _measurementIdCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _appIdCtrl.dispose();
    _projectIdCtrl.dispose();
    _messagingSenderIdCtrl.dispose();
    _authDomainCtrl.dispose();
    _storageBucketCtrl.dispose();
    _measurementIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAndProceed() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final configService = FirebaseConfigService();
      await configService.saveConfig(
        apiKey: _apiKeyCtrl.text.trim(),
        appId: _appIdCtrl.text.trim(),
        messagingSenderId: _messagingSenderIdCtrl.text.trim(),
        projectId: _projectIdCtrl.text.trim(),
        authDomain: _authDomainCtrl.text.trim().isEmpty ? null : _authDomainCtrl.text.trim(),
        storageBucket: _storageBucketCtrl.text.trim().isEmpty ? null : _storageBucketCtrl.text.trim(),
        measurementId: _measurementIdCtrl.text.trim().isEmpty ? null : _measurementIdCtrl.text.trim(),
      );

      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: _apiKeyCtrl.text.trim(),
          appId: _appIdCtrl.text.trim(),
          messagingSenderId: _messagingSenderIdCtrl.text.trim(),
          projectId: _projectIdCtrl.text.trim(),
          authDomain: _authDomainCtrl.text.trim().isEmpty ? null : _authDomainCtrl.text.trim(),
          storageBucket: _storageBucketCtrl.text.trim().isEmpty ? null : _storageBucketCtrl.text.trim(),
          measurementId: _measurementIdCtrl.text.trim().isEmpty ? null : _measurementIdCtrl.text.trim(),
        ),
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SplashScreen()),
        );
      }
    } catch (e) {
      setState(() => _error = 'Ошибка инициализации Firebase: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Column(
                      children: [
                        Text(
                          'WesiOS',
                          style: Theme.of(context).textTheme.displayLarge?.copyWith(
                                fontSize: 48,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.accentOrange,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Первоначальная настройка',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Введите данные вашего Firebase проекта.\nИх можно найти в консоли Firebase → Project Settings → General → Your apps → SDK setup and configuration',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  _buildField(
                    controller: _apiKeyCtrl,
                    label: 'API Key *',
                    hint: 'AIzaSy...',
                    validator: (v) => v == null || v.isEmpty ? 'Обязательное поле' : null,
                  ),
                  _buildField(
                    controller: _appIdCtrl,
                    label: 'App ID *',
                    hint: '1:123456789:web:abc123...',
                    validator: (v) => v == null || v.isEmpty ? 'Обязательное поле' : null,
                  ),
                  _buildField(
                    controller: _projectIdCtrl,
                    label: 'Project ID *',
                    hint: 'my-project-id',
                    validator: (v) => v == null || v.isEmpty ? 'Обязательное поле' : null,
                  ),
                  _buildField(
                    controller: _messagingSenderIdCtrl,
                    label: 'Messaging Sender ID *',
                    hint: '123456789',
                    validator: (v) => v == null || v.isEmpty ? 'Обязательное поле' : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Дополнительные поля (опционально):',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _authDomainCtrl,
                    label: 'Auth Domain',
                    hint: 'my-project.firebaseapp.com',
                  ),
                  _buildField(
                    controller: _storageBucketCtrl,
                    label: 'Storage Bucket',
                    hint: 'my-project.appspot.com',
                  ),
                  _buildField(
                    controller: _measurementIdCtrl,
                    label: 'Measurement ID',
                    hint: 'G-XXXXXXXX',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.accentRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.accentRed.withOpacity(0.3)),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(color: AppTheme.accentRed),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveAndProceed,
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Сохранить и продолжить', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            backgroundColor: AppTheme.surface,
                            title: const Text('Где найти эти данные?'),
                            content: const Text(
                              '1. Откройте https://console.firebase.google.com\n'
                              '2. Выберите ваш проект\n'
                              '3. Нажмите шестеренку → Project Settings\n'
                              '4. В разделе "Your apps" выберите Web app\n'
                              '5. Скопируйте значения из блока firebaseConfig\n\n'
                              'Если у вас нет Web app — создайте его, нажав "Add app" → Web.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Понятно'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Text('Где взять эти данные?'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        // Skip Firebase for pure local / demo mode
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const SplashScreen()),
                        );
                      },
                      child: Text(
                        'Пропустить (локальный режим без Firebase)',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        validator: validator,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: AppTheme.textSecondary),
          hintStyle: const TextStyle(color: AppTheme.textMuted),
        ),
      ),
    );
  }
}
