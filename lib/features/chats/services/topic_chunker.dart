import 'dart:math';

import 'russian_stem.dart';

/// Сообщение в том виде, какой нужен разбиению на темы.
///
/// Намеренно не модель хранения: алгоритм не должен зависеть от того, как
/// сообщения лежат на диске, а хранилище — от того, как их режут на темы.
class ChunkInput {
  final String id;
  final String text;
  final String authorId;
  final DateTime at;

  const ChunkInput({
    required this.id,
    required this.text,
    required this.authorId,
    required this.at,
  });
}

/// Что делать с найденной границей.
enum BoundaryAction {
  /// Уверены — режем сами.
  split,

  /// Сомневаемся — спрашиваем человека.
  ask,
}

/// Предполагаемая граница между темами.
class TopicBoundary {
  /// Индекс сообщения, с которого начинается новая тема.
  final int index;

  /// От 0 до 1. Ниже [TopicChunker.askBelow] границу вообще не предлагаем.
  final double confidence;

  final BoundaryAction action;

  /// Почему решили, что здесь граница, — человеческим языком.
  ///
  /// Не для красоты: вопрос «разделить здесь?» без объяснения выглядит
  /// капризом программы, и на него отвечают наугад.
  final String reason;

  const TopicBoundary({
    required this.index,
    required this.confidence,
    required this.action,
    required this.reason,
  });
}

/// Кусок переписки на одну тему.
class TopicChunk {
  final int start;
  final int end; // включительно
  final String title;
  final List<String> keywords;

  const TopicChunk({
    required this.start,
    required this.end,
    required this.title,
    required this.keywords,
  });

  int get length => end - start + 1;
}

/// Результат разбора.
class ChunkPlan {
  final List<TopicChunk> chunks;

  /// Границы, в которых программа не уверена, — их предлагают человеку.
  final List<TopicBoundary> questions;

  const ChunkPlan({required this.chunks, required this.questions});
}

/// Разбиение переписки на осознанные темы.
///
/// **Как это работает без обращения к ИИ.** Никакой модели здесь нет и не
/// нужно: тема меняется, когда меняется словарь. Между каждой парой соседних
/// сообщений считается, насколько похожи слова до и после — и провалы этой
/// похожести и есть переходы. Приём старый и проверенный (TextTiling,
/// Хёрст, 1997); он не «понимает» текст, но переходы находит.
///
/// К словарю добавлены два сигнала, которые в переписке сильнее любого
/// анализа слов:
///
/// - **пауза.** Разговор, продолженный на следующий день, — почти всегда
///   другой разговор. Это самый надёжный признак из всех;
/// - **слова-переключатели.** «Кстати», «другой вопрос», «по поводу» —
///   человек сам объявляет смену темы, и глупо это игнорировать.
///
/// **Почему спрашиваем, а не режем молча.** Ошибочно разрезанный разговор
/// человек чинит руками, и это раздражает сильнее, чем неразрезанный. Там,
/// где уверенности нет, программа обязана спросить — но спросить с
/// объяснением, иначе на вопрос ответят наугад.
class TopicChunker {
  /// Ниже этого границу не предлагаем вовсе — иначе вопросы посыплются
  /// после каждой реплики и их перестанут читать.
  static const double askBelow = 0.35;

  /// Выше этого режем сами, не спрашивая.
  static const double splitAbove = 0.7;

  /// Пауза, после которой разговор считается новым почти наверняка.
  static const Duration longSilence = Duration(hours: 6);

  /// Пауза, с которой начинаем присматриваться.
  static const Duration noticeableSilence = Duration(minutes: 40);

  /// Сколько сообщений с каждой стороны сравнивать.
  ///
  /// Три — компромисс: по одному сообщению словарь слишком беден, чтобы
  /// судить о теме, а по десяти граница размазывается и уезжает.
  static const int window = 3;

  /// Слова, которыми человек сам объявляет смену темы.
  static const List<String> switchMarkers = [
    'кстати', 'другой вопрос', 'по поводу', 'к слову', 'вернёмся',
    'вернемся', 'отдельно', 'ещё вопрос', 'еще вопрос', 'а теперь',
    'ладно', 'так вот', 'между прочим', 'забыл спросить', 'да, и',
  ];

