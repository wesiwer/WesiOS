import 'package:flutter/material.dart';
import '../../core/constants/app_version.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/widgets/window_controls.dart';
import '../../widgets/glass_card.dart';
import 'widgets/forecast_engines_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    // Все строки через WesiLocale — после смены языка setState перерисует
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, kTitleBarHeight + 16, 16, 16),
        children: [
          Text(
            WesiLocale.get('settings'),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 24),
          _section(WesiLocale.get('appearance')),
          _tile(
            icon: Icons.dark_mode,
            title: WesiLocale.get('theme'),
            subtitle: WesiLocale.get('dark_monochrome'),
            onTap: () {},
          ),
          _tile(
            icon: Icons.language,
            title: WesiLocale.get('language'),
            subtitle: WesiLocale.isRussian ? 'Русский' : 'English',
            onTap: _showLanguagePicker,
          ),
          const SizedBox(height: 24),
          _section(WesiLocale.get('notifications')),
          _tile(
            icon: Icons.notifications,
            title: WesiLocale.get('push_notifications'),
            subtitle: WesiLocale.get('enabled'),
            onTap: () {},
          ),
          _tile(
            icon: Icons.email,
            title: WesiLocale.get('email_notifications'),
            subtitle: WesiLocale.get('enabled'),
            onTap: () {},
          ),
          _tile(
            icon: Icons.telegram,
            title: WesiLocale.get('telegram_bot'),
            subtitle: WesiLocale.get('connect'),
            onTap: () {},
          ),
          const SizedBox(height: 24),
          _section(WesiLocale.get('privacy')),
          _tile(
            icon: Icons.visibility_off,
            title: WesiLocale.get('privacy_mode'),
            subtitle: WesiLocale.get('hide_financial_data'),
            trailing: Switch(
              value: false,
              onChanged: (_) {},
              activeColor: AppTheme.accentOrange,
            ),
          ),
          const SizedBox(height: 24),
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
            subtitle: WesiLocale.get('json_csv'),
            onTap: () {},
          ),
          _tile(
            icon: Icons.delete_forever,
            title: WesiLocale.get('clear_cache'),
            subtitle: WesiLocale.get('delete_local_data'),
            onTap: () {},
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
