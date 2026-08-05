import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../team/services/team_service.dart';
import '../models/chat_attachment.dart';
import '../models/chat_message.dart';
import '../models/chat_policy.dart';
import '../models/chat_thread.dart';
import 'attachment_store.dart';
import 'chat_delivery.dart';
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

  /// Мои ли это разговоры.
  ///
  /// Проверка не формальная. Во-первых, из группы можно выйти — и тогда она
  /// обязана пропасть из списка, хотя запись остаётся, чтобы остальные
  /// участники увидели уход. Во-вторых, синхронизация приносит на устройство
  /// **все** записи коллекции, а не только свои: без этого условия человек
  /// увидел бы у себя чужие групповые разговоры, к которым не имеет
  /// отношения.
  static bool mine(ChatThread chat) => chat.participantIds.contains(meId);

  /// Разговоры по свежести: закреплённые сверху, дальше — по последнему
  /// сообщению. Разговор без единого сообщения падает вниз, но не исчезает:
  /// его завели осознанно.
  static List<ChatThread> all({ChatKind? kind, DateTime? now}) {
    final box = _opened;
    if (box == null) return const [];
    final list = [
      for (final c in box.values)
        if ((kind == null || c.kind == kind) && mine(c)) c,
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
  ///
  /// Служебные строки не считаются: переименование группы — не сообщение, и
  /// красный кружок «вам написали» из-за него загорается зря. Один такой
  /// кружок ни о чём — и человек перестаёт им верить.
  static int unreadOf(ChatThread chat, {DateTime? now}) {
    final since = chat.lastOpenedAt;
    final me = meId;
    return MessageStore.of(chat.id, now: now)
        .where((m) =>
            !m.isSystem &&
            m.authorId != me &&
            (since == null || m.at.isAfter(since)))
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
      isGroupRaw: false,
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
      isGroupRaw: true,
    );
    await save(chat);
    return chat;
  }

  /// Написать в разговор.
  ///
  /// Экраны отправляют **через это**, а не напрямую в хранилище: только здесь
  /// известно и сколько сообщение живёт (у чата может быть свой срок), и
  /// уедет ли оно куда-нибудь вообще. Оба правила, разбросанные по экранам,
  /// разъехались бы при первом же новом месте отправки.
  static Future<ChatMessage?> send({
    required String chatId,
    required String body,
    MessageKind kind = MessageKind.text,
    String? replyTo,
    DateTime? now,
  }) async {
    final chat = byId(chatId);
    if (chat == null) return null;
    return MessageStore.send(
      chatId: chat.id,
      authorId: meId,
      body: body,
      kind: kind,
      replyTo: replyTo,
      lifetime: chat.lifetime,
      state: ChatDelivery.initialFor(chat),
      now: now,
    );
  }

  /// Приложить файл к разговору.
  ///
  /// Сообщение создаётся первым и **только потом** к нему кладётся файл:
  /// имя файла на диске содержит идентификатор сообщения, а до создания
  /// сообщения его неоткуда взять. Если файл положить не удалось, сообщение
  /// удаляется — пустой пузырь без вложения хуже, чем отсутствие пузыря.
  ///
  /// Возвращает сообщение либо код отказа строкой ([AttachmentStore.tooBig]
  /// и прочие).
  static Future<Object?> sendFile({
    required String chatId,
    required String sourcePath,
    String? displayName,
    String caption = '',
    DateTime? now,
  }) async {
    final chat = byId(chatId);
    if (chat == null) return null;

    final message = await MessageStore.send(
      chatId: chat.id,
      authorId: meId,
      // Подпись под файлом — это тело сообщения. Пустое тело хранилище не
      // примет, поэтому при отсутствии подписи кладём имя файла: в списке
      // разговоров и в поиске оно и нужно.
      body: caption.trim().isEmpty
          ? (displayName ?? sourcePath.split(Platform.pathSeparator).last)
          : caption.trim(),
      kind: MessageKind.file,
      lifetime: chat.lifetime,
      state: ChatDelivery.initialFor(chat),
      now: now,
    );
    if (message == null) return null;

    final result = await AttachmentStore.take(
      sourcePath: sourcePath,
      messageId: message.id,
      displayName: displayName,
    );

    if (result is! ChatAttachment) {
      await MessageStore.remove(message.id);
      return result;
    }

    await MessageStore.put(
        message.copyWith(attachment: result.toMap()));
    return MessageStore.byId(message.id);
  }

  /// Служебная строка в ленте: «такого-то добавили», «такой-то вышел».
  ///
  /// Пишется сообщением, а не всплывающей подсказкой, потому что состав
  /// группы — часть разговора: через месяц должно быть видно, кто и когда
  /// в нём появился.
  static Future<void> _note(String chatId, String text,
      {DateTime? now}) async {
    final chat = byId(chatId);
    if (chat == null) return;
    await MessageStore.send(
      chatId: chatId,
      authorId: meId,
      body: text,
      kind: MessageKind.system,
      lifetime: chat.lifetime,
      state: ChatDelivery.initialFor(chat),
      now: now,
    );
  }

  // ------------------------------------------------------------------ группа

  /// Переименовать группу. Пустое имя не принимается: разговор без названия
  /// показался бы в списке словом «Группа» рядом с другой такой же.
  static Future<ChatThread?> rename(String chatId, String title) async {
    final chat = _opened?.get(chatId);
    final clean = title.trim();
    if (chat == null || clean.isEmpty || clean == chat.title) return chat;
    await save(chat.copyWith(title: clean));
    return byId(chatId);
  }

  /// Задать состав группы.
  ///
  /// Себя из состава выкинуть нельзя — для этого есть [leave], и разница
  /// принципиальна: «убрать себя» молча оставило бы разговор без хозяина, а
  /// уход — это отдельное решение с отметкой в ленте.
  static Future<ChatThread?> setMembers(
    String chatId,
    Iterable<String> memberIds, {
    DateTime? now,
  }) async {
    final chat = _opened?.get(chatId);
    if (chat == null || !chat.isGroup) return chat;

    final me = meId;
    final next = <String>{me, ...memberIds}.toList()..sort();
    final before = chat.participantIds.toSet();
    final added = next.where((id) => !before.contains(id)).toList();
    final gone = before.where((id) => !next.contains(id)).toList();
    if (added.isEmpty && gone.isEmpty) return chat;

    await save(chat.copyWith(participantIds: next));
    for (final id in added) {
      await _note(chatId, '${_nameOf(id)} — в группе', now: now);
    }
    for (final id in gone) {
      await _note(chatId, '${_nameOf(id)} больше не в группе', now: now);
    }
    return byId(chatId);
  }

  /// Выйти из группы.
  ///
  /// Запись остаётся и уезжает дальше — иначе остальные участники не узнали
  /// бы об уходе вовсе. У себя разговор пропадает из списка сам: [all]
  /// показывает только те, где я состою.
  ///
  /// Своя переписка при этом стирается — кроме архивной. Уйти из группы и
  /// продолжать хранить её разговор у себя в телефоне — это не уход.
  static Future<void> leave(String chatId, {DateTime? now}) async {
    final chat = _opened?.get(chatId);
    if (chat == null || !chat.isGroup) return;
    final me = meId;
    if (!chat.participantIds.contains(me)) return;

    // Порядок важен: сначала стираем свою переписку, потом отметку об уходе.
    // Наоборот — и отметка попала бы под ту же чистку, а надгробие от неё
    // уехало бы дальше и стёрло бы её у остальных. То есть уход остался бы
    // незамеченным ровно для тех, кому он и предназначен.
    await MessageStore.clearChat(chatId);
    await _note(chatId, '${_nameOf(me)} вышел из группы', now: now);
    await save(chat.copyWith(
      participantIds: [
        for (final p in chat.participantIds)
          if (p != me) p,
      ],
    ));
  }

  static String _nameOf(String id) =>
      TeamService.byId(id)?.displayName ?? 'Участник';

  // ------------------------------------------------------------ срок хранения

  /// Сколько живут сообщения этого разговора на самом деле.
  static Duration lifetimeOf(ChatThread chat) =>
      chat.lifetime ?? MessageStore.defaultLifetime;

  /// Сроки, между которыми выбирает человек. null — общее правило.
  static const List<int?> lifetimeChoices = [null, 7, 90, 365];

  /// Поставить разговору свой срок хранения.
  ///
  /// Если срок вырос — уже написанное доживёт по новому правилу
  /// ([MessageStore.extendLifetime]). Если уменьшился — старое доживает по
  /// старому: настройка не должна стирать переписку задним числом.
  ///
  /// Возвращает, скольким сообщениям продлился срок.
  static Future<int> setLifetime(
    String chatId,
    int? days, {
    DateTime? now,
  }) async {
    final chat = _opened?.get(chatId);
    if (chat == null) return 0;

    final was = lifetimeOf(chat);
    await save(chat.copyWith(lifetimeDays: days));

    final updated = byId(chatId);
    if (updated == null) return 0;
    final become = lifetimeOf(updated);
    if (become <= was) return 0;
    return MessageStore.extendLifetime(chatId, become, now: now);
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
    // Служебная строка автора не имеет: «Вы: Иван — в группе» читается так,
    // будто это кто-то сказал, а не случилось.
    if (last.isSystem) return last.body;

    final mine = last.authorId == meId;
    final who = mine
        ? 'Вы: '
        : (chat.isGroup
            ? '${TeamService.byId(last.authorId)?.displayName ?? ''}: '
            : '');
    final body = switch (last.kind) {
      MessageKind.sticker => 'стикер',
      // Название файла, а не подпись: в списке разговоров важнее «что
      // прислали», чем комментарий к этому.
      MessageKind.file =>
        last.attachment?.isImage == true ? 'картинка' : 'файл',
      MessageKind.system => last.body,
      MessageKind.text => last.body,
    };
    return '$who$body';
  }
}
