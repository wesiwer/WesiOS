import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'wesi_wordmark.dart';
import 'window_controls.dart';

/// Общий заголовок модуля с опциональной кнопкой «Назад».
///
/// Back показывается только когда маршрут можно pop-нуть (открыт через
/// Navigator.pushNamed), а не когда экран живёт как вкладка IndexedStack.
class ModuleHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  const ModuleHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Padding(
      padding: EdgeInsets.fromLTRB(canPop ? 4 : 0, 0, 0, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canPop)
            IconButton(
              icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
              onPressed: () => Navigator.pop(context),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WesiTitle(title, size: 22),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (actions != null) ...actions!,
          // Резерв под системные кнопки окна
          if (kHasCustomTitleBar) const SizedBox(width: 140),
        ],
      ),
    );
  }
}
