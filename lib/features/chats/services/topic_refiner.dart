import 'dart:math';

import '../models/chat_policy.dart';
import 'topic_chunker.dart';
import 'topic_judge.dart';

/// Итог разбора после участия судьи.
class RefinedTopics {
  final List<TopicChunk> chunks;

  /// Что спросить у человека.
  final List<TopicQuestion> questions;

  /// Кто размечал — показывается в интерфейсе.
  final String judgedBy;

  const RefinedTopics({
    required this.chunks,
    required this.questions,
    required this.judgedBy,
  });
}

/// Второй проход: там, где местная разметка сомневается, спрашиваем модель.
///
/// **Разделение труда.** Слова-ключи находят места, где меняется словарь.
/// Этого достаточно, чтобы не гонять модель по всей переписке на каждое
/// сообщение, но недостаточно, чтобы получить осмысленное название темы:
/// перечисление «поставщик, прайс, комплектующие» — не название.
///
/// Поэтому модель видит только спорные окна и готовые куски, и её работа —
/// решить и назвать, а не искать.
///
/// **Чего не бывает.** Личная переписка наружу не уходит ни при каких
/// настройках — см. [TopicPrivacy]. Там остаётся местная разметка, и это
/// прямое следствие договорённости о шифровании, а не недоделка.
class TopicRefiner {
  /// Сколько сообщений показывать модели с каждой стороны границы.
  ///
  /// Четыре: по двум непонятно, о чём речь, а по десяти запрос дорожает и
  /// наружу уходит заметно больше переписки, чем нужно для ответа.
  static const int contextSize = 4;

  /// Больше скольких спорных мест за раз не спрашиваем.
  ///
  /// Переписка на тысячу сообщений после долгого перерыва может дать
  /// десятки кандидатов. Без предела один вход в чат превратился бы в
  /// полсотни запросов к модели.
  static const int maxQuestionsPerRun = 8;

  static Future<RefinedTopics> refine({
    required List<ChunkInput> messages,
    required ChatKind kind,
    required TopicJudge judge,
    ChunkPlan? plan,
  }) async {
    final base = plan ?? TopicChunker.plan(messages);

    final mayAsk = TopicPrivacy.mayLeaveDevice(kind) && judge.available;
    if (!mayAsk) {
      return RefinedTopics(
        chunks: base.chunks,
        questions: [
          for (final b in base.questions)
            TopicQuestion(
              index: b.index,
              // Без модели название — перечень характерных слов. Честно
              // подставляем его, а не выдумываем: человек увидит, на каком
              // основании программа спрашивает.
              suggestedTitle: _titleAfter(base, b.index),
              reason: b.reason,
              confidence: b.confidence,
            ),
        ],
        judgedBy: const HeuristicJudge().name,
      );
    }

    final questions = <TopicQuestion>[];
    final extraSplits = <int>[];

    for (final b in base.questions.take(maxQuestionsPerRun)) {
      final verdict = await judge.judge(
        before: _window(messages, b.index - contextSize, b.index),
        after: _window(messages, b.index, b.index + contextSize),
      );

      if (verdict == null) {
        // Модель не ответила или ответила мусором — ведём себя как без неё.
        // Тишина хуже, чем разметка попроще.
        questions.add(TopicQuestion(
          index: b.index,
          suggestedTitle: _titleAfter(base, b.index),
          reason: b.reason,
          confidence: b.confidence,
        ));
        continue;
      }

      if (!verdict.split) continue; // Модель говорит «одна тема» — верим.

      // Уверенность модели высокая — режем сами. Средняя — спрашиваем, но
      // уже с человеческим названием, а не перечнем слов.
      if (verdict.confidence >= 0.85) {
        extraSplits.add(b.index);
      } else {
        questions.add(TopicQuestion(
          index: b.index,
          suggestedTitle: verdict.title,
          reason: verdict.reason.isEmpty ? b.reason : verdict.reason,
          confidence: verdict.confidence,
        ));
      }
    }

    final chunks = extraSplits.isEmpty
        ? base.chunks
        : _resplit(messages, base, extraSplits);

    return RefinedTopics(
      chunks: await _rename(chunks, messages, judge),
      questions: questions,
      judgedBy: judge.name,
    );
  }

  /// Переназвать куски силами модели.
  ///
  /// Только те, что достаточно длинные: тема из двух реплик не стоит
  /// запроса, а перечня слов для неё хватает.
  static Future<List<TopicChunk>> _rename(
    List<TopicChunk> chunks,
    List<ChunkInput> messages,
    TopicJudge judge,
  ) async {
    final out = <TopicChunk>[];
    for (final c in chunks) {
      if (c.length < 3) {
        out.add(c);
        continue;
      }
      final title = await judge.nameTopic(
          messages.sublist(c.start, min(c.end + 1, messages.length)));
      out.add(title == null || title.isEmpty
          ? c
          : TopicChunk(
              start: c.start,
              end: c.end,
              title: title,
              keywords: c.keywords,
            ));
    }
    return out;
  }

  static List<TopicChunk> _resplit(
    List<ChunkInput> messages,
    ChunkPlan base,
    List<int> extra,
  ) {
    final points = <int>{
      for (final c in base.chunks)
        if (c.start > 0) c.start,
      ...extra,
    }.toList()
      ..sort();

    final out = <TopicChunk>[];
    var start = 0;
    for (final at in points) {
      if (at <= start) continue;
      out.add(_slice(messages, base, start, at - 1));
      start = at;
    }
    out.add(_slice(messages, base, start, messages.length - 1));
    return out;
  }

  /// Название и слова берём у ближайшего исходного куска: пересчитывать
  /// характерные слова заново незачем, они не меняются от того, что границу
  /// сдвинули на пару сообщений.
  static TopicChunk _slice(
    List<ChunkInput> messages,
    ChunkPlan base,
    int start,
    int end,
  ) {
    for (final c in base.chunks) {
      if (start >= c.start && start <= c.end) {
        return TopicChunk(
            start: start, end: end, title: c.title, keywords: c.keywords);
      }
    }
    return TopicChunk(
        start: start, end: end, title: 'Без темы', keywords: const []);
  }

  static String _titleAfter(ChunkPlan plan, int index) {
    for (final c in plan.chunks) {
      if (index >= c.start && index <= c.end) return c.title;
    }
    return '';
  }

  static List<ChunkInput> _window(List<ChunkInput> all, int from, int to) =>
      all.sublist(max(0, from), min(all.length, to));
}
