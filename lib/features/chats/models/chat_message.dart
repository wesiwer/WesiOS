import 'package:hive/hive.dart';

import 'chat_attachment.dart';

part 'chat_message.g.dart';

/// Что за сообщение.
@HiveType(typeId: 22)
enum MessageKind {
  @HiveField(0)
  text,

  /// Стикер — идентификатор набора и картинки, а не сама картинка.
  @HiveField(1)
  sticker,

  /// Служебное: «тема разделена», «человек вошёл в группу».
  @HiveField(2)
  system,

  /// Файл: документ, картинка, звук. Что именно — решает тип содержимого
  /// вложения, а не отдельный вид сообщения. Заводить `image` рядом с
  /// `file` значило бы решать одно и то же в двух местах и однажды
  /// разойтись.
  @HiveField(3)
  file,
}

/// Что случилось с сообщением по пути.
@HiveType(typeId: 23)
enum DeliveryState {
  /// Лежит у нас, наружу ещё не ушло.
  @HiveField(0)
  pending,

  /// Никуда и не собиралось: сервер не настроен либо чат не уезжает вовсе.
  ///
  /// Отдельное состояние, а не [pending], потому что разница видна человеку.
  /// «Часики» рядом с сообщением означают «отправляется» — и если отправлять
  /// некуда, они висят вечно и выглядят как поломка. Здесь сказать нечего, и
  /// правильный ответ — не показывать ничего, а не показывать ожидание,
  /// которого нет.
  @HiveField(5)
  local,

  /// Ушло на реле.
  @HiveField(1)
  sent,

  /// Реле подтвердило, что собеседник забрал.
  @HiveField(2)
  delivered,

  /// Собеседник открыл чат.
  @HiveField(3)
  read,

  /// Отправить не удалось. Не то же самое, что pending: pending ждёт своей
  /// очереди, а failed уже попробовало и получило отказ.
  @HiveField(4)
  failed,
}

/// Сообщение.
///
/// **Про срок жизни.** Обычные сообщения живут месяц и стираются
/// ([expiresAt]). Это не экономия места, а осознанное правило: переписка,
/// которая хранится вечно, рано или поздно становится уликой — в чужих руках
/// или в своих. Всё, что должно пережить месяц, человек кладёт в архив
/// осознанным действием ([archived]).
///
/// Архивное сообщение не удаляется никогда и не участвует в чистке.
@HiveType(typeId: 24)
class ChatMessage {
  @HiveField(0)
  final String id;

  /// К какому разговору относится.
  @HiveField(1)
  final String chatId;

  /// Кто написал — идентификатор человека из состава.
  @HiveField(2)
  final String authorId;

  /// Текст либо идентификатор стикера — смотря по [kind].
  @HiveField(3)
  final String body;

  @HiveField(4)
  final DateTime at;

  @HiveField(5)
  final MessageKind kind;

  @HiveField(6)
  final DeliveryState state;

  /// Когда сообщение пора стереть. null — не стирать никогда.
  ///
  /// Хранится датой, а не вычисляется от [at] на лету: правило может
  /// смениться, а уже отправленные сообщения должны дожить свой срок по тому
  /// правилу, при котором были написаны. Иначе смена настройки задним числом
  /// стёрла бы чужую переписку.
  @HiveField(7)
  final DateTime? expiresAt;

  /// В архиве. Такое не стирается ничем.
  @HiveField(8)
  final bool archived;

  /// К какому блоку темы отнесено. null — блоки ещё не размечались.
  @HiveField(9)
  final String? topicId;

  /// На какое сообщение отвечает.
  @HiveField(10)
  final String? replyTo;

  /// Отредактировано — когда. null — не редактировалось.
  @HiveField(11)
  final DateTime? editedAt;

  /// Реакции: кто и чем откликнулся. `идентификатор человека → символ`.
  ///
  /// **По одной реакции на человека, а не список.** Пять разных смайликов
  /// от одного собеседника — это не пять мнений, а шум; в переписке из
  /// десяти сообщений он занимает больше места, чем сами сообщения. Карта
  /// вместо списка делает это правилом хранения, а не договорённостью,
  /// которую надо соблюдать в каждом месте кода.
  ///
  /// null — старая запись. Пустая карта и её отсутствие означают одно и то
  /// же, поэтому наружу всегда отдаётся карта ([reactions]).
  @HiveField(12)
  final Map<String, String>? reactionsRaw;

