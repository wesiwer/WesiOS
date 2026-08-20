import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/notifications/wesi_notifications.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/window_controls.dart';
import '../profile/telegram_link_screen.dart';

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    final background = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        title: Text(
          ru ? 'Уведомления' : 'Notifications',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, kTitleBarInset + 8, 16, 28),
          children: [
            _section(ru ? 'В приложении' : 'In app'),
            _tile(
              icon: Icons.notifications_active_outlined,
              title: ru ? 'Колокольчик на главной' : 'Home bell',
              subtitle: ru
                  ? 'Просрочки, сроки и списания остаются внутри WesiOS'
                  : 'Overdue items, deadlines and charges stay inside WesiOS',
            ),
            const SizedBox(height: 12),
            _section(ru ? 'Системные' : 'System'),
            ValueListenableBuilder<int>(
              valueListenable: WesiNotifications.revision,
              builder: (context, _, __) {
                if (!WesiNotifications.isSupported) {
                  return _plannedTile(
                    icon: Icons.notifications,
                    title: ru
                        ? 'Системные уведомления'
                        : 'System notifications',
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
                      title: ru
                          ? 'Системные уведомления'
                          : 'System notifications',
                      subtitle: ru
                          ? 'Приходят, даже когда окно свёрнуто'
                          : 'Arrive even when the window is minimised',
                      trailing: Switch(
                        value: on,
                        activeColor: AppTheme.accent,
                        onChanged: (value) async {
                          await WesiNotifications.setEnabled(value);
                          if (value) {
                            await WesiNotifications.init();
                          }
                        },
                      ),
                    ),
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
                            NotifyKind.alert => ru
                                ? 'Сроки и деньги'
                                : 'Deadlines and money',
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
                            NotifyKind.update => ru
                                ? 'Вышла новая версия'
                                : 'A new version is out',
                          },
                          trailing: Switch(
                            value: WesiNotifications.kindEnabled(kind),
                            activeColor: AppTheme.accent,
                            onChanged: (value) =>
                                WesiNotifications.setKindEnabled(kind, value),
                          ),
                        ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            _section(ru ? 'Каналы' : 'Channels'),
            _tile(
              icon: Icons.send_rounded,
              title: 'Telegram',
              subtitle: ru
                  ? 'Привязка бота и настройки уведомлений'
                  : 'Bot linking and notification settings',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const TelegramLinkScreen(),
                ),
              ),
            ),
            _plannedTile(
              icon: Icons.email,
              title: WesiLocale.get('email_notifications'),
              subtitle: ru ? 'Нужен сервер' : 'Requires a server',
            ),
          ],
        ),
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
  }) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.accent),
      title: Text(
        title,
        style: TextStyle(color: AppTheme.textPrimary),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: AppTheme.textMuted.withOpacity(0.8),
          fontSize: 13,
        ),
      ),
      trailing: trailing ??
          (onTap != null
              ? Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: AppTheme.textMuted,
                )
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
      subtitle: Text(
        subtitle,
        style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
      ),
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
}