  /// Разобрать переписку.
  ///
  /// [minChunk] — короче этого куски не выделяем: тема из одной реплики
  /// почти всегда означает, что мы ошиблись.
  static ChunkPlan plan(
    List<ChunkInput> messages, {
    int minChunk = 2,
  }) {
    if (messages.length < minChunk * 2) {
      return ChunkPlan(
        chunks: messages.isEmpty
            ? const []
            : [_chunk(messages, 0, messages.length - 1)],
        questions: const [],
      );
    }

    final candidates = <TopicBoundary>[];
    for (var i = minChunk; i <= messages.length - minChunk; i++) {
      final b = _score(messages, i);
      if (b.confidence >= askBelow) candidates.add(b);
    }

    // Соседние границы — это одна размазанная граница, а не две темы по
    // одному сообщению. Оставляем самую уверенную из группы.
    final kept = _thin(candidates, minChunk);

    final splits = [
      for (final b in kept)
        if (b.action == BoundaryAction.split) b.index,
    ];
    final questions = [
      for (final b in kept)
        if (b.action == BoundaryAction.ask) b,
    ];

    final chunks = <TopicChunk>[];
    var start = 0;
    for (final at in splits) {
      chunks.add(_chunk(messages, start, at - 1));
      start = at;
    }
    chunks.add(_chunk(messages, start, messages.length - 1));

    return ChunkPlan(chunks: chunks, questions: questions);
  }

  // ------------------------------------------------------------- сигналы

  static TopicBoundary _score(List<ChunkInput> messages, int i) {
    final gap = messages[i].at.difference(messages[i - 1].at);
    final silence = _silenceScore(gap);
    final marker = _markerScore(messages[i].text);
    final lexical = _lexicalGap(messages, i);

    // Веса подобраны так, чтобы **каждого** сигнала по отдельности хватало
    // хотя бы на вопрос, но ни одного — на молчаливый разрез.
    //
    // Первая раскладка (0.5 / 0.25 / 0.25) этим свойством не обладала:
    // разговор, где тема сменилась полностью, но без паузы, набирал 0.25 и
    // не дотягивал даже до вопроса. То есть самый очевидный для человека
    // случай — «говорили про склад, теперь про прайс» — программа
    // пропускала молча. Поймано тестом.
    //
    // Пауза остаётся самым весомым: вернувшийся через сутки почти наверняка
    // говорит о другом. Слово-переключатель — самый слабый: «ладно» и «так
    // вот» человек говорит и внутри одной темы.
    var score = silence * 0.45 + lexical * 0.4 + marker * 0.15;

    // Ответ на вопрос — не новая тема, чем бы он ни выглядел по словам.
    // «Сколько стоит доставка?» → «3000» не имеет ни одного общего слова,
    // и без этой поправки здесь всегда находилась бы граница.
    if (_looksLikeAnswer(messages, i)) score *= 0.4;

    final reasons = <String>[
      if (silence > 0.4) _silenceReason(gap),
      if (marker > 0) 'сообщение начинается со слов, которыми меняют тему',
      if (lexical > 0.5) 'дальше речь идёт о другом',
    ];

    return TopicBoundary(
      index: i,
      confidence: score.clamp(0.0, 1.0),
      action: score >= splitAbove ? BoundaryAction.split : BoundaryAction.ask,
      reason: reasons.isEmpty ? 'разговор меняет направление' : reasons.join(', '),
    );
  }

  static double _silenceScore(Duration gap) {
    if (gap >= longSilence) return 1;
    if (gap <= noticeableSilence) return 0;
    // Между сорока минутами и шестью часами — плавно.
    final span = longSilence.inSeconds - noticeableSilence.inSeconds;
    return (gap.inSeconds - noticeableSilence.inSeconds) / span;
  }

  static String _silenceReason(Duration gap) {
    if (gap.inDays >= 1) return 'перерыв ${gap.inDays} дн.';
    if (gap.inHours >= 1) return 'перерыв ${gap.inHours} ч.';
    return 'перерыв ${gap.inMinutes} мин.';
  }

  static double _markerScore(String text) {
    final low = text.toLowerCase().trimLeft();
    for (final m in switchMarkers) {
      // Только в начале сообщения: «кстати» в середине фразы темы не меняет.
      if (low.startsWith(m)) return 1;
    }
    return 0;
  }

  /// Насколько разошёлся словарь до и после точки: 0 — те же слова,
  /// 1 — общих слов нет вовсе.
  static double _lexicalGap(List<ChunkInput> messages, int i) {
    final before = <String>[];
    final after = <String>[];
    for (var k = max(0, i - window); k < i; k++) {
      before.addAll(RussianStem.tokens(messages[k].text));
    }
    for (var k = i; k < min(messages.length, i + window); k++) {
      after.addAll(RussianStem.tokens(messages[k].text));
    }
    if (before.isEmpty || after.isEmpty) {
      // Сравнивать нечего — это не признак смены темы, а отсутствие данных.
      // Возвращать здесь единицу значило бы резать на каждом «ок».
      return 0;
    }
    return 1 - _cosine(_counts(before), _counts(after));
  }

