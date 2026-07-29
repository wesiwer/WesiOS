import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/data/countries.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/services/firebase_config_service.dart';
import '../../core/widgets/hover_button.dart';
import '../../core/widgets/wesi_avatar.dart';
import '../../core/widgets/window_controls.dart';
import '../../core/services/vault_lock_service.dart';
import '../../core/widgets/vault_unlock_dialog.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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
  int _selectedAvatarIndex = 0;
  String? _savedHint;
  Timer? _debounce;

  /// Доступ к секции ключей Firebase подтверждён в этом сеансе экрана.
  /// Намеренно не сохраняется между открытиями: закрыл профиль — снова
  /// нужен пароль.
  bool _vaultUnlocked = false;
  bool _bioAvailable = false;

  final List<String> _genders = ['Не указан', 'Мужской', 'Женский'];
  /// Полный список стран. При русском интерфейсе Россия и соседи идут
  /// первыми — искать свою страну в середине алфавита неудобно.
  List<String> get _countries => Countries.all;

  @override
  void initState() {
    super.initState();
    _loadAll();
    for (final c in [
      _nameCtrl,
      _emailCtrl,
      _apiKeyCtrl,
      _appIdCtrl,
      _projectIdCtrl,
      _messagingSenderIdCtrl,
      _authDomainCtrl,
      _storageBucketCtrl,
      _measurementIdCtrl,
    ]) {
      c.addListener(_scheduleSave);
    }
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _autoSave);
  }

  Future<void> _loadAll() async {
    final box = Hive.box('wesios_settings');
    final idx = box.get('avatar_index');
    if (idx != null) {
      _selectedAvatarIndex = idx as int;
    }
    _nameCtrl.text = box.get('profile_name', defaultValue: '') as String;
    _emailCtrl.text = box.get('profile_email', defaultValue: '') as String;
    _gender = box.get('profile_gender', defaultValue: 'Не указан') as String;
    _country = box.get('profile_country', defaultValue: 'Не указана') as String;
    final bd = box.get('profile_birth');
    if (bd is String && bd.isNotEmpty) {
      _birthDate = DateTime.tryParse(bd);
    }

    final service = FirebaseConfigService();
    final config = await service.getConfig();
    _apiKeyCtrl.text = config['apiKey'] ?? '';
    _appIdCtrl.text = config['appId'] ?? '';
    _projectIdCtrl.text = config['projectId'] ?? '';
    _messagingSenderIdCtrl.text = config['messagingSenderId'] ?? '';
    _authDomainCtrl.text = config['authDomain'] ?? '';
    _storageBucketCtrl.text = config['storageBucket'] ?? '';
    _measurementIdCtrl.text = config['measurementId'] ?? '';

    if (mounted) setState(() {});
  }

  Future<void> _autoSave() async {
    final box = Hive.box('wesios_settings');
    await box.put('profile_name', _nameCtrl.text.trim());
    await box.put('profile_email', _emailCtrl.text.trim());
    await box.put('profile_gender', _gender);
    await box.put('profile_country', _country);
    if (_birthDate != null) {
      await box.put('profile_birth', _birthDate!.toIso8601String());
    }

    // Firebase keys — сохраняем если есть обязательные
    if (_apiKeyCtrl.text.trim().isNotEmpty &&
        _appIdCtrl.text.trim().isNotEmpty &&
        _projectIdCtrl.text.trim().isNotEmpty &&
        _messagingSenderIdCtrl.text.trim().isNotEmpty) {
      try {
        final service = FirebaseConfigService();
        await service.saveConfig(
          apiKey: _apiKeyCtrl.text.trim(),
          appId: _appIdCtrl.text.trim(),
          messagingSenderId: _messagingSenderIdCtrl.text.trim(),
          projectId: _projectIdCtrl.text.trim(),
          authDomain: _authDomainCtrl.text.trim().isEmpty
              ? null
              : _authDomainCtrl.text.trim(),
          storageBucket: _storageBucketCtrl.text.trim().isEmpty
              ? null
              : _storageBucketCtrl.text.trim(),
          measurementId: _measurementIdCtrl.text.trim().isEmpty
              ? null
              : _measurementIdCtrl.text.trim(),
        );
      } catch (e) {
        debugPrint('auto-save firebase: $e');
      }
    }

    if (mounted) {
      setState(() => _savedHint = 'Сохранено');
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) setState(() => _savedHint = null);
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [
      _nameCtrl,
      _emailCtrl,
      _apiKeyCtrl,
      _appIdCtrl,
      _projectIdCtrl,
      _messagingSenderIdCtrl,
      _authDomainCtrl,
      _storageBucketCtrl,
      _measurementIdCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      // Календарь на языке приложения. Без явной локали Flutter показывает
      // системную, из-за чего при русском интерфейсе месяцы и кнопки
      // оставались английскими.
      locale: WesiLocale.isRussian ? const Locale('ru') : const Locale('en'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.accentOrange,
              onPrimary: AppTheme.background,
              surface: AppTheme.surface,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _birthDate = picked);
      _scheduleSave();
    }
  }

  /// Дата в формате дд.мм.гггг — с ведущими нулями (09.07.2004), а не
  /// 9.7.2004: без них дата читается как небрежность.
  static String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: ListView(
        padding: EdgeInsets.fromLTRB(24, kTitleBarHeight + 16, 24, 32),
        children: [
          Row(
            children: [
              const Text(
                'Wesi Профиль',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              if (_savedHint != null)
                Text(
                  _savedHint!,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.accentGreen),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Center(child: WesiAvatar(size: 100, showBorder: true)),
          const SizedBox(height: 16),
          _avatarGrid(),
          const SizedBox(height: 12),
          _avatarActions(),
          const SizedBox(height: 28),
          _section('Личная информация'),
          _field(_nameCtrl, 'Имя', 'Ваше имя'),
          _field(_emailCtrl, 'Email', 'email@example.com'),
          _dropdown(
            'Дата рождения',
            _birthDate != null
                ? _formatDate(_birthDate!)
                : 'Не указана',
            _pickBirthDate,
          ),
          _dropdown(
            'Пол',
            _gender,
            () => _picker('Пол', _genders, (v) {
              setState(() => _gender = v);
              _scheduleSave();
            }),
          ),
          _dropdown(
            'Страна',
            _country,
            () => _picker('Страна', _countries, (v) {
              setState(() => _country = v);
              _scheduleSave();
            }),
          ),
          const SizedBox(height: 24),
          _section('Ключи Firebase (автосохранение)'),
          // Ключи Firebase — это доступ к бэкенду проекта, поэтому секция
          // закрыта: значения не рисуются, пока не подтвердили пароль
          // (или отпечаток/Face ID на телефоне).
          if (!_vaultUnlocked) _lockedVault(),
          if (_vaultUnlocked) ...[
          const Text(
            'Наведи на поле — подсказка где взять значение. Сохраняется само.',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 12),
          _fieldTip(
              _apiKeyCtrl,
              'API Key *',
              'Firebase Console → Project settings → Your apps → apiKey'),
          _fieldTip(
              _appIdCtrl,
              'App ID *',
              'Firebase Console → Project settings → Your apps → appId'),
          _fieldTip(
              _projectIdCtrl,
              'Project ID *',
              'Firebase Console → Project settings → Project ID'),
          _fieldTip(
              _messagingSenderIdCtrl,
              'Messaging Sender ID *',
              'Firebase Console → Project settings → Cloud Messaging'),
          _fieldTip(_authDomainCtrl, 'Auth Domain',
              'Обычно project-id.firebaseapp.com'),
          _fieldTip(_storageBucketCtrl, 'Storage Bucket',
              'Обычно project-id.appspot.com'),
          _fieldTip(_measurementIdCtrl, 'Measurement ID',
              'Analytics → Measurement ID (G-...)'),
          const SizedBox(height: 16),
          HoverButton(
            onTap: () async {
              final service = FirebaseConfigService();
              await service.clearConfig();
              _apiKeyCtrl.clear();
              _appIdCtrl.clear();
              _projectIdCtrl.clear();
              _messagingSenderIdCtrl.clear();
              _authDomainCtrl.clear();
              _storageBucketCtrl.clear();
              _measurementIdCtrl.clear();
            },
            padding: const EdgeInsets.symmetric(vertical: 14),
            backgroundColor: AppTheme.surface,
            child: const Center(
              child: Text('Очистить Firebase-ключи',
                  style: TextStyle(color: AppTheme.accentRed)),
            ),
          ),
          const SizedBox(height: 12),
          _vaultOptions(),
          ],
        ],
      ),
    );
  }

  /// Заглушка вместо полей, пока доступ не подтверждён.
  Widget _lockedVault() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock, size: 18, color: AppTheme.accentOrange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  VaultLockService.isConfigured
                      ? 'Ключи защищены'
                      : 'Защитите ключи паролем',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            VaultLockService.isConfigured
                ? 'Введите пароль, чтобы посмотреть или изменить ключи Firebase.'
                : 'Ключи Firebase дают доступ к бэкенду проекта. Задайте пароль, '
                    'чтобы их нельзя было прочитать с разблокированного устройства.',
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textMuted, height: 1.4),
          ),
          const SizedBox(height: 14),
          HoverButton(
            onTap: _unlockVault,
            padding: const EdgeInsets.symmetric(vertical: 12),
            backgroundColor: AppTheme.accentOrange,
            child: Center(
              child: Text(
                VaultLockService.isConfigured
                    ? 'Разблокировать'
                    : 'Создать пароль',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Управление замком, когда доступ уже получен.
  Widget _vaultOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_bioAvailable)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: VaultLockService.biometricsEnabled,
            activeColor: AppTheme.accentOrange,
            title: const Text('Отпечаток или Face ID',
                style: TextStyle(
                    fontSize: 14, color: AppTheme.textPrimary)),
            subtitle: const Text(
                'Открывать ключи биометрией вместо ввода пароля',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            onChanged: (v) async {
              await VaultLockService.setBiometricsEnabled(v);
              if (mounted) setState(() {});
            },
          ),
        TextButton(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => const VaultUnlockDialog(setupMode: true),
            );
            if (ok == true && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Пароль обновлён')),
              );
            }
          },
          child: const Text('Сменить пароль',
              style: TextStyle(color: AppTheme.accentOrange)),
        ),
      ],
    );
  }

  Future<void> _unlockVault() async {
    final ok = await VaultUnlockDialog.unlock(context);
    if (ok && mounted) {
      final bio = await VaultLockService.isBiometricAvailable;
      if (!mounted) return;
      setState(() {
        _vaultUnlocked = true;
        _bioAvailable = bio;
      });
    }
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(t,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
      );

  Widget _field(TextEditingController c, String label, [String? hint]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: AppTheme.textSecondary),
        ),
      ),
    );
  }

  Widget _fieldTip(TextEditingController c, String label, String tip) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Tooltip(
        message: tip,
        waitDuration: const Duration(milliseconds: 300),
        child: TextField(
          controller: c,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            labelText: label,
            helperText: tip,
            helperMaxLines: 2,
            helperStyle:
                const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            labelStyle: const TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      ),
    );
  }

  Widget _dropdown(String label, String value, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                    Text(label,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 4),
                    Text(value,
                        style: const TextStyle(
                            fontSize: 16, color: AppTheme.textPrimary)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_drop_down, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  void _picker(
      String title, List<String> items, ValueChanged<String> onSelect) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
            ),
            ...items.map((item) => ListTile(
                  title: Text(item,
                      style: const TextStyle(color: AppTheme.textPrimary)),
                  onTap: () {
                    onSelect(item);
                    Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// Загрузка своей аватарки + возврат к пресетам.
  Widget _avatarActions() {
    final hasCustom = WesiAvatar.hasCustom;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        HoverButton(
          onTap: _pickCustomAvatar,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          backgroundColor: AppTheme.surface,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.upload, size: 16, color: AppTheme.accentOrange),
              const SizedBox(width: 8),
              Text(
                WesiLocale.get('upload_avatar'),
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
        if (hasCustom) ...[
          const SizedBox(width: 10),
          HoverButton(
            onTap: () async {
              await WesiAvatar.clearCustom();
              if (mounted) setState(() {});
            },
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            backgroundColor: AppTheme.surface,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.restart_alt,
                    size: 16, color: AppTheme.textMuted),
                const SizedBox(width: 8),
                Text(
                  WesiLocale.get('reset_avatar'),
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickCustomAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true, // нужны байты: складываем картинку в Hive
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    await WesiAvatar.setCustom(bytes);
    if (mounted) setState(() {});
  }

  Widget _avatarGrid() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: List.generate(WesiAvatar.avatarPresets.length, (index) {
        final preset = WesiAvatar.avatarPresets[index];
        final sel = index == _selectedAvatarIndex && !WesiAvatar.hasCustom;
        return GestureDetector(
          onTap: () async {
            setState(() => _selectedAvatarIndex = index);
            await WesiAvatar.setIndex(index);
            if (mounted) setState(() {});
          },
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: preset.gradient,
              border: Border.all(
                color: sel ? AppTheme.accentOrange : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: Center(
              child: IconTheme(
                data: const IconThemeData(size: 22),
                child: preset.icon,
              ),
            ),
          ),
        );
      }),
    );
  }
}
