import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/features/chats/models/chat_message.dart';
import 'package:wesios/features/chats/models/chat_policy.dart';
import 'package:wesios/features/chats/models/chat_thread.dart';
import 'package:wesios/features/chats/services/chat_service.dart';
import 'package:wesios/features/chats/services/message_store.dart';

/// Что уезжает с устройства, а что нет.
///
/// Здесь проверяются не удобства, а обещания: подпись «личную переписку видят
/// только собеседники» и правило «архив не удаляется ничем». Оба держатся
/// ровно на этом отборе, и оба ломаются молча — переписка просто окажется на
/// сервере, и никто этого не заметит.
void main() {
  late Directory dir;
  final base = DateTime.utc(2026, 8, 4, 12);

  final chats = ChatsSync();
  final messages = MessagesSync();

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_chat_sync');
    Hive.init(dir.path);
    Hive.registerAdapter(MessageKindAdapter());
    Hive.registerAdapter(DeliveryStateAdapter());
    Hive.registerAdapter(ChatMessageAdapter());
    Hive.registerAdapter(ChatThreadAdapter());
    await Hive.openBox('wesios_settings');
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
  });

  Future<ChatThread> thread(String id, ChatKind kind) async {
    final chat = ChatThread(
      id: id,
      kindName: kind.name,
      participantIds: const ['own', 'e2'],
      createdAt: base,
    );
    await ChatService.save(chat);
    return chat;
  }

  Future<ChatMessage> message(String chatId, {bool archived = false}) async {
    final m = (await MessageStore.send(
        chatId: chatId, authorId: 'own', body: 'Текст', now: base))!;
    if (archived) await MessageStore.archiveMessage(m.id);
    return MessageStore.byId(m.id)!;
  }

  group('что уезжает', () {
    test('рабочий чат уезжает, личный — нет', () async {
      final work = await thread('w', ChatKind.work);
      final personal = await thread('p', ChatKind.personal);

      expect(chats.shouldSync(work), isTrue);
      expect(chats.shouldSync(personal), isFalse);
      expect(chats.local().keys, ['w']);
    });

    test('сообщение личного чата не уезжает', () async {
      await thread('p', ChatKind.personal);
      final m = await message('p');
      expect(messages.shouldSync(m), isFalse);
    });

    test('сообщение рабочего чата уезжает', () async {
      await thread('w', ChatKind.work);
      final m = await message('w');
      expect(messages.shouldSync(m), isTrue);
    });

    test('сообщение без своего чата не уезжает', () async {
      // Либо мусор, либо приехало вперёд чата. И то и другое лучше
      // пропустить: отправлять переписку, про которую неизвестно, личная она
      // или рабочая, нельзя.
      final m = await message('нет-такого-чата');
      expect(messages.shouldSync(m), isFalse);
    });

    test('архивное не уезжает', () async {
      // Архив — местное решение человека хранить это у себя навсегда.
      // Отправлять его на сервер незачем, а главное — так он не попадёт под
      // чужое удаление.
      await thread('w', ChatKind.work);
      final m = await message('w', archived: true);
      expect(messages.shouldSync(m), isFalse);
    });
  });

  group('что приезжает', () {
    test('надгробие не дотягивается до архива', () async {
      // Удаление с другого устройства идёт прямо в бокс, мимо проверки в
      // MessageStore.remove. Без этого архив терялся бы тихо.
      await thread('w', ChatKind.work);
      final kept = await message('w', archived: true);
      final plain = await message('w');

      await messages.removeById(kept.id);
      await messages.removeById(plain.id);

      expect(MessageStore.byId(kept.id), isNotNull);
      expect(MessageStore.byId(plain.id), isNull);
    });

    test('чужая правка чата не сбрасывает своё непрочитанное', () async {
      // Иначе достаточно было бы, чтобы кто-то переименовал группу, — и всё
      // непрочитанное на этом устройстве обнулилось бы разом.
      final chat = await thread('w', ChatKind.work);
      final opened = base.add(const Duration(hours: 3));
      await ChatService.save(chat.copyWith(lastOpenedAt: opened));

      final incoming = chat.copyWith(title: 'Переименовано').toJson();
      expect(await chats.applyFields(incoming), isTrue);

      final after = ChatService.byId('w')!;
      expect(after.title, 'Переименовано');
      expect(after.lastOpenedAt, opened);
    });

    test('незнакомый чат приезжает как есть', () async {
      final incoming = ChatThread(
        id: 'group:новая',
        kindName: ChatKind.work.name,
        participantIds: const ['own', 'e2', 'e3'],
        title: 'Склад',
        createdAt: base,
      ).toJson();

      expect(await chats.applyFields(incoming), isTrue);
      expect(ChatService.byId('group:новая')!.title, 'Склад');
    });

    test('битая запись не разбирается и не подставляет пустоту', () async {
      expect(await chats.applyFields({'id': 'x'}), isFalse);
      expect(await messages.applyFields({'id': 'x'}), isFalse);
    });
  });

  group('перенос', () {
    test('срок хранения чата переживает круг', () async {
      final chat = await thread('w', ChatKind.work);
      await ChatService.setLifetime('w', 90, now: base);

      final back = ChatThread.tryParse(chats.encode(ChatService.byId('w')!))!;
      expect(back.lifetimeDays, 90);
      expect(chat.lifetimeDays, isNull);
    });

    test('«докуда дочитал» на сервер не уезжает', () async {
      // Это про устройство, а не про разговор: уехав, отметка обнуляла бы
      // непрочитанное на телефоне каждый раз, когда человек заглядывает в
      // тот же чат с компьютера.
      final chat = await thread('w', ChatKind.work);
      await ChatService.save(chat.copyWith(lastOpenedAt: base));
      expect(chats.encode(ChatService.byId('w')!).containsKey('lastOpenedAt'),
          isFalse);
    });

    test('сообщение переживает круг вместе с пометками', () async {
      await thread('w', ChatKind.work);
      final m = await message('w');
      await MessageStore.edit(
          id: m.id, by: 'own', body: 'Поправлено', now: base);

      final back = ChatMessage.tryParse(
          messages.encode(MessageStore.byId(m.id)!))!;
      expect(back.id, m.id);
      expect(back.body, 'Поправлено');
      expect(back.edited, isTrue);
      expect(back.expiresAt, m.expiresAt);
    });
  });

  group('порядок коллекций', () {
    test('состав раньше разговоров, разговоры раньше сообщений', () {
      // Сообщение без своего чата не проходит даже отбор, а чат без людей
      // показался бы разговором с пустым именем.
      final names = [for (final c in SyncCodec.collections) c.name];
      expect(names.indexOf('employees'), lessThan(names.indexOf('chats')));
      expect(names.indexOf('chats'), lessThan(names.indexOf('messages')));
    });

    test('журнал следит за боксами чатов', () {
      expect(SyncCodec.boxNames, contains(ChatService.boxName));
      expect(SyncCodec.boxNames, contains(MessageStore.boxName));
    });
  });
}
