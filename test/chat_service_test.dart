import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_endpoint.dart';
import 'package:wesios/features/chats/data/sticker_packs.dart';
import 'package:wesios/features/chats/models/chat_message.dart';
import 'package:wesios/features/chats/models/chat_policy.dart';
import 'package:wesios/features/chats/models/chat_thread.dart';
import 'package:wesios/features/chats/services/chat_delivery.dart';
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

    test('служебные строки непрочитанным не считаются', () async {
      // Переименование группы — не сообщение. Кружок «вам написали» из-за
      // него загорается зря, а кружку, который врёт, перестают верить.
      final chat = await ChatService.direct('e2', now: base);
      await MessageStore.send(
        chatId: chat.id,
        authorId: 'e2',
        body: 'Иван — в группе',
        kind: MessageKind.system,
        now: base,
      );
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

  group('группа', () {
    test('две группы с одним составом — разные разговоры', () async {
      // В отличие от разговора двоих: там одинаковый состав обязан давать
      // один и тот же чат, здесь — наоборот, «Склад» и «Склад (срочное)»
      // это два разных разговора одних и тех же людей.
      await TeamService.save(person('e3', 'Третий'));
      final a = await ChatService.group(
          title: 'Склад', memberIds: ['e2', 'e3'], now: base);
      final b = await ChatService.group(
          title: 'Склад',
          memberIds: ['e2', 'e3'],
          now: base.add(const Duration(seconds: 1)));
      expect(a.id, isNot(b.id));
      expect(ChatService.all().length, 2);
    });

    test('группа из двоих — всё равно группа', () async {
      // Считать группой «больше двух участников» казалось экономным ровно до
      // этого места: названную группу с одним человеком нельзя было бы ни
      // переименовать, ни поменять в ней состав.
      final chat =
          await ChatService.group(title: 'Склад', memberIds: ['e2'], now: base);
      expect(chat.participantIds.length, 2);
      expect(chat.isGroup, isTrue);
    });

    test('группа остаётся группой, когда людей стало двое', () async {
      // Иначе из группы, откуда ушли до двоих, выйти было бы уже нельзя —
      // оставшиеся заперты внутри.
      await TeamService.save(person('e3', 'Третий'));
      final chat = await ChatService.group(
          title: 'Склад', memberIds: ['e2', 'e3'], now: base);
      final after = await ChatService.setMembers(chat.id, ['e2'], now: base);
      expect(after!.participantIds.length, 2);
      expect(after.isGroup, isTrue);
    });

    test('разговор двоих группой не становится', () async {
      final chat = await ChatService.direct('e2', now: base);
      expect(chat.isGroup, isFalse);
      expect(await ChatService.setMembers(chat.id, ['e2', 'e3']),
          isNotNull);
      expect(ChatService.byId(chat.id)!.participantIds.length, 2);
    });

    test('я всегда в составе, даже если меня не выбрали', () async {
      final chat =
          await ChatService.group(title: 'Склад', memberIds: ['e2'], now: base);
      expect(chat.participantIds, contains('own'));
    });

    test('чужая группа не показывается в списке', () async {
      // Синхронизация приносит на устройство все записи коллекции, а не
      // только свои. Без отбора человек увидел бы у себя чужие разговоры.
      await TeamService.save(person('e3', 'Третий'));
      await ChatService.save(ChatThread(
        id: 'group:чужая',
        kindName: ChatKind.work.name,
        participantIds: ['e2', 'e3'],
        title: 'Не моё',
        createdAt: base,
      ));
      expect(ChatService.all(), isEmpty);
      // Запись при этом на месте — она просто не моя.
      expect(ChatService.byId('group:чужая'), isNotNull);
    });

    test('состав меняется, себя выкинуть нельзя', () async {
      await TeamService.save(person('e3', 'Третий'));
      final chat =
          await ChatService.group(title: 'Склад', memberIds: ['e2'], now: base);

      final after = await ChatService.setMembers(chat.id, ['e3'], now: base);
      expect(after!.participantIds, containsAll(['own', 'e3']));
      expect(after.participantIds, isNot(contains('e2')));
    });

    test('смена состава оставляет след в переписке', () async {
      await TeamService.save(person('e3', 'Третий'));
      final chat =
          await ChatService.group(title: 'Склад', memberIds: ['e2'], now: base);
      await ChatService.setMembers(chat.id, ['e2', 'e3'], now: base);

      final notes = MessageStore.of(chat.id, now: base)
          .where((m) => m.isSystem)
          .toList();
      expect(notes.length, 1);
      expect(notes.first.body, contains('Третий'));
    });

    test('выход убирает из списка, но запись остаётся', () async {
      // Удалить запись значило бы отправить надгробие — и остальные
      // участники не узнали бы об уходе вовсе.
      final chat =
          await ChatService.group(title: 'Склад', memberIds: ['e2'], now: base);
      await ChatService.leave(chat.id, now: base);

      expect(ChatService.all(), isEmpty);
      expect(ChatService.byId(chat.id), isNotNull);
      expect(ChatService.byId(chat.id)!.participantIds, isNot(contains('own')));
    });

    test('после выхода отметка об уходе не стирается своей же чисткой',
        () async {
      // Порядок действий в leave: сперва чистка переписки, потом отметка.
      // Наоборот — и отметка попала бы под чистку, а надгробие от неё стёрло
      // бы её у остальных.
      final chat =
          await ChatService.group(title: 'Склад', memberIds: ['e2'], now: base);
      await MessageStore.send(
          chatId: chat.id, authorId: 'own', body: 'Обычное', now: base);
      await ChatService.leave(chat.id, now: base);

      final left = MessageStore.of(chat.id, now: base);
      expect(left.length, 1);
      expect(left.single.isSystem, isTrue);
      expect(left.single.body, contains('вышел'));
    });

    test('выход не забирает архивное', () async {
      final chat =
          await ChatService.group(title: 'Склад', memberIds: ['e2'], now: base);
      final keep = (await MessageStore.send(
          chatId: chat.id, authorId: 'own', body: 'Важное', now: base))!;
      await MessageStore.archiveMessage(keep.id);

      await ChatService.leave(chat.id, now: base);
      expect(MessageStore.byId(keep.id), isNotNull);
    });

    test('из разговора двоих не выходят', () async {
      final chat = await ChatService.direct('e2', now: base);
      await ChatService.leave(chat.id, now: base);
      expect(ChatService.all().length, 1);
    });
  });

  group('правка сообщения', () {
    Future<ChatMessage> written({String author = 'own'}) async {
      final chat = await ChatService.direct('e2', now: base);
      return (await MessageStore.send(
          chatId: chat.id, authorId: author, body: 'Завтра в 9', now: base))!;
    }

    test('свой текст меняется и помечается', () async {
      final m = await written();
      final r = await MessageStore.edit(
          id: m.id,
          by: 'own',
          body: 'Завтра в 10',
          now: base.add(const Duration(minutes: 1)));

      expect(r, MessageEditResult.ok);
      final after = MessageStore.byId(m.id)!;
      expect(after.body, 'Завтра в 10');
      expect(after.edited, isTrue);
    });

    test('чужое не правится', () async {
      // Проверка стоит в хранилище, а не только в меню: правило, живущее в
      // одном экране, обходится вторым.
      final m = await written(author: 'e2');
      expect(await MessageStore.edit(id: m.id, by: 'own', body: 'Не я писал'),
          MessageEditResult.notMine);
      expect(MessageStore.byId(m.id)!.body, 'Завтра в 9');
    });

    test('стикер править нечем', () async {
      final chat = await ChatService.direct('e2', now: base);
      final m = (await MessageStore.send(
        chatId: chat.id,
        authorId: 'own',
        body: StickerPacks.idOf('react', 0),
        kind: MessageKind.sticker,
        now: base,
      ))!;
      expect(await MessageStore.edit(id: m.id, by: 'own', body: 'текст'),
          MessageEditResult.notEditable);
    });

    test('пустой текст не принимается', () async {
      final m = await written();
      expect(await MessageStore.edit(id: m.id, by: 'own', body: '   '),
          MessageEditResult.empty);
      expect(MessageStore.byId(m.id)!.body, 'Завтра в 9');
    });

    test('тот же текст — не правка', () async {
      final m = await written();
      expect(await MessageStore.edit(id: m.id, by: 'own', body: 'Завтра в 9'),
          MessageEditResult.unchanged);
      expect(MessageStore.byId(m.id)!.edited, isFalse);
    });

    test('правка не продлевает жизнь сообщению', () async {
      // Иначе месячный срок обходился бы дописыванием точки раз в месяц —
      // ровно то, от чего он и защищает.
      final m = await written();
      final was = m.expiresAt;
      await MessageStore.edit(
          id: m.id,
          by: 'own',
          body: 'Завтра в 10',
          now: base.add(const Duration(days: 20)));
      expect(MessageStore.byId(m.id)!.expiresAt, was);
    });
  });

  group('срок хранения чата', () {
    test('новое сообщение живёт по сроку своего чата', () async {
      final chat = await ChatService.direct('e2', now: base);
      await ChatService.setLifetime(chat.id, 7, now: base);

      final m = (await ChatService.send(
          chatId: chat.id, body: 'Коротко', now: base))!;
      expect(m.expiresAt, base.add(const Duration(days: 7)));
    });

    test('продление достаёт и до уже написанного', () async {
      final chat = await ChatService.direct('e2', now: base);
      final m = (await ChatService.send(
          chatId: chat.id, body: 'Старое', now: base))!;
      expect(m.expiresAt, base.add(MessageStore.defaultLifetime));

      final touched = await ChatService.setLifetime(chat.id, 365, now: base);
      expect(touched, 1);
      expect(MessageStore.byId(m.id)!.expiresAt,
          base.add(const Duration(days: 365)));
    });

    test('укорачивание не стирает переписку задним числом', () async {
      // Поставив «неделю» на месячный чат, человек одним нажатием потерял бы
      // три недели и узнал бы об этом уже после.
      final chat = await ChatService.direct('e2', now: base);
      final m = (await ChatService.send(
          chatId: chat.id, body: 'Старое', now: base))!;

      await ChatService.setLifetime(chat.id, 7, now: base);
      expect(MessageStore.byId(m.id)!.expiresAt, m.expiresAt);
      expect(MessageStore.of(chat.id, now: base.add(const Duration(days: 10)))
          .length, 1);
    });

    test('истёкшее не воскресает продлением', () async {
      final chat = await ChatService.direct('e2', now: base);
      final m = (await ChatService.send(
          chatId: chat.id, body: 'Давнее', now: base))!;
      final later = base.add(const Duration(days: 40));

      await ChatService.setLifetime(chat.id, 365, now: later);
      expect(MessageStore.of(chat.id, now: later), isEmpty);
      expect(MessageStore.byId(m.id)!.expiresAt, m.expiresAt);
    });

    test('архивное продление не трогает', () async {
      final chat = await ChatService.direct('e2', now: base);
      final m = (await ChatService.send(
          chatId: chat.id, body: 'Важное', now: base))!;
      await MessageStore.archiveMessage(m.id);

      final touched = await ChatService.setLifetime(chat.id, 365, now: base);
      expect(touched, 0);
      expect(MessageStore.byId(m.id)!.expiresAt, isNull);
    });

    test('возврат к общему правилу', () async {
      final chat = await ChatService.direct('e2', now: base);
      await ChatService.setLifetime(chat.id, 7, now: base);
      expect(ChatService.byId(chat.id)!.lifetimeDays, 7);

      await ChatService.setLifetime(chat.id, null, now: base);
      expect(ChatService.byId(chat.id)!.lifetimeDays, isNull);
      expect(ChatService.lifetimeOf(ChatService.byId(chat.id)!),
          MessageStore.defaultLifetime);
    });
  });

  group('состояние доставки', () {
    tearDown(() async => SyncEndpoint.configure(url: ''));

    test('без сервера сообщение никуда не собирается', () async {
      // Вечные «часики» означали бы «отправляется» — и висели бы всегда,
      // выглядя как поломка.
      final chat = await ChatService.direct('e2', now: base);
      final m = (await ChatService.send(
          chatId: chat.id, body: 'Привет', now: base))!;
      expect(m.state, DeliveryState.local);
      expect(ChatDelivery.whyLocal(chat), isNotNull);
    });

    test('с сервером рабочее сообщение ждёт отправки', () async {
      await SyncEndpoint.configure(url: '203.0.113.10:8090');
      final chat =
          await ChatService.direct('e2', kind: ChatKind.work, now: base);
      final m = (await ChatService.send(
          chatId: chat.id, body: 'Привет', now: base))!;
      expect(m.state, DeliveryState.pending);
      expect(ChatDelivery.whyLocal(chat), isNull);
    });

    test('личное не уезжает даже при настроенном сервере', () async {
      // Подпись в шапке обещает «видят только собеседники». Пока нет
      // конвертного шифрования, обещание держится тем, что переписка не
      // покидает устройство.
      await SyncEndpoint.configure(url: '203.0.113.10:8090');
      final chat =
          await ChatService.direct('e2', kind: ChatKind.personal, now: base);
      final m = (await ChatService.send(
          chatId: chat.id, body: 'Личное', now: base))!;
      expect(m.state, DeliveryState.local);
      expect(ChatDelivery.whyLocal(chat), isNotNull);
    });
  });

  group('поиск по переписке', () {
    test('находит без оглядки на регистр', () async {
      final chat = await ChatService.direct('e2', now: base);
      await ChatService.send(
          chatId: chat.id, body: 'Отгрузка в Пятницу', now: base);
      await ChatService.send(chatId: chat.id, body: 'Не про это', now: base);

      final found = MessageStore.search(chat.id, 'пятниц', now: base);
      expect(found.length, 1);
      expect(found.single.body, 'Отгрузка в Пятницу');
    });

    test('стикеры не всплывают на слово из их имени', () async {
      // В теле стикера лежит `react:0`, а не картинка.
      final chat = await ChatService.direct('e2', now: base);
      await MessageStore.send(
        chatId: chat.id,
        authorId: 'own',
        body: StickerPacks.idOf('react', 0),
        kind: MessageKind.sticker,
        now: base,
      );
      expect(MessageStore.search(chat.id, 'react', now: base), isEmpty);
    });

    test('пустой запрос ничего не находит, а не находит всё', () async {
      final chat = await ChatService.direct('e2', now: base);
      await ChatService.send(chatId: chat.id, body: 'Что-то', now: base);
      expect(MessageStore.search(chat.id, '   ', now: base), isEmpty);
    });

    test('стёртое по сроку не ищется', () async {
      final chat = await ChatService.direct('e2', now: base);
      await ChatService.send(chatId: chat.id, body: 'Давнее', now: base);
      expect(
          MessageStore.search(chat.id, 'давнее',
              now: base.add(const Duration(days: 40))),
          isEmpty);
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
