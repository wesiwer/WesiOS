import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/chat_message.dart';

/// Чем закончилась попытка поправить сообщение.
///
/// Перечисление, а не `bool`: человеку надо сказать, почему не вышло, а
/// собирать текст отказа в хранилище — значит тащить туда язык интерфейса.
enum MessageEditResult {
  ok,

  /// Сообщения уже нет — истекло или удалено, пока диалог был открыт.
  gone,

  /// Чужое. Правка чужих слов от чужого имени — подделка, а не удобство.
  notMine,

  /// Стикер или служебная строка: править нечего.
  notEditable,

  /// Пустой текст. Стереть сообщение можно удалением, но не так, чтобы от
  /// него остался пустой пузырь.
  empty,

  /// Текст не изменился — записывать «изменено» не за что.
  unchanged,
}

/// Хранилище переписки.
///
/// **Два правила, и они противоположны друг другу.**
///
/// Обычные сообщения живут месяц и стираются. Не ради места на диске —
/// переписка, которая хранится вечно, рано или поздно становится уликой: при
/// потере телефона, при проверке, при увольнении. Месяц покрывает рабочую
/// надобность «посмотреть, о чём договорились», и не превращает мессенджер в
/// архив всего сказанного.
///
/// Архив — противоположное: туда кладут осознанно, и оттуда не удаляется
/// ничего и никогда. Ни чисткой, ни сменой настроек, ни очисткой чата.
class MessageStore {
  static const String boxName = 'wesios_messages';

  /// Сколько живёт обычное сообщение.
  static const Duration defaultLifetime = Duration(days: 30);

  /// Меняется при любой записи — экраны перечитывают.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Box<ChatMessage>? _box;

  static Future<Box<ChatMessage>> open() async {
    final box = _box;
    if (box != null && box.isOpen) return box;
    return _box = Hive.isBoxOpen(boxName)
        ? Hive.box<ChatMessage>(boxName)
        : await Hive.openBox<ChatMessage>(boxName);
  }

  static Box<ChatMessage>? get _opened {
    final box = _box;
    if (box != null && box.isOpen) return box;
    if (!Hive.isBoxOpen(boxName)) return null;
    return _box = Hive.box<ChatMessage>(boxName);
  }

  /// Срок жизни для нового сообщения.
  static DateTime expiryFor(DateTime at, {Duration? lifetime}) =>
      at.add(lifetime ?? defaultLifetime);

  static final Random _random = Random.secure();

  /// Идентификатор сообщения.
  ///
  /// Времени и автора **недостаточно**: два сообщения, отправленные в одну
  /// микросекунду одним человеком, получали одинаковый идентификатор и
  /// затирали друг друга в хранилище. На живом устройстве это редкость, но
  /// при вставке нескольких сообщений разом — например, когда переписка
  /// приезжает с сервера пачкой — становится обычным делом. Поймано тестом.
  ///
  /// Время в начале оставлено намеренно: по идентификатору видно, когда
  /// сообщение написано, и записи в базе лежат в осмысленном порядке.
  static String newId(DateTime at, String authorId) {
    final salt = _random.nextInt(1 << 32).toRadixString(36);
    return '${at.microsecondsSinceEpoch}-$authorId-$salt';
  }

  // ------------------------------------------------------------------ чтение

  /// Переписка одного чата по времени. Истёкшие не показываются, даже если
  /// чистка до них ещё не дошла: увиденное сообщение, которое исчезнет через
  /// секунду, хуже, чем не показанное вовсе.
  static List<ChatMessage> of(String chatId, {DateTime? now}) {
    final box = _opened;
    if (box == null) return const [];
    final at = now ?? DateTime.now();
    final out = [
      for (final m in box.values)
        if (m.chatId == chatId && !m.isExpired(at)) m,
    ]..sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  /// Найти в переписке одного чата.
  ///
  /// Стикеры пропускаются: в теле у них лежит `react:0`, и поиск слова
  /// «react» вываливал бы горсть картинок вместо разговора.
  ///
  /// Регистр не важен — человек ищет «пятница», а написано «Пятницу».
  /// Приведение к нижнему регистру делается один раз для запроса, а не на
  /// каждое сообщение по два раза.
  static List<ChatMessage> search(
    String chatId,
    String query, {
    DateTime? now,
  }) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    return [
      for (final m in of(chatId, now: now))
        if (!m.isSticker && m.body.toLowerCase().contains(needle)) m,
    ];
  }

