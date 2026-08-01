import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/firebase_config_service.dart';
import '../../core/widgets/hover_button.dart';
import '../../core/widgets/vault_unlock_dialog.dart';
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
  bool _passwordSet = false;

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
      MaterialPageRoute(builder: (_) => SplashScreen()),
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
                  SizedBox(height: 40),
                  _buildField(_apiKeyCtrl, 'API Key *', 'AIzaSy...', 'API Key для доступа к Firebase services. Найдите в Project Settings > General > Web API Key.'),
                  _buildField(_appIdCtrl, 'App ID *', '1:123456789:web:abc123...', 'Уникальный ID приложения. Найдите в Project Settings > General > Your Apps > App ID.'),
                  _buildField(_projectIdCtrl, 'Project ID *', 'my-project-id', 'ID проекта Firebase. Найдите в Project Settings > General > Project ID.'),
                  _buildField(_messagingSenderIdCtrl, 'Messaging Sender ID *', '123456789', 'ID отправителя для FCM. Найдите в Project Settings > Cloud Messaging > Sender ID.'),
                  SizedBox(height: 16),
                  Text(
                    'Дополнительные поля (опционально):',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textMuted),
                  ),
                  SizedBox(height: 12),
                  _buildField(_authDomainCtrl, 'Auth Domain', 'my-project.firebaseapp.com', 'Домен для аутентификации. Автоматически генерируется Firebase.'),
                  _buildField(_storageBucketCtrl, 'Storage Bucket', 'my-project.appspot.com', 'Bucket для Cloud Storage. Найдите в Storage > Get Started.'),
                  _buildField(_measurementIdCtrl, 'Measurement ID', 'G-XXXXXXXX', 'ID для Google Analytics. Найдите в Project Settings > Integrations > Google Analytics, либо в конфиге веб-приложения.'),
                  if (_error != null) ...[
                    SizedBox(height: 16),
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.accentRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.accentRed.withOpacity(0.3)),
                      ),
                      child: Text(_error!, style: TextStyle(color: AppTheme.accentRed)),
                    ),
                  ],
                  SizedBox(height: 24),
                  _passwordOffer(),
                  SizedBox(height: 32),
                  HoverButton(
                    onTap: _isLoading ? null : _saveAndProceed,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppTheme.accentOrange,
                    hoverColor: AppTheme.accentOrange.withOpacity(0.8),
                    child: Center(
                      child: _isLoading
                        ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('Сохранить и продолжить', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                  ),
                  SizedBox(height: 16),
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

  /// Предложение сразу закрыть ключи паролем.
  ///
  /// Именно здесь это уместнее всего: ключи только что введены и лежат
  /// открытыми. Не обязательное — пропустить можно, пароль ставится позже
  /// в профиле.
  Widget _passwordOffer() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _passwordSet
              ? AppTheme.accentGreen.withOpacity(0.4)
              : AppTheme.glassBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(_passwordSet ? Icons.lock : Icons.lock_open,
              size: 18,
              color: _passwordSet
                  ? AppTheme.accentGreen
                  : AppTheme.accentOrange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _passwordSet
                      ? 'Пароль установлен'
                      : 'Защитить ключи паролем',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary),
                ),
                SizedBox(height: 2),
                Text(
                  _passwordSet
                      ? 'Ключи будут скрыты до ввода пароля. На телефоне можно открывать отпечатком.'
                      : 'Иначе ключи сможет прочитать любой, кто возьмёт разблокированное устройство.',
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.textMuted, height: 1.35),
                ),
              ],
            ),
          ),
          SizedBox(width: 8),
          TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => VaultUnlockDialog(setupMode: true),
              );
              if (ok == true && mounted) setState(() => _passwordSet = true);
            },
            child: Text(_passwordSet ? 'Сменить' : 'Задать',
                style: TextStyle(color: AppTheme.accentOrange)),
          ),
        ],
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label, [String? hint, String? tooltip]) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: ctrl,
                  validator: label.contains('*') ? (v) => v == null || v.isEmpty ? 'Обязательное поле' : null : null,
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: label,
                    hintText: hint,
                    labelStyle: TextStyle(color: AppTheme.textSecondary),
                    hintStyle: TextStyle(color: AppTheme.textMuted),
                  ),
                ),
              ),
              if (tooltip != null)
                Tooltip(
                  message: tooltip,
                  textStyle: TextStyle(color: Colors.white, fontSize: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.carbonDark.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.accentOrange.withOpacity(0.3)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.info_outline, size: 18, color: AppTheme.textMuted),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
