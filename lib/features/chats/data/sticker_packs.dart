/// Стикеры и эмодзи.
///
/// **Почему стикеры — символы, а не картинки.** Картинки пришлось бы класть
/// в сборку (это мегабайты на каждой платформе) или качать с сервера (это
/// ожидание и ещё одна вещь, которая ломается). Набор ниже рисуется шрифтом,
/// весит ноль, работает офлайн и одинаково выглядит на Windows и Android.
///
/// Когда понадобятся настоящие рисованные стикеры — формат сообщения к этому
/// готов: в теле лежит **идентификатор** стикера, а не сам он. Заменить
/// отрисовку можно будет, не трогая ни хранилище, ни передачу.
class StickerPacks {
  StickerPacks._();

  /// Наборы: идентификатор → символы.
  ///
  /// Идентификатор попадает в сообщение и остаётся навсегда, поэтому менять
  /// его нельзя — только добавлять новые.
  static const List<StickerPack> all = [
    StickerPack(
      id: 'react',
      titleRu: 'Реакции',
      titleEn: 'Reactions',
      items: ['👍', '👌', '🔥', '💯', '👏', '🙏', '🤝', '💪',
              '❤️', '😂', '🤔', '😐', '🙄', '😴', '🤯', '🫡'],
    ),
    StickerPack(
      id: 'work',
      titleRu: 'Работа',
      titleEn: 'Work',
      items: ['📦', '🚚', '🏭', '📊', '📈', '📉', '💰', '🧾',
              '📅', '⏰', '✅', '❌', '⚠️', '📌', '🔧', '🗂'],
    ),
    StickerPack(
      id: 'mood',
      titleRu: 'Настроение',
      titleEn: 'Mood',
      items: ['😀', '😅', '😎', '🥲', '😤', '😱', '🥴', '🤒',
              '☕', '🌙', '⚡', '🎯', '🎉', '🍀', '🧊', '💤'],
    ),
  ];

  /// Символ по идентификатору вида `react:3`.
  ///
  /// Неизвестный идентификатор — не повод показывать пустоту: сообщение было
  /// отправлено, и человек должен видеть, что оно есть. Отдаём знак вопроса.
  static String resolve(String stickerId) {
    final parts = stickerId.split(':');
    if (parts.length != 2) return '❔';
    final index = int.tryParse(parts[1]);
    if (index == null) return '❔';
    for (final pack in all) {
      if (pack.id != parts[0]) continue;
      if (index < 0 || index >= pack.items.length) return '❔';
      return pack.items[index];
    }
    return '❔';
  }

  /// Идентификатор для отправки.
  static String idOf(String packId, int index) => '$packId:$index';

  /// Эмодзи для обычного текста — то, что вставляется прямо в строку.
  ///
  /// Отдельно от стикеров: стикер — это самостоятельное сообщение, эмодзи —
  /// часть фразы. Смешивать их в одной панели значит путать два разных
  /// действия.
  static const List<String> emoji = [
    '😀', '😁', '😂', '🙂', '😉', '😊', '😍', '😘', '😜', '🤗',
    '🤔', '😐', '😴', '😢', '😭', '😡', '🥳', '🤝', '👍', '👎',
    '👌', '🙏', '💪', '👀', '🔥', '⭐', '❤️', '💔', '✅', '❌',
    '⚠️', '📌', '📎', '💰', '📦', '🚚', '📅', '⏰', '☕', '🎉',
  ];
}

class StickerPack {
  final String id;
  final String titleRu;
  final String titleEn;
  final List<String> items;

  const StickerPack({
    required this.id,
    required this.titleRu,
    required this.titleEn,
    required this.items,
  });
}