  /// Всё, что в архиве, — новое сверху.
  static List<ChatMessage> archive() {
    final box = _opened;
    if (box == null) return const [];
    return [
      for (final m in box.values)
        if (m.archived) m,
    ]..sort((a, b) => b.at.compareTo(a.at));
  }

  static ChatMessage? byId(String id) => _opened?.get(id);

  static int countOf(String chatId, {DateTime? now}) =>
      of(chatId, now: now).length;

  /// Последнее сообщение чата — для списка разговоров.
  static ChatMessage? lastOf(String chatId, {DateTime? now}) {
    final all = of(chatId, now: now);
    return all.isEmpty ? null : all.last;
  }

  // ------------------------------------------------------------------ запись

  static Future<void> put(ChatMessage message) async {
    await _opened?.put(message.id, message);
    revision.value++;
  }

  static Future<ChatMessage?> send({
    required String chatId,
    required String authorId,
    required String body,
    MessageKind kind = MessageKind.text,
    String? replyTo,
    Duration? lifetime,
    DateTime? now,
    DeliveryState state = DeliveryState.pending,
  }) async {
    final text = kind == MessageKind.text ? body.trim() : body;
    if (text.isEmpty) return null;

    final at = now ?? DateTime.now();
    final message = ChatMessage(
      id: newId(at, authorId),
      chatId: chatId,
      authorId: authorId,
      body: text,
      at: at,
      kind: kind,
      // Состояние приходит снаружи, а не решается здесь: чтобы его выбрать,
      // надо знать, уезжает ли этот чат и настроен ли сервер, — а хранилище
      // про то и другое знать не должно. См. `ChatDelivery.initialFor`.
      state: state,
      expiresAt: expiryFor(at, lifetime: lifetime),
      replyTo: replyTo,
    );
    await put(message);
    return message;
  }

  /// Поправить написанное.
  ///
  /// Автор проверяется **здесь**, а не только в диалоге. Правило, которое
  /// живёт в одном экране, обходится вторым экраном — эта ошибка уже была
  /// поймана на назначении задач, и повторять её незачем.
  static Future<MessageEditResult> edit({
    required String id,
    required String by,
    required String body,
    DateTime? now,
  }) async {
    final message = _opened?.get(id);
    if (message == null) return MessageEditResult.gone;
    if (message.authorId != by) return MessageEditResult.notMine;
    if (!message.editable) return MessageEditResult.notEditable;

    final text = body.trim();
    if (text.isEmpty) return MessageEditResult.empty;
    if (text == message.body) return MessageEditResult.unchanged;

    // Срок жизни не пересчитывается: сообщение написано тогда, когда
    // написано, и правка опечатки не должна продлевать ему жизнь ещё на
    // месяц. Иначе достаточно было бы раз в месяц дописывать точку, чтобы
    // переписка не стиралась никогда, — а месячный срок ровно от этого и
    // защищает.
    await put(message.copyWith(body: text, editedAt: now ?? DateTime.now()));
    return MessageEditResult.ok;
  }

  /// Убрать сообщение из чата.
  ///
  /// Архивное не удаляется: это и есть смысл архива. Возвращает false, чтобы
  /// вызывающий мог сказать человеку правду, а не молча ничего не сделать.
  static Future<bool> remove(String id) async {
    final message = _opened?.get(id);
    if (message == null) return false;
    if (message.archived) return false;
    await _opened?.delete(id);
    revision.value++;
    return true;
  }

  /// Положить в архив — навсегда.
  static Future<void> archiveMessage(String id) async {
    final message = _opened?.get(id);
    if (message == null || message.archived) return;
    // Срок снимается вместе с пометкой: оставить его — значит оставить в
    // архиве бомбу замедленного действия на случай, если проверку на
    // archived где-нибудь забудут.
    await put(message.copyWith(archived: true, expiresAt: null));
  }

  /// Вернуть из архива: сообщение снова получает срок жизни.
  static Future<void> unarchive(String id, {DateTime? now}) async {
    final message = _opened?.get(id);
    if (message == null || !message.archived) return;
    await put(message.copyWith(
      archived: false,
      expiresAt: expiryFor(now ?? DateTime.now()),
    ));
  }

