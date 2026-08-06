import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/feedback/wesi_feedback.dart';
import '../../core/notifications/wesi_notifications.dart';
import '../../core/constants/app_version.dart';
import '../../core/services/app_icon_service.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/currency_service.dart';
import '../tasks/services/task_service.dart';
import '../treasury/services/treasury_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/widgets/module_header.dart';
import '../../core/widgets/window_controls.dart';
import '../../widgets/glass_card.dart';
import '../../core/sync/sync_endpoint.dart';
import '../../core/sync/sync_engine.dart';
import '../chats/services/topic_privacy.dart';
import 'sync_screen.dart';
import 'widgets/forecast_engines_section.dart';
import 'widgets/github_auth_section.dart';
import '../../core/widgets/app_update_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, mode, _) {
        final bg = Theme.of(context).scaffoldBackgroundColor;
        return Scaffold(
          backgroundColor: bg,
          body: ListView(
            padding: EdgeInsets.fromLTRB(16, kTitleBarInset + 16, 16, 16),
            children: [
              ModuleHeader(title: WesiLocale.get('settings')),
              const SizedBox(height: 24),
              _section(WesiLocale.get('appearance')),
              ValueListenableBuilder<AppThemeMode>(
                valueListenable: ThemeNotifier.instance,
                builder: (context, themeMode, _) {
                  final isDark = themeMode == AppThemeMode.dark;
                  return _tile(
                    icon: isDark ? Icons.dark_mode : Icons.light_mode,
                    title: WesiLocale.get('theme'),
                    subtitle: isDark
                        ? (ru ? 'Тёмная' : 'Dark')
                        : (ru ? 'Светлая' : 'Light'),
                    trailing: Switch(
                      value: !isDark,
                      onChanged: (light) {
                        if (light) {
                          ThemeNotifier.instance.setLight();
                        } else {
                          ThemeNotifier.instance.setDark();
                        }
                      },
                    ),
                  );
                },
              ),
              ValueListenableBuilder<AppIconMode>(
                valueListenable: AppIconService.mode,
                builder: (context, iconMode, _) {
                  final subtitle = switch (iconMode) {
                    AppIconMode.auto => ru
                        ? 'Авто — вместе с темой'
                        : 'Auto — follows theme',
                    AppIconMode.dark =>
                      ru ? 'Тёмная (чёрный фон)' : 'Dark (black background)',
                    AppIconMode.light =>
                      ru ? 'Светлая (белый фон)' : 'Light (white background)',
                  };
                  return _tile(
                    icon: Icons.apps,
                    title: ru ? 'Иконка приложения' : 'App icon',
                    subtitle: AppIconService.isSupported
                        ? subtitle
                        : (ru
                            ? 'Смена иконки доступна на Android'
                            : 'Icon change is available on Android'),
                    onTap: AppIconService.isSupported ? _showIconPicker : null,
                    trailing: AppIconService.isSupported
                        ? Icon(Icons.arrow_forward_ios,
                            size: 14, color: AppTheme.textMuted)
                        : null,
                  );
                },
              ),
              _tile(
                icon: Icons.language,
                title: WesiLocale.get('language'),
                subtitle: WesiLocale.isRussian ? 'Русский' : 'English',
                onTap: _showLanguagePicker,
              ),
              const SizedBox(height: 24),
              _section(ru ? 'Отклик' : 'Feedback'),
              // Показывается только то, что это устройство умеет. Вибрация
              // на настольном компьютере и звуковые щелчки в кармане — это
              // не «на всякий случай», это обещание того, чего не будет.
              if (WesiFeedback.supportsHaptics || WesiFeedback.supportsSound)
                ValueListenableBuilder<int>(
                  valueListenable: WesiFeedback.revision,
                  builder: (context, _, __) => Column(
                    children: [
                      if (WesiFeedback.supportsHaptics)
                        _tile(
                          icon: Icons.vibration,
                          title: ru ? 'Тактильный отклик' : 'Haptics',
                          subtitle: ru
                              ? 'Короткая отдача на нажатие, отправку и ошибку'
                              : 'A short buzz on taps, sends and errors',
                          trailing: Switch(
                            value: WesiFeedback.haptics,
                            activeColor: AppTheme.accent,
                            onChanged: (v) async {
                              await WesiFeedback.setHaptics(v);
                              // Пробный отклик сразу: переключатель, который
                              // ничего не делает в момент нажатия, проверяют
                              // потом и не находят.
                              if (v) WesiFeedback.success();
                            },
                          ),
                        ),
                      if (WesiFeedback.supportsSound)
                        _tile(
                          icon: Icons.volume_up_outlined,
                          title: ru ? 'Звуки' : 'Sounds',
                          subtitle: ru
                              ? 'Тихие короткие сигналы на действия'
                              : 'Quiet short cues for actions',
                          trailing: Switch(
                            value: WesiFeedback.sound,
                            activeColor: AppTheme.accent,
                            onChanged: (v) async {
                              await WesiFeedback.setSound(v);
                              if (v) WesiFeedback.success();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              _section(WesiLocale.get('notifications')),
              _tile(
                icon: Icons.notifications_active_outlined,
                title: ru ? 'Уведомления в приложении' : 'In-app notifications',
                subtitle: ru
                    ? 'Просрочки, сроки, списания — колокольчик на главной'
                    : 'Overdue, deadlines, charges — the bell on Home',
                onTap: () => Navigator.pushNamed(context, '/home'),
              ),
              // Системные уведомления. Раньше здесь стояла заглушка
              // «нужен сервер» — она была неправдой: сообщать о просрочке,
              // списании и пришедшем сообщении можно и с самого устройства,
              // сервер нужен только для доставки в закрытое приложение.
              ValueListenableBuilder<int>(
                valueListenable: WesiNotifications.revision,
                builder: (context, _, __) {
                  if (!WesiNotifications.isSupported) {
                    return _plannedTile(
                      icon: Icons.notifications,
                      title: ru ? 'Системные уведомления' : 'System notifications',
                      subtitle: ru
                          ? 'Эта платформа их не показывает'
                          : 'Not available on this platform',
                    );
                  }
                  final on = WesiNotifications.enabled;
                  return Column(
                    children: [
                      _tile(
                        icon: Icons.notifications,
                        title: ru ? 'Системные уведомления' : 'System notifications',
                        subtitle: ru
                            ? 'Приходят, даже когда окно свёрнуто'
                            : 'Arrive even when the window is minimised',
                        trailing: Switch(
                          value: on,
                          activeColor: AppTheme.accent,
                          onChanged: (v) async {
                            await WesiNotifications.setEnabled(v);
                            if (v) await WesiNotifications.init();
                          },
                        ),
                      ),
                      // Виды показываются только при включённом главном:
                      // четыре переключателя под выключенным — это четыре
                      // настройки, которые ничего не делают.
                      if (on)
                        for (final kind in NotifyKind.values)
                          _tile(
                            icon: switch (kind) {
                              NotifyKind.alert => Icons.warning_amber_outlined,
                              NotifyKind.message => Icons.chat_bubble_outline,
                              NotifyKind.sync => Icons.sync_problem,
                              NotifyKind.update => Icons.system_update_alt,
                            },
                            title: switch (kind) {
                              NotifyKind.alert =>
                                ru ? 'Сроки и деньги' : 'Deadlines and money',
                              NotifyKind.message =>
                                ru ? 'Сообщения' : 'Messages',
                              NotifyKind.sync =>
                                ru ? 'Сбои обмена' : 'Sync failures',
                              NotifyKind.update =>
                                ru ? 'Обновления' : 'Updates',
                            },
                            subtitle: switch (kind) {
                              NotifyKind.alert => ru
                                  ? 'Просрочки, ближайшие списания, минус на счету'
                                  : 'Overdue, upcoming charges, negative balance',
                              NotifyKind.message => ru
                                  ? 'Пришедшее в переписке'
                                  : 'Incoming messages',
                              NotifyKind.sync => ru
                                  ? 'Когда данные не уехали на сервер'
                                  : 'When data did not reach the server',
                              NotifyKind.update =>
                                ru ? 'Вышла новая версия' : 'A new version is out',
                            },
                            trailing: Switch(
                              value: WesiNotifications.kindEnabled(kind),
                              activeColor: AppTheme.accent,
                              onChanged: (v) =>
                                  WesiNotifications.setKindEnabled(kind, v),
                            ),
                          ),
                    ],
                  );
                },
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
                  ),
                ),
              ),
              // Куда уходит переписка ради разбиения на темы. Решение
              // владельца, и оно должно приниматься здесь, глазами, а не
              // подразумеваться кодом.
              ValueListenableBuilder<int>(
                valueListenable: TopicPrivacy.revision,
                builder: (context, _, __) => _topicPrivacyTile(ru),
              ),
              const SizedBox(height: 24),
              _section(WesiLocale.isRussian ? 'Обновление' : 'Updates'),
              const GitHubAuthSection(),
              const AppUpdateCard(),
              const SizedBox(height: 8),
              _section(WesiLocale.get('engine_settings_section')),
              ForecastEnginesSection(),
              const SizedBox(height: 24),
              _section(WesiLocale.get('about_app')),
              GlassCard(
                child: Column(
                  children: [
                    Text(
                      'WesiOS',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      WesiLocale.get('business_os'),
                      style: TextStyle(
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
                        color: AppTheme.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        AppVersion.display,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      WesiLocale.get('created_by'),
                      style:
                          TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/founder'),
                      child: Text(
                        WesiLocale.get('founder_story'),
                        style: TextStyle(color: AppTheme.accent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _section(WesiLocale.get('data')),
              // Подпись живая: если пропуск протух или последний обмен
              // сорвался, это должно быть видно из настроек, а не только
              // после захода на экран синхронизации.
              ValueListenableBuilder<SyncReport?>(
                valueListenable: SyncEngine.lastReport,
                builder: (context, report, _) => ValueListenableBuilder<int>(
                  valueListenable: SyncEndpoint.revision,
                  builder: (context, _, __) => _tile(
                    icon: Icons.sync,
                    title: ru ? 'Синхронизация' : 'Sync',
                    subtitle: _syncSubtitle(report, ru),
                    onTap: () => SyncScreen.open(context),
                    textColor: report != null && !report.ok
                        ? AppTheme.accentRed
                        : null,
                  ),
                ),
              ),
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
      },
    );
  }

  String _syncSubtitle(SyncReport? report, bool ru) {
    if (SyncEndpoint.session == null) {
      return ru
          ? 'Свой сервер: данные на всех устройствах'
          : 'Your own server: data on every device';
    }
    if (report != null && !report.ok) {
      return report.describe(russian: ru);
    }
    final last = SyncEndpoint.lastRun;
    if (last == null) return ru ? 'Обмена ещё не было' : 'No exchange yet';
    final l = last.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final when = '${two(l.day)}.${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
    return ru ? 'Последний обмен: $when' : 'Last exchange: $when';
  }

  /// Выбор режима разметки тем.
  ///
  /// Три пункта, а не переключатель «вкл/выкл»: средний вариант — своя
  /// модель на своём сервере — и есть тот, который обычно нужен, а из
  /// двоичного переключателя он выпадает.
  Widget _topicPrivacyTile(bool ru) {
    final mode = TopicPrivacy.mode;
    return ListTile(
      leading: Icon(Icons.workspaces_outline, color: AppTheme.accent),
      title: Text(
        ru ? 'Разбиение чатов на темы' : 'Chat topic detection',
        style: TextStyle(color: AppTheme.textPrimary),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            TopicPrivacy.hintRu(mode),
            style: TextStyle(
                fontSize: 12, height: 1.35, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final m in TopicPrivacyMode.values)
                GestureDetector(
                  onTap: () async {
                    await TopicPrivacy.setMode(m);
                    if (mounted) setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: m == mode
                          ? AppTheme.accent.withOpacity(0.16)
                          : AppTheme.surface.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: m == mode
                            ? AppTheme.accent.withOpacity(0.55)
                            : AppTheme.glassBorder,
                      ),
                    ),
                    child: Text(
                      TopicPrivacy.labelRu(m),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight:
                            m == mode ? FontWeight.w700 : FontWeight.w400,
                        color: m == mode
                            ? AppTheme.accent
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
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
      leading: Icon(icon, color: AppTheme.accent),
      title: Text(title,
          style: TextStyle(color: textColor ?? AppTheme.textPrimary)),
      subtitle: Text(subtitle,
          style: TextStyle(
              color: (textColor ?? AppTheme.textMuted).withOpacity(0.8),
              fontSize: 13)),
      trailing: trailing ??
          (onTap != null
              ? Icon(Icons.arrow_forward_ios,
                  size: 14, color: AppTheme.textMuted)
              : null),
      onTap: onTap,
    );
  }

  Widget _plannedTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final ru = WesiLocale.isRussian;
    return ListTile(
      leading: Icon(icon, color: AppTheme.textMuted),
      title: Text(title, style: TextStyle(color: AppTheme.textMuted)),
      subtitle: Text(subtitle,
          style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Text(
          ru ? 'в планах' : 'planned',
          style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
        ),
      ),
    );
  }

  void _showIconPicker() {
    final ru = WesiLocale.isRussian;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ValueListenableBuilder<AppIconMode>(
            valueListenable: AppIconService.mode,
            builder: (context, current, _) {
              Widget option({
                required AppIconMode value,
                required IconData icon,
                required String title,
                required String subtitle,
              }) {
                final selected = current == value;
                return ListTile(
                  leading: Icon(icon,
                      color: selected ? AppTheme.accent : AppTheme.textMuted),
                  title: Text(title,
                      style: TextStyle(color: AppTheme.textPrimary)),
                  subtitle: Text(subtitle,
                      style: TextStyle(
                          color: AppTheme.textMuted, fontSize: 13)),
                  trailing: selected
                      ? Icon(Icons.check, color: AppTheme.accent)
                      : null,
                  onTap: () async {
                    final nav = Navigator.of(ctx);
                    await AppIconService.setMode(value);
                    if (!mounted) return;
                    nav.pop();
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ru
                              ? 'Иконка обновлена. На части лаунчеров смена видна через несколько секунд.'
                              : 'Icon updated. On some launchers it may take a few seconds.',
                        ),
                      ),
                    );
                  },
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    ru ? 'Иконка приложения' : 'App icon',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.accent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      ru
                          ? 'Тёмная — чёрный фон и белый знак. Светлая — белый фон и серо-синий знак.'
                          : 'Dark — black background, white mark. Light — white background, slate-blue mark.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ),
                  option(
                    value: AppIconMode.auto,
                    icon: Icons.brightness_auto,
                    title: ru ? 'Авто' : 'Auto',
                    subtitle: ru
                        ? 'Меняется вместе с темой приложения'
                        : WesiLocale.get('theme_changes_with_app'),
                  ),
                  option(
                    value: AppIconMode.dark,
                    icon: Icons.dark_mode,
                    title: ru ? 'Тёмная' : 'Dark',
                    subtitle:
                        ru ? 'Всегда чёрный фон' : 'Always black background',
                  ),
                  option(
                    value: AppIconMode.light,
                    icon: Icons.light_mode,
                    title: ru ? 'Светлая' : 'Light',
                    subtitle:
                        ru ? 'Всегда белый фон' : 'Always white background',
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _exportBackup() async {
    final ru = WesiLocale.isRussian;
    try {
      final result = await BackupService.export();
      if (!mounted) return;
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
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 17),
        ),
        content: Text(
          ru
              ? 'Будет стёрто записей: $count — операции, задачи, счета и '
                  'ваши статьи. Отменить это нельзя. Настройки, ключи и '
                  'пароль Wesi Shield останутся.'
              : 'This deletes $count records — operations, tasks, accounts '
                  'and your articles. It cannot be undone. Settings, keys '
                  'and the Wesi Shield password stay.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(WesiLocale.get('cancel'),
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ru ? 'Удалить' : 'Delete',
                style: TextStyle(color: AppTheme.accentRed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await BackupService.clearLocalData();
    TreasuryService.revision.value++;
    TaskService.revision.value++;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(ru ? 'Локальные данные удалены' : 'Local data deleted')),
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
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              ListTile(
                leading: const Text('🇷🇺', style: TextStyle(fontSize: 24)),
                title: Text('Русский',
                    style: TextStyle(color: AppTheme.textPrimary)),
                trailing: WesiLocale.isRussian
                    ? Icon(Icons.check, color: AppTheme.accent)
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
                title: Text('English',
                    style: TextStyle(color: AppTheme.textPrimary)),
                trailing: WesiLocale.isEnglish
                    ? Icon(Icons.check, color: AppTheme.accent)
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
