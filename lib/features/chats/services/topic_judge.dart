import 'topic_chunker.dart';

/// Что решили про одну спорную границу.
class TopicVerdict {
  /// Резать здесь.
  final bool split;

  /// Название темы, которая начинается после границы. Пусто — не придумали.
  final String title;

  /// От 0 до 1.
  final double confidence;

  /// Объяснение для человека.
  final String reason;

  const TopicVerdict({
    required this.split,
    this.title = '',
    this.confidence = 0,
    this.reason = '',
  });
}

/// Что показать человеку в спорном месте.
class TopicQuestion {
  final int index;
  final String suggestedTitle;
  final String reason;
  final double confidence;

  const TopicQuestion({
    required this.index,
    required this.suggestedTitle,
    required this.reason,
    required this.confidence,
  });

  /// Текст вопроса — тот самый, который вы описали.
  String ask({bool russian = true}) {
    if (!russian) {
      return suggestedTitle.isEmpty
          ? 'Looks like the subject changes here. Split the chat?'
          : 'Looks like you moved on to “$suggestedTitle”. Split here?';
    }
    return suggestedTitle.isEmpty
        ? 'Кажется, здесь разговор меняет тему. Разделить?'
        : 'Кажется, вы перешли к теме «$suggestedTitle». '
            'Разделить тут чат на отдельный блок?';
  }
}

/// Кто решает, где кончается одна тема и начинается другая.
///
/// **Почему это отдельный слой.** Слова-ключи находят места, где меняется
/// словарь, но не понимают, о чём речь: назвать тему они могут только
/// перечислением слов — «поставщик, прайс, комплектующие». Это работает, но
/// осмысленным блоком не выглядит, и владелец прав, что так делать не стоит.
///
/// **И почему слова-ключи всё равно нужны.** Отправлять модели весь чат на
/// каждое новое сообщение — это деньги, задержка и, главное, отправка
/// переписки наружу. Поэтому работа делится:
///
/// 1. местная разметка ([TopicChunker]) быстро находит **кандидатов** —
///    обычно это несколько мест из сотни сообщений;
/// 2. судья смотрит только на них и решает, резать ли и как назвать.
///
/// **Куда именно уходит переписка — решает владелец** ([TopicPrivacy]).
/// Сначала здесь стояло жёсткое «личные чаты не уходят никогда»; владелец
/// решил иначе, и это его право: работа с блоками — ключевая часть чатов, а
/// без модели осмысленных названий не получить.
///
/// Что при этом обязано остаться: подпись под чатом всегда соответствует
/// настройке. Обещание «видят только собеседники», оставленное при
/// включённой модели, — это не приватность, а ложь о ней.
abstract class TopicJudge {
  /// Готов ли судья работать. Нет ключа или нет сети — false, и разметка
  /// молча остаётся местной.
  bool get available;

  /// Имя для интерфейса: человек должен видеть, кто размечал его переписку.
  String get name;

  /// Решить про одну границу. [before] и [after] — куски переписки вокруг
  /// спорного места, уже подготовленные к отправке.
  Future<TopicVerdict?> judge({
    required List<ChunkInput> before,
    required List<ChunkInput> after,
  });

  /// Назвать готовый кусок.
  Future<String?> nameTopic(List<ChunkInput> messages);
}

/// Разметка без обращения куда-либо.
///
/// Даёт границы и перечень характерных слов вместо названия. Осознанным
/// блоком это не выглядит, и в этом её честный предел — зато она работает
/// офлайн, мгновенно и на переписке, которую нельзя показывать никому.
class HeuristicJudge implements TopicJudge {
  const HeuristicJudge();

  @override
  bool get available => true;

  @override
  String get name => 'на устройстве';

  @override
  Future<TopicVerdict?> judge({
    required List<ChunkInput> before,
    required List<ChunkInput> after,
  }) async =>
      null; // Решение уже принято разметкой — добавить нечего.

  @override
  Future<String?> nameTopic(List<ChunkInput> messages) async => null;
}
