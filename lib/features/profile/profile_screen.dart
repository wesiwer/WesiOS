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
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _appIdCtrl = TextEditingController();
  final _projectIdCtrl = TextEditingController();
  final _messagingSenderIdCtrl = TextEditingController();
  final _authDomainCtrl = TextEditingController();
  final _storageBucketCtrl = TextEditingController();
  final _measurementIdCtrl = TextEditingController();

  DateTime? _birthDate;
  String _gender = 'Не указан';
  String _country = 'Не указана';
  bool _isLoading = false;
  String? _error;

  final List<String> _genders = ['Не указан', 'Мужской', 'Женский'];
  final List<String> _countries = [
    'Не указана', 'Россия', 'США', 'Германия', 'Франция',
    'Великобритания', 'Китай', 'Япония', 'Другая'
  ];

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
    _nameCtrl.dispose();
    _emailCtrl.dispose();
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
        debugPrint('Firebase re-init failed: \$e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сохранено')),
        );
      }
    } catch (e) {
      setState(() => _error = 'Ошибка: \$e');
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

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.accentOrange,
              surface: AppTheme.surface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _birthDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppTheme.background.withOpacity(0.9),
            elevation: 0,
            pinned: true,
            expandedHeight: 200,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'Wesi Профиль',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppTheme.carbonDark.withOpacity(0.6),
                      AppTheme.background,
                    ],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      // Avatar
                      GestureDetector(
                        onTap: () {
                          // TODO: image picker
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppTheme.carbonDark, AppTheme.carbonMid],
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.accentOrange.withOpacity(0.4),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.accentOrange.withOpacity(0.1),
                                  blurRadius: 15,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.person_outline,
                              size: 36,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Нажмите для смены аватарки',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Personal info section
                _buildSectionTitle('Личная информация'),
                const SizedBox(height: 16),
                _buildField(_nameCtrl, 'Имя', 'Ваше имя'),
                _buildField(_emailCtrl, 'Email', 'email@example.com'),

                // Birth date
                _buildDropdownField(
                  label: 'Дата рождения',
                  value: _birthDate != null
                    ? '\${_birthDate!.day}.\${_birthDate!.month}.\${_birthDate!.year}'
                    : 'Не указана',
                  onTap: _pickBirthDate,
                ),

                // Gender
                _buildDropdownField(
                  label: 'Пол',
                  value: _gender,
                  onTap: () => _showPicker('Пол', _genders, (v) => setState(() => _gender = v)),
                ),

                // Country
                _buildDropdownField(
                  label: 'Страна',
                  value: _country,
                  onTap: () => _showPicker('Страна', _countries, (v) => setState(() => _country = v)),
                ),

                const SizedBox(height: 32),
                _buildSectionTitle('Ключи и токены'),
                const SizedBox(height: 8),
                const Text(
                  'Конфигурация Firebase проекта',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 16),

                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildField(_apiKeyCtrl, 'API Key *', 'AIzaSy...'),
                      _buildField(_appIdCtrl, 'App ID *', '1:123...'),
                      _buildField(_projectIdCtrl, 'Project ID *', 'my-project'),
                      _buildField(_messagingSenderIdCtrl, 'Messaging Sender ID *', '123456'),
                      const SizedBox(height: 16),
                      _buildField(_authDomainCtrl, 'Auth Domain'),
                      _buildField(_storageBucketCtrl, 'Storage Bucket'),
                      _buildField(_measurementIdCtrl, 'Measurement ID'),
                    ],
                  ),
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
                      : const Text('Сохранить', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
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
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
        letterSpacing: 0.3,
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

  Widget _buildDropdownField({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 16,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_drop_down,
                  color: AppTheme.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPicker(String title, List<String> items, ValueChanged<String> onSelect) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textMuted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              ...items.map((item) => ListTile(
                title: Text(item, style: const TextStyle(color: AppTheme.textPrimary)),
                trailing: (title == 'Пол' && item == _gender) || (title == 'Страна' && item == _country)
                  ? const Icon(Icons.check, color: AppTheme.accentOrange)
                  : null,
                onTap: () {
                  onSelect(item);
                  Navigator.pop(context);
                },
              )),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
