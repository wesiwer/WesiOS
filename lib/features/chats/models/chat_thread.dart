import 'package:hive/hive.dart';

import 'chat_policy.dart';

part 'chat_thread.g.dart';

/// Разговор.
///
/// **Почему тип чата хранится строкой, а не перечислением.** [ChatKind] живёт
/// в `chat_policy.dart` — файле, где записано решение владельца о том, кто
/// может читать переписку. Тащить туда Hive значило бы смешать договорённость
/// с тем, как она лежит на диске. Один короткий getter дешевле.
@HiveType(typeId: 25)
class ChatThread {
  @HiveField(0)
  final String id;

  /// `work` или `personal`. См. [kind].
  @HiveField(1)
  final String kindName;

  /// Кто участвует — идентификаторы людей из состава, включая себя.
  @HiveField(2)
  final List<String> participantIds;

  /// Название. Для разговора двоих пусто — там показывается имя собеседника,
  /// и хранить его копией значило бы получить два разных имени у одного
  /// человека после переименования.
  @HiveField(3)
  final String title;

  @HiveField(4)
  final DateTime createdAt;

  @HiveField(5)
  final bool pinned;

  /// Без уведомлений.
  @HiveField(6)
  final bool muted;

  /// Когда человек последний раз открывал разговор — по этому считается
  /// непрочитанное.
  @HiveField(7)
  final DateTime? lastOpenedAt;

  /// Сколько дней живут сообщения этого разговора. null — общее правило.
  ///
  /// **Почему nullable, а не число со значением по умолчанию.** Записи,
  /// сохранённые до появления поля, приедут без него, и `fields[8] as int`
  /// уронил бы чтение всего бокса — то есть разом все разговоры. Та же мина,
  /// что уже была поймана на правах доступа. Плюс null здесь и по смыслу
  /// правильнее: «отдельно не настраивали» — это не то же самое, что
  /// «настроили ровно на тридцать дней», и при смене общего правила такой
  /// чат должен поехать за ним, а не остаться на старом числе.
  @HiveField(8)
  final int? lifetimeDays;

  /// Группа ли это. null — старая запись, считаем по числу участников.
  ///
  /// **Почему это отдельное поле, а не «больше двух участников».** Считать по
  /// количеству казалось экономным ровно до первой проверки:
  ///
  /// - группу из двоих завести было нельзя — она немедленно превращалась в
  ///   обычный разговор, и ни переименовать её, ни поменять состав не
  ///   получалось;
  /// - группа, из которой ушли до двоих, переставала быть группой, и выйти
  ///   из неё было уже невозможно — оставшиеся запирались внутри.
  ///
  /// Групповой разговор — это решение человека, а не следствие арифметики.
  @HiveField(9)
  final bool? isGroupRaw;

  const ChatThread({
    required this.id,
    required this.kindName,
    required this.participantIds,
    this.title = '',
    required this.createdAt,
    this.pinned = false,
    this.muted = false,
    this.lastOpenedAt,
    this.lifetimeDays,
    this.isGroupRaw,
  });

  ChatKind get kind =>
      kindName == ChatKind.personal.name ? ChatKind.personal : ChatKind.work;

  bool get isGroup => isGroupRaw ?? participantIds.length > 2;

  /// Свой срок хранения. null — общий.
  Duration? get lifetime {
    final days = lifetimeDays;
    return (days == null || days <= 0) ? null : Duration(days: days);
  }

  /// Собеседник в разговоре двоих. null для группы и для разговора с собой.
  String? otherThan(String meId) {
    if (isGroup) return null;
    for (final p in participantIds) {
      if (p != meId) return p;
    }
    return null;
  }

  ChatThread copyWith({
    String? title,
    bool? pinned,
    bool? muted,
    DateTime? lastOpenedAt,
    List<String>? participantIds,
    ChatKind? kind,
    Object? lifetimeDays = _unset,
  }) =>
      ChatThread(
        id: id,
        kindName: (kind ?? this.kind).name,
        participantIds: participantIds ?? this.participantIds,
        title: title ?? this.title,
        createdAt: createdAt,
        pinned: pinned ?? this.pinned,
        muted: muted ?? this.muted,
        lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
        // Метка «не передано»: без неё вернуть чат к общему правилу было бы
        // нечем — null означал бы «оставь как есть». Та же ловушка, что уже
        // ловилась в статьях, задачах и сообщениях.
        lifetimeDays: identical(lifetimeDays, _unset)
            ? this.lifetimeDays
            : lifetimeDays as int?,
        isGroupRaw: isGroupRaw,
      );

  static const Object _unset = Object();

  /// Устойчивый идентификатор разговора двоих.
  ///
  /// Собирается из отсортированных идентификаторов участников, поэтому у
  /// обоих собеседников получается **один и тот же**. Случайный
  /// идентификатор дал бы два разных разговора на одну пару людей, и
  /// сообщения разъехались бы по разным веткам.
  static String directId(String a, String b, ChatKind kind) {
    final pair = [a, b]..sort();
    return '${kind.name}:${pair.join('-')}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kindName,
        'participants': participantIds,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'pinned': pinned,
        'muted': muted,
        'lifetimeDays': lifetimeDays,
        'group': isGroup,
      };

  static ChatThread? tryParse(Map<String, dynamic> json) {
    final id = json['id'];
    final createdAt = DateTime.tryParse('${json['createdAt']}');
    if (id is! String || createdAt == null) return null;
    return ChatThread(
      id: id,
      kindName: '${json['kind'] ?? ChatKind.work.name}',
      participantIds: [
        for (final p in (json['participants'] as List? ?? const [])) '$p',
      ],
      title: '${json['title'] ?? ''}',
      createdAt: createdAt,
      pinned: json['pinned'] == true,
      muted: json['muted'] == true,
      lifetimeDays: json['lifetimeDays'] is num
          ? (json['lifetimeDays'] as num).toInt()
          : null,
      isGroupRaw: json['group'] is bool ? json['group'] as bool : null,
    );
  }
}
