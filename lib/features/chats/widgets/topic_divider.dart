import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/chat_message.dart';
import '../services/topic_chunker.dart';
import '../services/topic_judge.dart';

/// Заголовок блока темы в ленте.
class TopicDivider extends StatelessWidget {
  final String title;

  const TopicDivider({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppTheme.glassBorder, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.surface.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ),
          Expanded(child: Divider(color: AppTheme.glassBorder, height: 1)),
        ],
      ),
    );
  }

  /// Разметка ленты: где ставить заголовки и где спрашивать.
  ///
  /// Считается на месте, из самой переписки. Хранить разметку рядом с
  /// сообщениями было бы преждевременно: она меняется с каждым новым
  /// сообщением, и синхронизировать её пришлось бы отдельно.
  static ChatLayout planFor(List<ChatMessage> messages) {
    final input = [
      for (final m in messages)
        if (!m.isSystem)
          ChunkInput(
            id: m.id,
            text: m.isSticker ? '' : m.body,
            authorId: m.authorId,
            at: m.at,
          ),
    ];
    if (input.length < 4) return ChatLayout.empty;

    final plan = TopicChunker.plan(input);
    return ChatLayout(
      headers: {
        for (final c in plan.chunks)
          if (c.start > 0) c.start: c.title,
      },
      questions: {
        for (final b in plan.questions)
          b.index: TopicQuestion(
            index: b.index,
            suggestedTitle: _titleAfter(plan, b.index),
            reason: b.reason,
            confidence: b.confidence,
          ),
      },
    );
  }

  static String _titleAfter(ChunkPlan plan, int index) {
    for (final c in plan.chunks) {
      if (index >= c.start && index <= c.end) return c.title;
    }
    return '';
  }
}

/// Что рисовать между сообщениями.
class ChatLayout {
  final Map<int, String> headers;
  final Map<int, TopicQuestion> questions;
  final Set<int> _dismissed = {};

  ChatLayout({required this.headers, required this.questions});

  static ChatLayout get empty =>
      ChatLayout(headers: const {}, questions: const {});

  String? headerAt(int index) => headers[index];

  TopicQuestion? questionAt(int index) =>
      _dismissed.contains(index) ? null : questions[index];

  /// Человек ответил «не надо» — больше не спрашиваем.
  ///
  /// Пока экран открыт: вопрос, заданный второй раз подряд, раздражает
  /// сильнее, чем неразделённый разговор.
  void dismiss(int index) => _dismissed.add(index);
}
