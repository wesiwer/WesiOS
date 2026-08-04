import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hover_button.dart';

/// Логин и пароль нового сотрудника — показываются ОДИН раз.
///
/// Окно намеренно нельзя закрыть мимо кнопки: пароль после закрытия
/// восстановить нельзя, потому что в базе лежит только его хеш. Это цена за
/// то, что украденная база не выдаёт пароли; закрытое по неосторожности окно
/// лечится сбросом, а утёкший пароль — ничем.
class CredentialsResultDialog extends StatelessWidget {
  final String login;
  final String password;

  /// Пароль выдан заново уже существующему человеку.
  final bool isReset;

  const CredentialsResultDialog({
    super.key,
    required this.login,
    required this.password,
    this.isReset = false,
  });

  static Future<void> show(
    BuildContext context, {
    required String login,
    required String password,
    bool isReset = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CredentialsResultDialog(
        login: login,
        password: password,
        isReset: isReset,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle,
                      color: AppTheme.accentGreen, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isReset
                          ? (ru ? 'Новый пароль' : 'New password')
                          : (ru ? 'Сотрудник заведён' : 'Employee created'),
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _field(context, ru ? 'Логин' : 'Login', login),
              const SizedBox(height: 10),
              _field(context, ru ? 'Пароль' : 'Password', password),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accentRed.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(11),
                  border:
                      Border.all(color: AppTheme.accentRed.withOpacity(0.35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 17, color: AppTheme.accentRed),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        ru
                            ? 'Запишите пароль сейчас. Второй раз он не '
                                'покажется: в базе хранится не пароль, а его '
                                'отпечаток. Забыли — выдадите новый.'
                            : 'Write the password down now. It will not be '
                                'shown again: the database keeps only a hash. '
                                'If lost, issue a new one.',
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.45,
                            color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: HoverButton(
                      onTap: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: ru
                                ? 'Логин: $login\nПароль: $password'
                                : 'Login: $login\nPassword: $password',
                          ),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(ru
                                  ? 'Скопировано — передайте лично'
                                  : 'Copied — hand it over in person'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      backgroundColor: AppTheme.surfaceLight,
                      child: Center(
                        child: Text(
                          ru ? 'Скопировать' : 'Copy',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: HoverButton(
                      onTap: () => Navigator.pop(context),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      backgroundColor: AppTheme.accent,
                      child: Center(
                        child: Text(
                          ru ? 'Записал' : 'Got it',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        const SizedBox(height: 5),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLight.withOpacity(0.6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: SelectableText(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
