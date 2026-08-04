import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../services/topic_judge.dart';

/// Вопрос о разделении темы — прямо в ленте.
///
/// Не всплывающее окно и не уведомление: вопрос про это место разговора надо
/// задавать **в этом месте разговора**. Окно посреди экрана заставляет
/// вспоминать, о чём вообще речь.
///
/// И обязательно с объяснением, почему программа так решила. «Разделить?»
/// без причины выглядит капризом, и на него отвечают наугад.
class TopicQuestionCard extends StatelessWidget {
  final TopicQuestion question;
  final VoidCallback onSplit;
  final VoidCallback onKeep;

  const TopicQuestionCard({
    super.key,
    required this.question,
    required this.onSplit,
    required this.onKeep,
  });

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.accent.withOpacity(0.07),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppTheme.accent.withOpacity(0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_motion,
                  size: 15, color: AppTheme.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  question.ask(russian: ru),
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
          if (question.reason.trim().isNotEmpty) ...[
            const SizedBox(height: 7),
            Padding(
              padding: const EdgeInsets.only(left: 23),
              child: Text(
                ru ? 'Почему: ${question.reason}' : 'Why: ${question.reason}',
                style: TextStyle(
                    fontSize: 10.5, height: 1.35, color: AppTheme.textMuted),
              ),
            ),
          ],
          const SizedBox(height: 11),
          Row(
            children: [
              const SizedBox(width: 23),
              _button(
                ru ? 'Разделить' : 'Split',
                onSplit,
                filled: true,
              ),
              const SizedBox(width: 8),
              _button(ru ? 'Не надо' : 'Keep as is', onKeep),
            ],
          ),
        ],
      ),
    );
  }

  Widget _button(String label, VoidCallback onTap, {bool filled = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: filled
                ? AppTheme.accent.withOpacity(0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: filled
                  ? AppTheme.accent.withOpacity(0.5)
                  : AppTheme.glassBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: filled ? FontWeight.w700 : FontWeight.w400,
              color: filled ? AppTheme.accent : AppTheme.textSecondary,
            ),
          ),
        ),
      );
}