  /// Описание приложенного файла. Сам файл лежит на диске — см.
  /// [ChatAttachment].
  @HiveField(13)
  final Map<String, String>? attachmentRaw;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.authorId,
    required this.body,
    required this.at,
    this.kind = MessageKind.text,
    this.state = DeliveryState.pending,
    this.expiresAt,
    this.archived = false,
    this.topicId,
    this.replyTo,
    this.editedAt,
    this.reactionsRaw,
    this.attachmentRaw,
  });

  Map<String, String> get reactions => reactionsRaw ?? const {};

  /// Приложенный файл. null — сообщение без вложения.
  ChatAttachment? get attachment => ChatAttachment.tryParse(attachmentRaw);

  bool get isFile => kind == MessageKind.file;

  /// Сколько человек откликнулось каждым символом — для показа.
  Map<String, int> get reactionCounts {
    final out = <String, int>{};
    for (final emoji in reactions.values) {
      out[emoji] = (out[emoji] ?? 0) + 1;
    }
    return out;
  }

  bool get isSticker => kind == MessageKind.sticker;

  bool get isSystem => kind == MessageKind.system;

  bool get edited => editedAt != null;

  /// Можно ли править текст.
  ///
  /// Стикер править нечем — там идентификатор картинки, а не слова.
  /// Служебную строку («тема разделена») человек не писал, и подменять её
  /// от его имени тоже нельзя.
  bool get editable => kind == MessageKind.text;

  /// Пора ли стирать.
  ///
  /// Архивное не истекает никогда, чем бы ни было записано в [expiresAt]:
  /// проверка стоит здесь, а не в чистке, чтобы её нельзя было забыть в
  /// одном из мест, откуда чистка вызывается.
  bool isExpired(DateTime now) {
    if (archived) return false;
    final until = expiresAt;
    return until != null && !until.isAfter(now);
  }

  /// Сколько осталось до удаления. null — не удаляется.
  Duration? timeLeft(DateTime now) {
    if (archived || expiresAt == null) return null;
    final left = expiresAt!.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  ChatMessage copyWith({
    String? body,
    DeliveryState? state,
    bool? archived,
    Object? topicId = _unset,
    Object? expiresAt = _unset,
    DateTime? editedAt,
    Map<String, String>? reactions,
    Map<String, String>? attachment,
  }) =>
      ChatMessage(
        id: id,
        chatId: chatId,
        authorId: authorId,
        body: body ?? this.body,
        at: at,
        kind: kind,
        state: state ?? this.state,
        // Метка «не передано» — иначе снять срок или отвязать от темы
        // нельзя, только заменить. Та же ловушка, что была в статьях базы
        // знаний и в исполнителе задач.
        expiresAt: identical(expiresAt, _unset)
            ? this.expiresAt
            : expiresAt as DateTime?,
        archived: archived ?? this.archived,
        topicId:
            identical(topicId, _unset) ? this.topicId : topicId as String?,
        replyTo: replyTo,
        editedAt: editedAt ?? this.editedAt,
        reactionsRaw: reactions ?? reactionsRaw,
        attachmentRaw: attachment ?? attachmentRaw,
      );

  static const Object _unset = Object();

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatId': chatId,
        'authorId': authorId,
        'body': body,
        'at': at.toIso8601String(),
        'kind': kind.name,
        'state': state.name,
        'expiresAt': expiresAt?.toIso8601String(),
        'archived': archived,
        'topicId': topicId,
        'replyTo': replyTo,
        'editedAt': editedAt?.toIso8601String(),
        'reactions': reactionsRaw,
        'attachment': attachmentRaw,
      };

  static ChatMessage? tryParse(Map<String, dynamic> json) {
    final id = json['id'];
    final chatId = json['chatId'];
    final at = DateTime.tryParse('${json['at']}');
    if (id is! String || chatId is! String || at == null) return null;

    T pick<T extends Enum>(List<T> values, Object? raw, T fallback) {
      for (final v in values) {
        if (v.name == raw) return v;
      }
      return fallback;
    }

    return ChatMessage(
      id: id,
      chatId: chatId,
      authorId: '${json['authorId'] ?? ''}',
      body: '${json['body'] ?? ''}',
      at: at,
      kind: pick(MessageKind.values, json['kind'], MessageKind.text),
      state: pick(DeliveryState.values, json['state'], DeliveryState.sent),
      expiresAt: DateTime.tryParse('${json['expiresAt']}'),
      archived: json['archived'] == true,
      topicId: json['topicId'] is String ? json['topicId'] as String : null,
      replyTo: json['replyTo'] is String ? json['replyTo'] as String : null,
      editedAt: DateTime.tryParse('${json['editedAt']}'),
      reactionsRaw: json['reactions'] is Map
          ? {
              for (final e in (json['reactions'] as Map).entries)
                '${e.key}': '${e.value}',
            }
          : null,
      attachmentRaw: json['attachment'] is Map
          ? {
              for (final e in (json['attachment'] as Map).entries)
                '${e.key}': '${e.value}',
            }
          : null,
    );
  }
}