  /// Набор откликов, между которыми выбирает человек.
  ///
  /// Короткий намеренно. Полная клавиатура смайликов превращает реакцию в
  /// ещё одно сообщение — а её ценность ровно в том, что она отвечает, не
  /// прерывая разговор.
  static const List<String> reactionChoices = [
    '👍', '❤️', '😄', '🤔', '👀', '🔥', '✅', '❌',
  ];

  /// Откликнуться на сообщение.
  ///
  /// Повторный тот же символ снимает отклик — иначе убрать случайный
  /// «палец вверх» было бы нечем. Другой символ заменяет прежний: у
  /// человека одно мнение, а не коллекция.
  ///
  /// Возвращает `false`, если сообщения уже нет.
  static Future<bool> react({
    required String id,
    required String by,
    required String emoji,
  }) async {
    final message = _opened?.get(id);
    if (message == null) return false;

    final next = Map<String, String>.from(message.reactions);
    if (next[by] == emoji) {
      next.remove(by);
    } else {
      next[by] = emoji;
    }
    await put(message.copyWith(reactions: next));
    return true;
  }

  static Future<void> markState(String id, DeliveryState state) async {
    final message = _opened?.get(id);
    if (message == null) return;
    await put(message.copyWith(state: state));
  }

  /// Привязать сообщения к блоку темы.
  static Future<void> assignTopic(
      Iterable<String> ids, String? topicId) async {
    final box = _opened;
    if (box == null) return;
    for (final id in ids) {
      final message = box.get(id);
      if (message == null) continue;
      await box.put(id, message.copyWith(topicId: topicId));
    }
    revision.value++;
  }

  // ----------------------------------------------------------------- чистка

  /// Стереть всё, чему вышел срок.
  ///
  /// Возвращает, сколько стёрлось, — чтобы это можно было показать и
  /// проверить тестом, а не гадать, отработало ли.
  static Future<int> sweep({DateTime? now}) async {
    final box = _opened;
    if (box == null) return 0;
    final at = now ?? DateTime.now();
    final dead = [
      for (final m in box.values)
        if (m.isExpired(at)) m.id,
    ];
    if (dead.isEmpty) return 0;
    await box.deleteAll(dead);
    revision.value++;
    return dead.length;
  }

  /// Пересчитать срок жизни уже написанного в чате — **только в сторону
  /// продления**.
  ///
  /// Асимметрия намеренная и она здесь главное.
  ///
  /// Продление ничего не разрушает: человек сказал «пусть хранится дольше», и
  /// разумно, что это относится и к тому, что уже написано, — иначе настройка
  /// начинает действовать только с завтрашнего дня и выглядит сломанной.
  ///
  /// Укорачивание задним числом разрушает: поставив «хранить неделю» на чат,
  /// которому месяц, человек одним нажатием стёр бы три недели переписки — и
  /// узнал бы об этом уже после. Такое решение принимают отдельно и явно,
  /// кнопкой «очистить», а не побочным следствием настройки.
  ///
  /// Уже истёкшие не воскрешаются: их для человека нет, и возвращать их
  /// сменой настройки было бы сюрпризом в обратную сторону.
  ///
  /// Возвращает, скольким сообщениям срок продлился.
  static Future<int> extendLifetime(
    String chatId,
    Duration lifetime, {
    DateTime? now,
  }) async {
    final box = _opened;
    if (box == null) return 0;
    final at = now ?? DateTime.now();
    var touched = 0;

    for (final m in box.values.toList()) {
      if (m.chatId != chatId || m.archived || m.isExpired(at)) continue;
      final current = m.expiresAt;
      // null — не истекает вовсе; куда уж дольше.
      if (current == null) continue;
      final wanted = m.at.add(lifetime);
      if (!wanted.isAfter(current)) continue;
      await box.put(m.id, m.copyWith(expiresAt: wanted));
      touched++;
    }

    if (touched > 0) revision.value++;
    return touched;
  }

  /// Очистить чат руками. Архивное остаётся.
  static Future<int> clearChat(String chatId) async {
    final box = _opened;
    if (box == null) return 0;
    final dead = [
      for (final m in box.values)
        if (m.chatId == chatId && !m.archived) m.id,
    ];
    if (dead.isEmpty) return 0;
    await box.deleteAll(dead);
    revision.value++;
    return dead.length;
  }
}
