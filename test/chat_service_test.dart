import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/chats/data/sticker_packs.dart';
import 'package:wesios/features/chats/models/chat_message.dart';
import 'package:wesios/features/chats/models/chat_policy.dart';
import 'package:wesios/features/chats/models/chat_thread.dart';
import 'package:wesios/features/chats/services/chat_service.dart';
import 'package:wesios/features/chats/services/message_store.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';

void main() {
  late Directory dir;
  final base = DateTime.utc(2026, 8, 4, 12);

  EmployeeModel person(String id, String name, {bool owner = false}) =>
      EmployeeModel(
        id: id,
        login: id,
        fullName: name,
        isOwner: owner,
        permissions: owner ? TeamPermissions.owner : const TeamPermissions(),
        createdAt: base,
      );

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_chats');
    Hive.init(dir.path);
    Hive.registerAdapter(TeamPermissionsAdapter());
    Hive.registerAdapter(EmployeeModelAdapter());
    Hive.registerAdapter(MessageKindAdapter());
    Hive.registerAdapter(DeliveryStateAdapter());
    Hive.registerAdapter(ChatMessageAdapter());
    Hive.registerAdapter(ChatThreadAdapter());
    await Hive.openBox('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await MessageStore.open();
    await ChatService.open();
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    await Hive.box<ChatMessage>(MessageStore.boxName).clear();
    await Hive.box<ChatThread>(ChatService.boxName).clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box('wesios_settings').clear();
    await TeamService.save(person('own', 'Владелец', owner: true));
    await TeamService.save(person('e2', 'Иван Петров'));
  });

  group('разговор двоих', () {
    test('идентификатор одинаков с обеих сторон', () {
      // Случайный идентификатор дал бы две ветки на одну пару людей, и
      // сообщения разъехались бы: каждый писал бы в свою.
      final fromA = ChatThread.directId('a', 'b', ChatKind.work);
      final fromB = ChatThread.directId('b', 'a', ChatKind.work);
      expect(fromA, fromB);
    });

    test('рабочий и личный — разные разговоры с одним человеком', () {
      expect(ChatThread.directId('a', 'b', ChatKind.work),
          isNot(ChatThread.directId('a', 'b', ChatKind.personal)));
    });

    test('повторное открытие не заводит второй разговор', () async {
      final first = await ChatService.direct('e2', now: base);
      final second = await ChatService.direct('e2', now: base);
      expect(first.id, second.id);
      expect(ChatService.all().length, 1);
    });

    test('название берётся из состава, а не хранится копией', () async {
      // Иначе после переименования человека в контактах в чатах остался бы
      // старый вариант — два разных имени у одного человека.
      final chat = await ChatService.direct('e2', now: base);
      expect(ChatService.titleOf(chat), 'Иван Петров');

      await TeamService.save(person('e2', 'Иван Сергеевич Петров'));
      expect(ChatService.titleOf(chat), 'Иван Сергеевич Петров');
    });
  });

  group('список разговоров', () {
    test('свежие сверху', () async {
      final a = await ChatService.direct('e2', now: base);
      await TeamService.save(person('e3', 'Третий'));
      final b = await ChatService.direct('e3', now: base);

      await MessageStore.send(
          chatId: a.id, authorId: 'own', body: 'Старое', now: base);
      await MessageStore.send(
          chatId: b.id,
          authorId: 'own',
          body: 'Свежее',
          now: base.add(const Duration(hours: 1)));

      expect(ChatService.all(now: base.add(const Duration(hours: 2)))
          .first.id, b.id);
    });

    test('закреплённый всегда первый, даже если в нём тихо', () async {
      final a = await ChatService.direct('e2', now: base);
      await TeamService.save(person('e3', 'Третий'));
      final b = await ChatService.direct('e3', now: base);

      await MessageStore.send(
          chatId: b.id,
          authorId: 'own',
          body: 'Свежее',
          now: base.add(const Duration(hours: 1)));
      await ChatService.togglePinned(a.id);

      expect(ChatService.all(now: base.add(const Duration(hours: 2)))
          .first.id, a.id);
    });

    test('папки не смешиваются', () async {
      await ChatService.direct('e2', kind: ChatKind.work, now: base);
      await ChatService.direct('e2', kind: ChatKind.personal, now: base);

      expect(ChatService.all(kind: ChatKind.work).length, 1);
      expect(ChatService.all(kind: ChatKind.personal).length, 1);
      expect(ChatService.all().length, 2);
    });
  });

  group('непрочитанное', () {
    test('свои сообщения непрочитанными не считаются', () async {
      final chat = await ChatService.direct('e2', now: base);
      await MessageStore.send(
          chatId: chat.id, authorId: 'own', body: 'Моё', now: base);
      expect(ChatService.unreadOf(ChatService.byId(chat.id)!), 0);
    });

    test('чужие считаются, пока разговор не открыли', () async {
      final chat = await ChatService.direct('e2', now: base);
      await MessageStore.send(
          chatId: chat.id, authorId: 'e2', body: 'Привет', now: base);
      expect(ChatService.unreadOf(ChatService.byId(chat.id)!), 1);

      await ChatService.markOpened(chat.id,
          now: base.add(const Duration(minutes: 1)));
      expect(ChatService.unreadOf(ChatService.byId(chat.id)!), 0);
    });

    test('пришедшее после открытия снова считается', () async {
      final chat = await ChatService.direct('e2', now: base);
      await ChatService.markOpened(chat.id, now: base);
      await MessageStore.send(
          chatId: chat.id,
          authorId: 'e2',
          body: 'Позже',
          now: base.add(const Duration(minutes: 5)));
      expect(ChatService.unreadOf(ChatService.byId(chat.id)!), 1);
    });
  });

  group('удаление разговора', () {
    test('архивные сообщения переживают удаление чата', () async {
      // Удаление разговора не должно быть лазейкой в обход архива.
      final chat = await ChatService.direct('e2', now: base);
      final keep = (await MessageStore.send(
          chatId: chat.id, authorId: 'own', body: 'Важное', now: base))!;
      await MessageStore.send(
          chatId: chat.id, authorId: 'own', body: 'Обычное', now: base);
      await MessageStore.archiveMessage(keep.id);

      await ChatService.remove(chat.id);

      expect(ChatService.byId(chat.id), isNull);
      expect(MessageStore.byId(keep.id), isNotNull);
      expect(MessageStore.archive().length, 1);
    });
  });

  group('стикеры', () {
    test('идентификатор превращается в символ', () {
      final id = StickerPacks.idOf('react', 0);
      expect(StickerPacks.resolve(id), StickerPacks.all.first.items.first);
    });

    test('неизвестный стикер не превращается в пустоту', () {
      // Сообщение было отправлено — человек должен видеть, что оно есть.
      expect(StickerPacks.resolve('нет-такого:5'), '❔');
      expect(StickerPacks.resolve('мусор'), '❔');
      expect(StickerPacks.resolve('react:999'), '❔');
    });

    test('идентификаторы наборов уникальны', () {
      final ids = [for (final p in StickerPacks.all) p.id];
      expect(ids.toSet().length, ids.length);
    });

    test('в сообщении хранится идентификатор, а не символ', () async {
      // Когда символы заменятся рисованными стикерами, уже отправленные
      // сообщения покажутся новой картинкой, а не останутся текстом.
      final chat = await ChatService.direct('e2', now: base);
      final m = (await MessageStore.send(
        chatId: chat.id,
        authorId: 'own',
        body: StickerPacks.idOf('work', 2),
        kind: MessageKind.sticker,
        now: base,
      ))!;
      expect(m.body, 'work:2');
      expect(m.body, isNot(contains('🏭')));
    });

    test('предпросмотр стикера в списке — слово, а не пустой пузырь', () async {
      final chat = await ChatService.direct('e2', now: base);
      await MessageStore.send(
        chatId: chat.id,
        authorId: 'own',
        body: StickerPacks.idOf('react', 0),
        kind: MessageKind.sticker,
        now: base,
      );
      expect(ChatService.previewOf(ChatService.byId(chat.id)!),
          contains('стикер'));
    });
  });

  group('перенос в JSON', () {
    test('разговор переживает круг', () async {
      final chat = await ChatService.direct('e2',
          kind: ChatKind.personal, now: base);
      final back = ChatThread.tryParse(chat.toJson())!;
      expect(back.id, chat.id);
      expect(back.kind, ChatKind.personal);
      expect(back.participantIds, chat.participantIds);
    });

    test('битая запись не разбирается', () {
      expect(ChatThread.tryParse({'id': 'x'}), isNull);
    });
  });
}
