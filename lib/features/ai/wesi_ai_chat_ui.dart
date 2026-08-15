import 'models/wesi_ai_chat_models.dart';
import 'storage/wesi_ai_local_store.dart';

enum WesiAiUiMode { classic, thinking }

/// Presentation-only helpers for the ordinary Wesi AI chat.
/// Transport keys and backend routing are intentionally not changed here.
class WesiAiChatUi {
  const WesiAiChatUi._();

  static bool shouldCreateInitialConversation(WesiAiLocalState state) =>
      state.activeConversation == null && state.conversations.isEmpty;

  static String tierLabel(WesiAiTier tier) => switch (tier) {
        WesiAiTier.fast => 'Быстрый',
        WesiAiTier.pro => 'Pro',
        WesiAiTier.maximum => 'Максимальный',
      };

  static String personaEmptyLabel(WesiAiPersona persona) => switch (persona) {
        WesiAiPersona.zane => 'Зейн готов к работе',
        WesiAiPersona.nirvana => 'Нирвана готова к работе',
        WesiAiPersona.lobby => 'Зейн и Нирвана готовы к работе',
      };

  static String sendingLabel(Duration elapsed) {
    final seconds = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
    return 'Формирует ответ · ${seconds}с';
  }

  static String modeLabel(WesiAiUiMode mode) => switch (mode) {
        WesiAiUiMode.classic => 'Классический',
        WesiAiUiMode.thinking => 'Думающий',
      };

  static String safeReasoningSummary(WesiAiMessage message) {
    final rawBlocks = message.metadata['blocks'];
    final blockCount = rawBlocks is List ? rawBlocks.length : 0;
    if (blockCount > 0) {
      return 'Проверил контекст и подготовил ответ с учётом $blockCount структурированных блоков.';
    }
    return 'Сопоставил запрос с контекстом текущего диалога и подготовил итоговый ответ.';
  }

  static const Set<String> _followUpStopWords = <String>{
    'это',
    'эта',
    'этот',
    'эти',
    'как',
    'что',
    'чтобы',
    'или',
    'для',
    'про',
    'при',
    'над',
    'под',
    'без',
    'есть',
    'был',
    'была',
    'были',
    'будет',
    'нужно',
    'можно',
    'только',
    'теперь',
    'тогда',
    'если',
    'уже',
    'ещё',
    'еще',
    'очень',
    'который',
    'которая',
    'которые',
    'мне',
    'тебе',
    'его',
    'её',
    'она',
    'они',
    'мой',
    'моя',
    'наш',
    'ваш',
    'такой',
    'такая',
    'сделай',
    'сделать',
    'давай',
    'ответ',
    'вопрос',
    'почему',
    'зачем',
    'пожалуйста',
    'просто',
    'тоже',
    'там',
    'тут',
    'здесь',
    'the',
    'and',
    'for',
    'with',
    'from',
    'this',
    'that',
    'into',
    'your',
    'you',
  };

  static String _followUpTopic(String source) {
    final cleaned = source
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'https?://\S+'), ' ')
        .replaceAll(RegExp(r'[^0-9A-Za-zА-Яа-яЁё_-]+'), ' ');
    final seen = <String>{};
    final words = <String>[];
    for (final raw in cleaned.split(RegExp(r'\s+'))) {
      final word = raw.trim();
      final lower = word.toLowerCase();
      if (word.length < 3 ||
          _followUpStopWords.contains(lower) ||
          !seen.add(lower)) {
        continue;
      }
      words.add(word);
      if (words.length == 5) break;
    }
    return words.join(' ');
  }

  static bool _hasFollowUpSignal(String source, List<String> signals) =>
      signals.any((signal) => source.contains(signal));

  static List<String> followUps({
    required String answer,
    String lastUserText = '',
    WesiAiPersona persona = WesiAiPersona.zane,
  }) {
    final topicSource = lastUserText.trim().isNotEmpty ? lastUserText : answer;
    final topic = _followUpTopic(topicSource);
    if (topic.isEmpty) {
      return const <String>[
        'Уточни следующий практический шаг',
        'Какие риски здесь стоит учесть?',
        'Что ещё важно проверить?',
      ];
    }

    final quoted = '«$topic»';
    final signalSource = '$lastUserText $answer'.toLowerCase();

    if (_hasFollowUpSignal(signalSource, const <String>[
      'ошиб',
      'пада',
      'сломал',
      'сломалось',
      'не работает',
      'перестал',
      'сбой',
      'crash',
      'exception',
      'build',
      'сборк',
      'gradle',
      'kotlin',
      'dns',
      'сервер',
    ])) {
      return <String>[
        'Найди корневую причину для $quoted',
        'Как исправить $quoted пошагово?',
        'Какие логи или проверки нужны для $quoted?',
      ];
    }

    if (_hasFollowUpSignal(signalSource, const <String>[
      'бюджет',
      'цена',
      'стоимост',
      'доход',
      'расход',
      'прибыл',
      'марж',
      'процент',
      'метрик',
      'статист',
      'расчёт',
      'расчет',
      'посчитай',
    ])) {
      return <String>[
        'Разложи расчёт по $quoted по шагам',
        'Какие допущения сильнее всего влияют на $quoted?',
        'Покажи оптимистичный и консервативный сценарии для $quoted',
      ];
    }

    if (_hasFollowUpSignal(signalSource, const <String>[
      'сравни',
      'лучше',
      'выбрать',
      'выбор',
      'между',
      'вариант',
      'альтернатив',
      'плюсы',
      'минусы',
    ])) {
      return <String>[
        'Сравни варианты для $quoted по главным критериям',
        'Какой вариант для $quoted ты рекомендуешь и почему?',
        'Какие компромиссы есть у $quoted?',
      ];
    }

    if (_hasFollowUpSignal(signalSource, const <String>[
      'план',
      'реализ',
      'архитект',
      'добавить',
      'внедр',
      'разработ',
      'стратег',
      'этап',
      'roadmap',
      'ux',
      'ui',
    ])) {
      return <String>[
        'Собери план реализации для $quoted',
        'Какие варианты реализации $quoted стоит сравнить?',
        'Что сделать первым для $quoted?',
      ];
    }

    if (_hasFollowUpSignal(signalSource, const <String>[
      'облож',
      'дизайн',
      'изображ',
      'видео',
      'музык',
      'бит',
      'текст',
      'идея',
      'концепц',
      'назван',
      'стиль',
      'креатив',
    ])) {
      return <String>[
        'Предложи три разных направления для $quoted',
        'Как можно сильнее развить идею $quoted?',
        'Сделай альтернативный вариант для $quoted',
      ];
    }

    if (_hasFollowUpSignal(signalSource, const <String>[
      'объясни',
      'расскажи',
      'что такое',
      'как работает',
      'почему',
      'зачем',
      'разница',
      'значит',
    ])) {
      return <String>[
        'Объясни $quoted на конкретном примере',
        'Что чаще всего неправильно понимают в $quoted?',
        'Как $quoted работает на практике?',
      ];
    }

    if (persona == WesiAiPersona.nirvana) {
      return <String>[
        'Разберём глубже $quoted',
        'Что в $quoted может быть неочевидно?',
        'Какие ещё варианты есть для $quoted?',
      ];
    }
    return <String>[
      'Какой следующий шаг по $quoted?',
      'Какие риски есть у $quoted?',
      'Что ещё проверить по $quoted?',
    ];
  }
}
