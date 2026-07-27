import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/glass_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionTitle('Внешний вид'),
          _buildSettingTile(
            icon: Icons.dark_mode,
            title: 'Тема',
            subtitle: 'Тёмная монохромная',
            onTap: () {},
          ),
          _buildSettingTile(
            icon: Icons.language,
            title: 'Язык',
            subtitle: 'Русский',
            onTap: () {},
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('Уведомления'),
          _buildSettingTile(
            icon: Icons.notifications,
            title: 'Push-уведомления',
            subtitle: 'Включены',
            onTap: () {},
          ),
          _buildSettingTile(
            icon: Icons.email,
            title: 'Email-уведомления',
            subtitle: 'Включены',
            onTap: () {},
          ),
          _buildSettingTile(
            icon: Icons.telegram,
            title: 'Telegram-бот',
            subtitle: 'Привязать',
            onTap: () {},
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('Конфиденциальность'),
          _buildSettingTile(
            icon: Icons.visibility_off,
            title: 'Privacy Mode',
            subtitle: 'Скрыть финансовые данные',
            trailing: Switch(
              value: false,
              onChanged: (v) {},
              activeColor: AppTheme.accentOrange,
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('Горячие клавиши'),
          _buildSettingTile(
            icon: Icons.keyboard,
            title: 'Настроить хоткеи',
            subtitle: 'Ctrl+K, Ctrl+Shift+A...',
            onTap: () {},
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('О приложении'),
          GlassCard(
            child: Column(
              children: [
                GestureDetector(
                  onLongPress: () => _showEasterEggAnimation(context),
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accentOrange.withOpacity(0.2),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/wesi_logo_easter.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'WesiOS',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Business Operating System',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accentOrange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'v1.0',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.accentOrange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Создано Wesi Inc',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/founder'),
                  child: const Text(
                    'История основателя',
                    style: TextStyle(color: AppTheme.accentOrange),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('Данные'),
          _buildSettingTile(
            icon: Icons.key,
            title: 'Firebase Config',
            subtitle: 'Изменить ключи доступа',
            onTap: () => Navigator.pushNamed(context, '/profile'),
          ),
          _buildSettingTile(
            icon: Icons.backup,
            title: 'Экспорт бэкапа',
            subtitle: 'JSON/CSV',
            onTap: () {},
          ),
          _buildSettingTile(
            icon: Icons.delete_forever,
            title: 'Очистить кэш',
            subtitle: 'Удалить локальные данные',
            onTap: () {},
            textColor: AppTheme.accentRed,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
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

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
    Color? textColor,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppTheme.accentOrange, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: textColor ?? AppTheme.primary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 13, color: textColor?.withOpacity(0.7) ?? AppTheme.textMuted),
      ),
      trailing: trailing ?? const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.textMuted),
      onTap: onTap,
    );
  }

  void _showEasterEggAnimation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 300,
          height: 300,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentOrange.withOpacity(0.5),
                blurRadius: 100,
                spreadRadius: 30,
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/images/wesi_logo_easter.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (Navigator.canPop(context)) Navigator.pop(context);
    });
  }
}
