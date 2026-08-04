import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../team/services/team_service.dart';
import '../models/chat_message.dart';
import '../models/chat_policy.dart';
import '../models/chat_thread.dart';
import 'message_store.dart';

/// Разговоры.
///
/// Разговор двоих заводится сам, при первом сообщении, и его идентификатор
/// считается из участников — поэтому у обоих собеседников он получается
/// одинаковым. Случайный дал бы две ветки на одну пару людей.
class ChatService {
  static const String boxName = 'wesios_chats';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Box<ChatThread>? _box;

  static Future<Box<ChatThread>> open() async {
    final box = _box;
    if (box != null && box.isOpen) return box;
    return _box = Hive.isBoxOpen(boxName)
        ? Hive.box<ChatThread>(boxName)
        : await Hive.openBox<ChatThread>(boxName);
  }

  static Box<ChatThread>? get _opened {
    final box = _box;
    if (box != null && box.isOpen) return box;
    if (!Hive.isBoxOpen(boxName)) return null;
    return _box = Hive.box<ChatThread>(boxName);
  }

  /// Кто сейчас за приложением.
  static String get meId =>
      TeamService.current?.id ?? TeamService.owner?.id ?? 'owner';

  // ------------------------------------------------------------------ список

  /// Разговоры по свежести: закреплённые сверху, дальше — по последнему
  /// сообщению. Разговор без единого сообщения падает вниз, но не исчезает:
  /// его завели осознанно.
  static List<ChatThread> all({ChatKind? kind, DateTime? now}) {
    final box = _opened;
    if (box == null) return const [];
    final list = [
      for (final c in box.values)
        if (kind == null || c.kind == kind) c,
    ];
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final la = MessageStore.lastOf(a.id, now: now)?.at ?? a.createdAt;
      final lb = MessageStore.lastOf(b.id, now: now)?.at ?? b.createdAt;
      return lb.compareTo(la);
    });
    return list;
  }

  static ChatThread? byId(String id) => _opened?.get(id);

  /// Сколько сообщений человек ещё не видел.
  static int unreadOf(ChatThread chat, {DateTime? now}) {
    final since = chat.lastOpenedAt;
    final me = meId;
    return MessageStore.of(chat.id, now: now)
        .where((m) =>
            m.authorId != me && (since == null || m.at.isAfter(since)))
        .length;
  }

  // ------------------------------------------------------------------ запись

  static Future<void> save(ChatThread chat) async {
    await _opened?.put(chat.id, chat);
    revision.value++;
  }

  /// Найти или завести разговор с человеком.
  static Future<ChatThread> direct(
    String otherId, {
    ChatKind kind = ChatKind.work,
    DateTime? now,
  }) async {
    final me = meId;
    final id = ChatThread.directId(me, otherId, kind);
    final existing = _opened?.get(id);
    if (existing != null) return existing;

    final chat = ChatThread(
      id: id,
      kindName: kind.name,
      participantIds: [me, otherId]..sort(),
      createdAt: now ?? DateTime.now(),
    );
    await save(chat);
    return chat;
  }

  /// Завести группу.
  static Future<ChatThread> group({
    required String title,
    required List<String> memberIds,
    ChatKind kind = ChatKind.work,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final members = <String>{meId, ...memberIds}.toList()..sort();
    final chat = ChatThread(
      // У группы идентификатор случайный: две группы с одним составом —
      // это две разные группы, в отличие от разговора двоих.
      id: 'group:${at.microsecondsSinceEpoch}',
      kindName: kind.name,
      participantIds: members,
      title: title.trim(),
      createdAt: at,
    );
    await save(chat);
    return chat;
  }

  /// Отметить, что разговор открыли, — по этому считается непрочитанное.
  static Future<void> markOpened(String chatId, {DateTime? now}) async {
    final chat = _opened?.get(chatId);
    if (chat == null) return;
    await save(chat.copyWith(lastOpenedAt: now ?? DateTime.now()));
  }

  static Future<void> togglePinned(String chatId) async {
    final chat = _opened?.get(chatId);
    if (chat == null) return;
    await save(chat.copyWith(pinned: !chat.pinned));
  }

  static Future<void> toggleMuted(String chatId) async {
    final chat = _opened?.get(chatId);
    if (chat == null) return;
    await save(chat.copyWith(muted: !chat.muted));
  }

  /// Удалить разговор вместе с перепиской.
  ///
  /// Архивные сообщения остаются: в этом смысл архива, и удаление чата не
  /// должно быть лазейкой в обход него.
  static Future<void> remove(String chatId) async {
    await MessageStore.clearChat(chatId);
    await _opened?.delete(chatId);
    revision.value++;
  }

  /// Как показать разговор в списке.
  static String titleOf(ChatThread chat) {
    if (chat.title.trim().isNotEmpty) return chat.title.trim();
    final other = chat.otherThan(meId);
    if (other != null) {
      final person = TeamService.byId(other);
      if (person != null) return person.displayName;
    }
    return chat.isGroup ? 'Группа' : 'Разговор';
  }

  /// Короткая строка под названием: кто и что сказал последним.
  static String previewOf(ChatThread chat, {DateTime? now}) {
    final last = MessageStore.lastOf(chat.id, now: now);
    if (last == null) return '';
    final mine = last.authorId == meId;
    final who = mine
        ? 'Вы: '
        : (chat.isGroup
            ? '${TeamService.byId(last.authorId)?.displayName ?? ''}: '
            : '');
    final body = switch (last.kind) {
      MessageKind.sticker => 'стикер',
      MessageKind.system => last.body,
      MessageKind.text => last.body,
    };
    return '$who$body';
  }
}
