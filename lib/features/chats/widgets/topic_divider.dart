import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/chat_message.dart';
import '../services/topic_chunker.dart';
import '../services/topic_judge.dart';
import '../services/topic_refiner.dart';

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
    final prepared = prepare(messages);
    if (prepared == null) return _manualOnly(messages);

    final plan = TopicChunker.plan(prepared.input);
    return _withManual(
      messages,
      ChatLayout(
        headers: {
          for (final c in plan.chunks)
            if (c.start > 0) prepared.toMessage(c.start): c.title,
        },
        questions: {
          for (final b in plan.questions)
            prepared.toMessage(b.index): TopicQuestion(
              index: prepared.toMessage(b.index),
              suggestedTitle: _titleAfter(plan, b.index),
              reason: b.reason,
              confidence: b.confidence,
            ),
        },
      ),
    );
  }

  /// Границы, поставленные человеком, — поверх всего остального.
  ///
  /// **Это и есть смысл кнопки «Разделить».** Раньше она записывала метку
  /// темы на сообщения, а разметку никто по этой метке не строил: в
  /// хранилище что-то менялось, на экране — ничего. Со стороны человека
  /// кнопка просто не работала.
  ///
  /// Решение человека главнее алгоритма: где он разделил — там граница, и
  /// спрашивать об этом месте больше не о чем.
  static ChatLayout _withManual(List<ChatMessage> messages, ChatLayout auto) {
    final manual = _manualBoundaries(messages);
    if (manual.isEmpty) return auto;

    final headers = Map<int, String>.from(auto.headers)..addAll(manual);
    final questions =
        Map<int, TopicQuestion>.from(auto.questions)
          // Место, про которое уже решили, второй раз не обсуждаем.
          ..removeWhere((at, _) => manual.containsKey(at));

    return ChatLayout(
      headers: headers,
      questions: questions,
      judgedBy: auto.judgedBy,
    );
  }

  /// Разметка, когда автоматической нет вовсе (переписка ещё короткая), но
  /// человек уже что-то разделил руками.
  static ChatLayout _manualOnly(List<ChatMessage> messages) {
    final manual = _manualBoundaries(messages);
    return manual.isEmpty
        ? ChatLayout.empty
        : ChatLayout(headers: manual, questions: const {});
  }

  /// `позиция в ленте → название блока` для границ, расставленных человеком.
  ///
  /// Граница там, где метка темы сменилась относительно предыдущего
  /// сообщения. Название считается тем же способом, что и у обычных кусков,
  /// — иначе разделённые вручную блоки выглядели бы чужими среди остальных.
  static Map<int, String> _manualBoundaries(List<ChatMessage> messages) {
    final out = <int, String>{};
    String? previous;

    for (var i = 0; i < messages.length; i++) {
      final topic = messages[i].topicId;
      if (i > 0 && topic != previous && topic != null) {
        out[i] = _titleOfRange(messages, i, _endOfBlock(messages, i));
      }
      previous = topic;
    }
    return out;
  }

  static int _endOfBlock(List<ChatMessage> messages, int from) {
    final topic = messages[from].topicId;
    var end = from;
    while (end + 1 < messages.length && messages[end + 1].topicId == topic) {
      end++;
    }
    return end;
  }

  static String _titleOfRange(
    List<ChatMessage> messages,
    int start,
    int end,
  ) {
    final input = <ChunkInput>[];
    for (var i = start; i <= end; i++) {
      final m = messages[i];
      if (m.isSystem) continue;
      input.add(ChunkInput(
        id: m.id,
        text: m.isSticker ? '' : m.body,
        authorId: m.authorId,
        at: m.at,
      ));
    }
    if (input.isEmpty) return 'Новая тема';
    return TopicChunker.chunkFor(input, 0, input.length - 1).title;
  }

  /// Разметка, полученная после участия модели.
  static ChatLayout fromRefined(
    List<ChatMessage> messages,
    ChunkedMessages prepared,
    RefinedTopics refined,
  ) =>
      // Границы человека главнее и модели тоже: он видел разговор целиком,
      // а модель — четыре сообщения вокруг спорного места.
      _withManual(
        messages,
        ChatLayout(
          headers: {
            for (final c in refined.chunks)
              if (c.start > 0) prepared.toMessage(c.start): c.title,
          },
          questions: {
            for (final q in refined.questions)
              prepared.toMessage(q.index): TopicQuestion(
                index: prepared.toMessage(q.index),
                suggestedTitle: q.suggestedTitle,
                reason: q.reason,
                confidence: q.confidence,
              ),
          },
          judgedBy: refined.judgedBy,
        ),
      );

  /// Готовит переписку к разбору — и запоминает, какому сообщению
  /// соответствует каждая позиция.
  ///
  /// **Зачем карта позиций.** Служебные строки («такой-то в группе») в
  /// разбор не идут: они не часть разговора и сбивают счёт слов. Но лента
  /// рисует их наравне со всеми, и позиция четвёртого сообщения в разборе
  /// не равна позиции четвёртого сообщения на экране. Без пересчёта
  /// заголовок темы уезжал вверх на столько строк, сколько служебных
  /// оказалось выше, — тем заметнее, чем активнее живёт группа.
  static ChunkedMessages? prepare(List<ChatMessage> messages) {
    final input = <ChunkInput>[];
    final positions = <int>[];
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      if (m.isSystem) continue;
      input.add(ChunkInput(
        id: m.id,
        text: m.isSticker ? '' : m.body,
        authorId: m.authorId,
        at: m.at,
      ));
      positions.add(i);
    }
    if (input.length < 4) return null;
    return ChunkedMessages(input: input, positions: positions);
  }

  static String _titleAfter(ChunkPlan plan, int index) {
    for (final c in plan.chunks) {
      if (index >= c.start && index <= c.end) return c.title;
    }
    return '';
  }
}

/// Переписка, приведённая к виду для разбора, вместе с картой позиций.
class ChunkedMessages {
  final List<ChunkInput> input;

  /// `positions[i]` — какому сообщению ленты соответствует `input[i]`.
  final List<int> positions;

  const ChunkedMessages({required this.input, required this.positions});

  int toMessage(int chunkIndex) => chunkIndex >= 0 &&
          chunkIndex < positions.length
      ? positions[chunkIndex]
      : (positions.isEmpty ? 0 : positions.last + 1);
}

/// Что рисовать между сообщениями.
class ChatLayout {
  final Map<int, String> headers;
  final Map<int, TopicQuestion> questions;

  /// Кто разметил — показывается человеку. Пустая строка означает, что
  /// разметки ещё нет.
  final String judgedBy;

  final Set<int> _dismissed = {};

  ChatLayout({
    required this.headers,
    required this.questions,
    this.judgedBy = '',
  });

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
