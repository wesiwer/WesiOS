import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/firebase_config_service.dart';
import '../../core/widgets/hover_button.dart';
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
    setState(() { _isLoading = true; _error = null; });

    try {
      final service = FirebaseConfigService();
      await service.saveConfig(
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

  Future<void> _skip() async {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),
                  Center(
                    child: Column(
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withOpacity(0.9),
                                Colors.white.withOpacity(0.5),
                                AppTheme.carbonHighlight.withOpacity(0.3),
                              ],
                            ).createShader(bounds);
                          },
                          child: const Text(
                            'WesiOS',
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 8,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Первоначальная настройка',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Введите данные вашего Firebase проекта.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  _buildField(_apiKeyCtrl, 'API Key *', 'AIzaSy...'),
                  _buildField(_appIdCtrl, 'App ID *', '1:123456789:web:abc123...'),
                  _buildField(_projectIdCtrl, 'Project ID *', 'my-project-id'),
                  _buildField(_messagingSenderIdCtrl, 'Messaging Sender ID *', '123456789'),
                  const SizedBox(height: 16),
                  Text(
                    'Дополнительные поля (опционально):',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  _buildField(_authDomainCtrl, 'Auth Domain', 'my-project.firebaseapp.com'),
                  _buildField(_storageBucketCtrl, 'Storage Bucket', 'my-project.appspot.com'),
                  _buildField(_measurementIdCtrl, 'Measurement ID', 'G-XXXXXXXX'),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.accentRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.accentRed.withOpacity(0.3)),
                      ),
                      child: Text(_error!, style: const TextStyle(color: AppTheme.accentRed)),
                    ),
                  ],
                  const SizedBox(height: 32),
                  HoverButton(
                    onTap: _isLoading ? null : _saveAndProceed,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppTheme.accentOrange,
                    hoverColor: AppTheme.accentOrange.withOpacity(0.8),
                    child: Center(
                      child: _isLoading
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Сохранить и продолжить', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: _skip,
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

  Widget _buildField(TextEditingController ctrl, String label, [String? hint]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: ctrl,
        validator: label.contains('*') ? (v) => v == null || v.isEmpty ? 'Обязательное поле' : null : null,
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
