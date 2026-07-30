import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/app_version.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/currency_service.dart';
import '../tasks/services/task_service.dart';
import '../treasury/services/treasury_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/widgets/window_controls.dart';
import '../../widgets/glass_card.dart';
import 'widgets/forecast_engines_section.dart';
import 'widgets/github_auth_section.dart';
import '../../core/widgets/app_update_card.dart';
import '../../core/widgets/wesi_wordmark.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    // Все строки через WesiLocale — после смены языка setState перерисует
    final ru = WesiLocale.isRussian;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, kTitleBarInset + 16, 16, 16),
        children: [
          WesiTitle(WesiLocale.get('settings')),
          const SizedBox(height: 24),
          _section(WesiLocale.get('appearance')),
          // Тема в приложении одна. Пункт со стрелкой обещал выбор,
          // которого нет.
          _plannedTile(
            icon: Icons.dark_mode,
            title: WesiLocale.get('theme'),
            subtitle: WesiLocale.get('dark_monochrome'),
          ),
          _tile(
            icon: Icons.language,
            title: WesiLocale.get('language'),
            subtitle: WesiLocale.isRussian ? 'Русский' : 'English',
            onTap: _showLanguagePicker,
          ),
          const SizedBox(height: 24),
          _section(WesiLocale.get('notifications')),
          // Здесь стояло «включены» — про push и почту, которых в
          // приложении нет вовсе. То, что действительно работает, — это
          // колокольчик на главной, и ссылка ведёт именно туда.
          _tile(
            icon: Icons.notifications_active_outlined,
            title: ru ? 'Уведомления в приложении' : 'In-app notifications',
            subtitle: ru
                ? 'Просрочки, сроки, списания — колокольчик на главной'
                : 'Overdue, deadlines, charges — the bell on Home',
            onTap: () => Navigator.pushNamed(context, '/home'),
          ),
          _plannedTile(
            icon: Icons.notifications,
            title: WesiLocale.get('push_notifications'),
            subtitle: ru ? 'Нужен сервер' : 'Requires a server',
          ),
          _plannedTile(
            icon: Icons.email,
            title: WesiLocale.get('email_notifications'),
            subtitle: ru ? 'Нужен сервер' : 'Requires a server',
          ),
          _plannedTile(
            icon: Icons.telegram,
            title: WesiLocale.get('telegram_bot'),
            subtitle: ru ? 'Нужен сервер' : 'Requires a server',
          ),
          const SizedBox(height: 24),
          _section(WesiLocale.get('privacy')),
          // Переключатель раньше стоял мёртвым: value: false, onChanged
          // пустой. Теперь он действительно прячет суммы — по всему
          // приложению, потому что маскирование живёт в CurrencyService,
          // а не в каждом экране по отдельности.
          ValueListenableBuilder<bool>(
            valueListenable: CurrencyService.privacyMode,
            builder: (context, hidden, _) => _tile(
              icon: hidden ? Icons.visibility_off : Icons.visibility,
              title: WesiLocale.get('privacy_mode'),
              subtitle: ru
                  ? 'Суммы заменяются точками — для чужих глаз рядом'
                  : 'Amounts show as dots — for eyes over your shoulder',
              trailing: Switch(
                value: hidden,
                onChanged: CurrencyService.setPrivacyMode,
                activeColor: AppTheme.accentOrange,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _section(WesiLocale.isRussian ? 'Обновление' : 'Updates'),
          const GitHubAuthSection(),
          const AppUpdateCard(),
          const SizedBox(height: 8),
          _section(WesiLocale.get('engine_settings_section')),
          const ForecastEnginesSection(),
          const SizedBox(height: 24),
          _section(WesiLocale.get('about_app')),
          GlassCard(
            child: Column(
              children: [
                const Text(
                  'WesiOS',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  WesiLocale.get('business_os'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accentOrange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    AppVersion.display,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.accentOrange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  WesiLocale.get('created_by'),
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textMuted),
                ),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/founder'),
                  child: Text(
                    WesiLocale.get('founder_story'),
                    style: const TextStyle(color: AppTheme.accentOrange),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _section(WesiLocale.get('data')),
          _tile(
            icon: Icons.key,
            title: WesiLocale.get('firebase_config'),
            subtitle: WesiLocale.get('change_access_keys'),
            onTap: () => Navigator.pushNamed(context, '/profile'),
          ),
          _tile(
            icon: Icons.backup,
            title: WesiLocale.get('export_backup'),
            subtitle: ru
                ? 'JSON: операции, задачи, счета и ваши статьи'
                : 'JSON: operations, tasks, accounts and your articles',
            onTap: _exportBackup,
          ),
          _tile(
            icon: Icons.delete_forever,
            title: WesiLocale.get('clear_cache'),
            subtitle: WesiLocale.get('delete_local_data'),
            onTap: _clearLocalData,
            textColor: AppTheme.accentRed,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.textMuted,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
    Color? textColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.accentOrange),
      title: Text(title,
          style: TextStyle(color: textColor ?? AppTheme.textPrimary)),
      subtitle: Text(subtitle,
          style: TextStyle(
              color: (textColor ?? AppTheme.textMuted).withOpacity(0.8),
              fontSize: 13)),
      trailing: trailing ??
          const Icon(Icons.arrow_forward_ios,
              size: 14, color: AppTheme.textMuted),
      onTap: onTap,
    );
  }

  /// Пункт, которого пока нет.
  ///
  /// Стрелка справа обещает, что по нажатию что-то откроется. Раньше такие
  /// пункты нажимались и молчали, а два из них ещё и писали «включены» —
  /// про то, чего в приложении нет вовсе. Здесь вместо стрелки честная
  /// пометка, и нажимать нечего.
  Widget _plannedTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final ru = WesiLocale.isRussian;
    return ListTile(
      leading: Icon(icon, color: AppTheme.textMuted),
      title: Text(title, style: const TextStyle(color: AppTheme.textMuted)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Text(
          ru ? 'в планах' : 'planned',
          style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
        ),
      ),
    );
  }

  Future<void> _exportBackup() async {
    final ru = WesiLocale.isRussian;
    try {
      final result = await BackupService.export();
      if (!mounted) return;
      // Файл во временном каталоге: системное «поделиться» — единственный
      // способ, работающий и на Android, и на десктопе без отдельного
      // диалога сохранения под каждую платформу.
      await Share.shareXFiles(
        [XFile(result.path)],
        subject: 'WesiOS backup',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ru
                ? 'Выгружено записей: ${result.total} '
                    '(операций ${result.transactions}, задач ${result.tasks})'
                : 'Exported ${result.total} records '
                    '(${result.transactions} operations, ${result.tasks} tasks)',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ru ? 'Не удалось выгрузить: $e' : 'Export failed: $e'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
    }
  }

  Future<void> _clearLocalData() async {
    final ru = WesiLocale.isRussian;
    final count = await BackupService.countLocalRecords();
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          ru ? 'Удалить локальные данные?' : 'Delete local data?',
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 17),
        ),
        content: Text(
          ru
              ? 'Будет стёрто записей: $count — операции, задачи, счета и '
                  'ваши статьи. Отменить это нельзя. Настройки, ключи и '
                  'пароль Wesi Shield останутся.'
              : 'This deletes $count records — operations, tasks, accounts '
                  'and your articles. It cannot be undone. Settings, keys '
                  'and the Wesi Shield password stay.',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(WesiLocale.get('cancel'),
                style: const TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ru ? 'Удалить' : 'Delete',
                style: const TextStyle(color: AppTheme.accentRed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await BackupService.clearLocalData();
    // Экраны, которые слушают revision, перечитают пустые данные сами.
    TreasuryService.revision.value++;
    TaskService.revision.value++;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ru ? 'Локальные данные удалены' : 'Local data deleted')),
    );
  }

  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text(
                WesiLocale.get('select_language'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              ListTile(
                leading: const Text('🇷🇺', style: TextStyle(fontSize: 24)),
                title: const Text('Русский',
                    style: TextStyle(color: AppTheme.textPrimary)),
                trailing: WesiLocale.isRussian
                    ? const Icon(Icons.check, color: AppTheme.accentOrange)
                    : null,
                onTap: () async {
                  final nav = Navigator.of(ctx);
                  await WesiLocale.setLanguage('ru');
                  if (!mounted) return;
                  setState(() {});
                  nav.pop();
                },
              ),
              ListTile(
                leading: const Text('🇬🇧', style: TextStyle(fontSize: 24)),
                title: const Text('English',
                    style: TextStyle(color: AppTheme.textPrimary)),
                trailing: WesiLocale.isEnglish
                    ? const Icon(Icons.check, color: AppTheme.accentOrange)
                    : null,
                onTap: () async {
                  final nav = Navigator.of(ctx);
                  await WesiLocale.setLanguage('en');
                  if (!mounted) return;
                  setState(() {});
                  nav.pop();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
