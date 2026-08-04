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

  const ChatThread({
    required this.id,
    required this.kindName,
    required this.participantIds,
    this.title = '',
    required this.createdAt,
    this.pinned = false,
    this.muted = false,
    this.lastOpenedAt,
  });

  ChatKind get kind =>
      kindName == ChatKind.personal.name ? ChatKind.personal : ChatKind.work;

  bool get isGroup => participantIds.length > 2;

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
      );

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
    );
  }
}
