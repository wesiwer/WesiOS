import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/firebase_config_service.dart';
import '../../core/widgets/hover_button.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final service = FirebaseConfigService();
    final config = await service.getConfig();
    if (mounted) {
      setState(() {
        _apiKeyCtrl.text = config['apiKey'] ?? '';
        _appIdCtrl.text = config['appId'] ?? '';
        _projectIdCtrl.text = config['projectId'] ?? '';
        _messagingSenderIdCtrl.text = config['messagingSenderId'] ?? '';
        _authDomainCtrl.text = config['authDomain'] ?? '';
        _storageBucketCtrl.text = config['storageBucket'] ?? '';
        _measurementIdCtrl.text = config['measurementId'] ?? '';
      });
    }
  }

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

  Future<void> _saveConfig() async {
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

      try {
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
      } catch (e) {
        debugPrint('Firebase re-init failed: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Конфигурация сохранена')),
        );
      }
    } catch (e) {
      setState(() => _error = 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _clearConfig() async {
    final service = FirebaseConfigService();
    await service.clearConfig();
    if (mounted) {
      _apiKeyCtrl.clear();
      _appIdCtrl.clear();
      _projectIdCtrl.clear();
      _messagingSenderIdCtrl.clear();
      _authDomainCtrl.clear();
      _storageBucketCtrl.clear();
      _measurementIdCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Конфигурация очищена')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Профиль и Firebase')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Firebase Configuration', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Измените ключи доступа к Firebase проекту', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 24),
              _buildField(_apiKeyCtrl, 'API Key *', 'AIzaSy...'),
              _buildField(_appIdCtrl, 'App ID *', '1:123...'),
              _buildField(_projectIdCtrl, 'Project ID *', 'my-project'),
              _buildField(_messagingSenderIdCtrl, 'Messaging Sender ID *', '123456'),
              const SizedBox(height: 16),
              Text('Дополнительно:', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _buildField(_authDomainCtrl, 'Auth Domain'),
              _buildField(_storageBucketCtrl, 'Storage Bucket'),
              _buildField(_measurementIdCtrl, 'Measurement ID'),
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
                onTap: _isLoading ? null : _saveConfig,
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: AppTheme.accentOrange,
                hoverColor: AppTheme.accentOrange.withOpacity(0.8),
                child: Center(
                  child: _isLoading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Сохранить конфигурацию', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 12),
              HoverButton(
                onTap: _clearConfig,
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: AppTheme.surface,
                hoverColor: AppTheme.accentRed.withOpacity(0.2),
                child: const Center(
                  child: Text('Очистить конфигурацию', style: TextStyle(color: AppTheme.accentRed)),
                ),
              ),
            ],
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
