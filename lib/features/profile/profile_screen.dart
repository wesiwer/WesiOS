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
import '../../core/security/shield_service.dart';
import '../../core/widgets/vault_unlock_dialog.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../team/services/team_service.dart';
import 'widgets/credentials_card.dart';
import 'widgets/sync_card.dart';
import 'services/profile_service.dart';

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
  bool _applyingSyncedProfile = false;

  /// Доступ к секции ключей Firebase подтверждён в этом сеансе экрана.
  /// Намеренно не сохраняется между открытиями: закрыл профиль — снова
  /// нужен пароль.
  // Legacy Firebase vault helpers are retained for migration only.
  // ignore: unused_field
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
    ProfileService.revision.addListener(_onProfileRevision);
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
    if (_applyingSyncedProfile) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _autoSave);
  }

  Future<void> _loadAll() async {
    // Профиль мог приехать с другого устройства — раскладываем его по ключам
    // настроек до чтения, иначе экран показал бы прежние значения.
    await ProfileService.spreadToSettings();
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

  void _onProfileRevision() {
    if (!mounted || _applyingSyncedProfile) return;
    final box = Hive.box('wesios_settings');
    _applyingSyncedProfile = true;
    try {
      final idx = box.get('avatar_index');
      _selectedAvatarIndex = idx is int ? idx : 0;
      _nameCtrl.text = '${box.get('profile_name', defaultValue: '')}';
      _emailCtrl.text = '${box.get('profile_email', defaultValue: '')}';
      _gender = '${box.get('profile_gender', defaultValue: 'Не указан')}';
      _country = '${box.get('profile_country', defaultValue: 'Не указана')}';
      final birth = box.get('profile_birth');
      _birthDate =
          birth is String && birth.isNotEmpty ? DateTime.tryParse(birth) : null;
    } finally {
      _applyingSyncedProfile = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _autoSave() async {
    // Пишем через ProfileService: он кладёт профиль отдельной записью, чтобы
    // тот попал в обмен и оказался одинаковым на всех устройствах человека, и
    // заодно дублирует поля в настройки — на них смотрит остальной интерфейс.
    await ProfileService.write(
      name: _nameCtrl.text,
      email: _emailCtrl.text,
      gender: _gender,
      country: _country,
      birth: _birthDate,
      avatarIndex: _selectedAvatarIndex,
      photo: WesiAvatar.customBytes,
    );

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
    ProfileService.revision.removeListener(_onProfileRevision);
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
      locale: WesiLocale.isRussian ? Locale('ru') : const Locale('en'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppTheme.accent,
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
        padding: EdgeInsets.fromLTRB(24, kTitleBarInset + 16, 24, 32),
        children: [
          Row(
            children: [
              WesiTitle('Wesi Профиль', size: 22),
              Spacer(),
              if (_savedHint != null)
                Text(
                  _savedHint!,
                  style: TextStyle(fontSize: 12, color: AppTheme.accentGreen),
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
          _accountSection(),
          // Синхронизация — это ответ на вопрос «мои данные точно не
          // пропадут». Его задают, глядя на свой профиль, а не листая
          // настройки, поэтому состояние видно сразу и без нажатий.
          _section('Вход'),
          const ProfileCredentialsCard(),
          _section('Синхронизация'),
          const ProfileSyncCard(),
          _section('Личная информация'),
          _field(_nameCtrl, 'Имя', 'Ваше имя'),
          _field(_emailCtrl, 'Email', 'email@example.com'),
          _dropdown(
            'Дата рождения',
            _birthDate != null ? _formatDate(_birthDate!) : 'Не указана',
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
        ],
      ),
    );
  }

  /// Заглушка вместо полей, пока доступ не подтверждён.
  Widget _lockedVault() {
    return Container(
      padding: EdgeInsets.all(18),
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
              Icon(Icons.lock, size: 18, color: AppTheme.accent),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  ShieldService.isConfigured
                      ? 'Ключи защищены'
                      : 'Защитите ключи паролем',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            ShieldService.isConfigured
                ? 'Введите пароль, чтобы посмотреть или изменить ключи Firebase.'
                : 'Ключи Firebase дают доступ к бэкенду проекта. Задайте пароль, '
                    'чтобы их нельзя было прочитать с разблокированного устройства.',
            style:
                TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.4),
          ),
          SizedBox(height: 14),
          HoverButton(
            onTap: _unlockVault,
            padding: EdgeInsets.symmetric(vertical: 12),
            backgroundColor: AppTheme.accent,
            child: Center(
              child: Text(
                ShieldService.isConfigured
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
            value: ShieldService.biometricsEnabled,
            activeColor: AppTheme.accent,
            title: Text('Отпечаток или Face ID',
                style: TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
            subtitle: Text('Открывать ключи биометрией вместо ввода пароля',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            onChanged: (v) async {
              await ShieldService.setBiometricsEnabled(v);
              if (mounted) setState(() {});
            },
          ),
        TextButton(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => VaultUnlockDialog(setupMode: true),
            );
            if (ok == true && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Пароль обновлён')),
              );
            }
          },
          child:
              Text('Сменить пароль', style: TextStyle(color: AppTheme.accent)),
        ),
        // Всё остальное — автоблокировка, журнал, область защиты — живёт в
        // Wesi Shield; дублировать те же переключатели здесь значит однажды
        // разойтись с ними в поведении.
        TextButton.icon(
          onPressed: () => Navigator.pushNamed(context, '/shield'),
          icon: Icon(Icons.shield_outlined,
              size: 16, color: AppTheme.textSecondary),
          label: Text('Все настройки защиты — Wesi Shield',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ),
      ],
    );
  }

  Future<void> _unlockVault() async {
    final ok = await VaultUnlockDialog.unlock(context);
    if (ok && mounted) {
      final bio = await ShieldService.isBiometricAvailable;
      if (!mounted) return;
      setState(() {
        _vaultUnlocked = true;
        _bioAvailable = bio;
      });
    }
  }

  /// Кто вошёл, смена пароля и выход.
  ///
  /// Показывается только когда в приложении сотрудник: у владельца на своём
  /// устройстве выходить не из чего, и пункт «Выйти» без входа сбивал бы с
  /// толку.
  Widget _accountSection() {
    final me = TeamService.current;
    if (me == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Учётная запись'),
        Container(
          padding: const EdgeInsets.all(14),
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
                  Icon(Icons.badge_outlined, size: 17, color: AppTheme.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      me.displayName,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Логин: ${me.login}',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              if (me.position.isNotEmpty)
                Text(me.position,
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: HoverButton(
                      onTap: _changeOwnPassword,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      backgroundColor: AppTheme.surfaceLight,
                      child: Center(
                        child: Text('Сменить пароль',
                            style: TextStyle(
                                fontSize: 12.5, color: AppTheme.textPrimary)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: HoverButton(
                      onTap: _signOut,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      backgroundColor: AppTheme.surfaceLight,
                      child: Center(
                        child: Text('Выйти',
                            style: TextStyle(
                                fontSize: 12.5, color: AppTheme.accentRed)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _changeOwnPassword() async {
    final me = TeamService.current;
    if (me == null) return;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Новый пароль',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Не короче 8 знаков',
            hintStyle: TextStyle(color: AppTheme.textMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена', style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Сменить', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final value = ctrl.text;
    if (value.length < 8) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Пароль слишком короткий'),
            backgroundColor: AppTheme.accentRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    await TeamService.setPassword(me.id, value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пароль обновлён'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _signOut() async {
    await TeamService.signOut();
    if (mounted)
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  Widget _section(String t) => Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text(t,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
      );

  Widget _field(TextEditingController c, String label, [String? hint]) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        style: TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: AppTheme.textSecondary),
        ),
      ),
    );
  }

  Widget _fieldTip(TextEditingController c, String label, String tip) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Tooltip(
        message: tip,
        waitDuration: Duration(milliseconds: 300),
        child: TextField(
          controller: c,
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            labelText: label,
            helperText: tip,
            helperMaxLines: 2,
            helperStyle: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            labelStyle: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      ),
    );
  }

  Widget _dropdown(String label, String value, VoidCallback onTap) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                    SizedBox(height: 4),
                    Text(value,
                        style: TextStyle(
                            fontSize: 16, color: AppTheme.textPrimary)),
                  ],
                ),
              ),
              Icon(Icons.arrow_drop_down, color: AppTheme.textMuted),
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
              padding: EdgeInsets.all(16),
              child: Text(title,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
            ),
            ...items.map((item) => ListTile(
                  title:
                      Text(item, style: TextStyle(color: AppTheme.textPrimary)),
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
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          backgroundColor: AppTheme.surface,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.upload, size: 16, color: AppTheme.accent),
              SizedBox(width: 8),
              Text(
                WesiLocale.get('upload_avatar'),
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
        if (hasCustom) ...[
          SizedBox(width: 10),
          HoverButton(
            onTap: () async {
              await WesiAvatar.clearCustom();
              // Аватарка — часть профиля, и уехать должна вместе с ним.
              await ProfileService.write(
                name: _nameCtrl.text,
                email: _emailCtrl.text,
                gender: _gender,
                country: _country,
                birth: _birthDate,
                avatarIndex: _selectedAvatarIndex,
                clearPhoto: true,
              );
              if (mounted) setState(() {});
            },
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            backgroundColor: AppTheme.surface,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.restart_alt, size: 16, color: AppTheme.textMuted),
                SizedBox(width: 8),
                Text(
                  WesiLocale.get('reset_avatar'),
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
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
    await _autoSave();
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
            // Выбор пресета отменяет загруженную картинку — в записи профиля
            // тоже, иначе на другом устройстве осталась бы старая фотография.
            await ProfileService.write(
              name: _nameCtrl.text,
              email: _emailCtrl.text,
              gender: _gender,
              country: _country,
              birth: _birthDate,
              avatarIndex: index,
              clearPhoto: true,
            );
            if (mounted) setState(() {});
          },
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: preset.gradient,
              border: Border.all(
                color: sel ? AppTheme.accent : Colors.transparent,
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