  static bool _looksLikeAnswer(List<ChunkInput> messages, int i) {
    final prev = messages[i - 1];
    final cur = messages[i];
    if (prev.authorId == cur.authorId) return false;
    if (!prev.text.trimRight().endsWith('?')) return false;
    // Ответ приходит по горячим следам; через сутки это уже новый разговор,
    // даже если формально он отвечает на старый вопрос.
    return cur.at.difference(prev.at) < const Duration(minutes: 40);
  }

  static Map<String, int> _counts(List<String> tokens) {
    final map = <String, int>{};
    for (final t in tokens) {
      map[t] = (map[t] ?? 0) + 1;
    }
    return map;
  }

  static double _cosine(Map<String, int> a, Map<String, int> b) {
    var dot = 0.0;
    for (final e in a.entries) {
      final other = b[e.key];
      if (other != null) dot += e.value * other;
    }
    if (dot == 0) return 0;
    final na = sqrt(a.values.fold<double>(0, (s, v) => s + v * v));
    final nb = sqrt(b.values.fold<double>(0, (s, v) => s + v * v));
    return dot / (na * nb);
  }

  /// Из группы близко стоящих границ оставить одну — самую уверенную.
  static List<TopicBoundary> _thin(List<TopicBoundary> all, int minChunk) {
    if (all.isEmpty) return const [];
    final sorted = [...all]
      ..sort((x, y) => y.confidence.compareTo(x.confidence));
    final kept = <TopicBoundary>[];
    for (final b in sorted) {
      final tooClose =
          kept.any((k) => (k.index - b.index).abs() < minChunk);
      if (!tooClose) kept.add(b);
    }
    return kept..sort((x, y) => x.index.compareTo(y.index));
  }

  // -------------------------------------------------------------- название

  /// Название темы по её самым характерным словам.
  ///
  /// Характерное — не то же самое, что частое. «Заказ» может встречаться во
  /// всей переписке и потому не отличает одну тему от другой. Берём слова,
  /// которые в этом куске встречаются заметно чаще, чем во всей беседе, —
  /// это обычная мера tf-idf, посчитанная вручную.
  static TopicChunk _chunk(List<ChunkInput> messages, int start, int end) {
    final own = <String>[];
    for (var i = start; i <= end; i++) {
      own.addAll(RussianStem.tokens(messages[i].text));
    }
    if (own.isEmpty) {
      return TopicChunk(
          start: start, end: end, title: 'Без темы', keywords: const []);
    }

    final ownCounts = _counts(own);
    final docFreq = <String, int>{};
    for (final m in messages) {
      for (final t in RussianStem.tokens(m.text).toSet()) {
        docFreq[t] = (docFreq[t] ?? 0) + 1;
      }
    }

    final scored = <String, double>{};
    ownCounts.forEach((term, count) {
      final df = docFreq[term] ?? 1;
      scored[term] = count * log(messages.length / df + 1);
    });

    final best = scored.entries.toList()
      ..sort((a, b) {
        final byScore = b.value.compareTo(a.value);
        // При равном весе — по алфавиту, чтобы название не прыгало от
        // запуска к запуску на одних и тех же данных.
        return byScore != 0 ? byScore : a.key.compareTo(b.key);
      });
    final keywords = [for (final e in best.take(3)) e.key];

    return TopicChunk(
      start: start,
      end: end,
      title: _titleFrom(keywords, messages, start, end),
      keywords: keywords,
    );
  }

  /// Название показываем словами из переписки, а не основами.
  ///
  /// Основа «договор» читается, а «поставщ» — нет. Поэтому для каждой
  /// основы находим первое настоящее слово, которое её дало.
  static String _titleFrom(
    List<String> keywords,
    List<ChunkInput> messages,
    int start,
    int end,
  ) {
    if (keywords.isEmpty) return 'Без темы';
    final words = <String, String>{};
    for (var i = start; i <= end; i++) {
      for (final raw in messages[i].text.split(RegExp(r'[^А-Яа-яЁёA-Za-z0-9-]+'))) {
        if (raw.length < 3) continue;
        final stem = RussianStem.of(raw);
        words.putIfAbsent(stem, () => raw.toLowerCase());
      }
    }
    final parts = [for (final k in keywords) words[k] ?? k];
    final title = parts.join(', ');
    return title.isEmpty
        ? 'Без темы'
        : title[0].toUpperCase() + title.substring(1);
  }
}
