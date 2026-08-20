import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_telegram_icon.dart';
import 'profile_screen.dart';

/// Keeps the existing profile intact and exposes Telegram as a first-class
/// profile action without coupling ProfileScreen to the networking code.
class ProfileWithTelegram extends StatelessWidget {
  const ProfileWithTelegram({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ProfileScreen(),
        Positioned(
          right: 16,
          bottom: 16,
          child: SafeArea(
            minimum: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: Colors.transparent,
              child: FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed('/profile/telegram'),
                icon: const WesiTelegramIcon(size: 19),
                label: Text(WesiLocale.isRussian ? 'Telegram' : 'Telegram'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 8,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
