import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../models/probe_result.dart';

/// Точка состояния.
///
/// Цвета отличаются не только оттенком, но и формой значка внутри: восемь
/// процентов мужчин не различают красный и зелёный, и экран, где состояние
/// передаётся одним лишь цветом, для них не показывает ничего.
class HealthDot extends StatelessWidget {
  final HealthGrade grade;
  final double size;

  const HealthDot({super.key, required this.grade, this.size = 12});

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    final (color, icon, label) = switch (grade) {
      HealthGrade.good => (
          AppTheme.accentGreen,
          Icons.check,
          ru ? 'Работает' : 'Healthy',
        ),
      HealthGrade.degraded => (
          AppTheme.accent,
          Icons.priority_high,
          ru ? 'Отвечает с перебоями' : 'Degraded',
        ),
      HealthGrade.down => (
          AppTheme.accentRed,
          Icons.close,
          ru ? 'Не отвечает' : 'Down',
        ),
      HealthGrade.offline => (
          AppTheme.textMuted,
          Icons.wifi_off,
          ru ? 'Нет сети на устройстве' : 'This device is offline',
        ),
      HealthGrade.unknown => (
          AppTheme.textMuted,
          Icons.more_horiz,
          ru ? 'Ещё не проверяли' : 'Not checked yet',
        ),
    };

    return Tooltip(
      message: label,
      child: Container(
        width: size + 8,
        height: size + 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.16),
          border: Border.all(color: color.withOpacity(0.55), width: 1.2),
        ),
        child: Icon(icon, size: size * 0.72, color: color),
      ),
    );
  }
}
