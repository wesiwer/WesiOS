import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/chats/models/chat_message.dart';
import 'package:wesios/features/chats/services/message_store.dart';

/// Два правила хранения противоположны друг другу, и оба легко нарушить
/// незаметно: обычная переписка обязана исчезать, архивная — оставаться
/// несмотря ни на что. Ошибка в первом превращает мессенджер в улику,
/// ошибка во втором теряет то, что человек сохранил осознанно.
void main() {
  late Directory dir;
  final base = DateTime.utc(2026, 8, 4, 12);

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_messages');
    Hive.init(dir.path);
    Hive.registerAdapter(MessageKindAdapter());
    Hive.registerAdapter(DeliveryStateAdapter());
    Hive.registerAdapter(ChatMessageAdapter());
    await MessageStore.open();
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    await Hive.box<ChatMessage>(MessageStore.boxName).clear();
  });

  Future<ChatMessage> send(
    String text, {
    String chat = 'c1',
    String author = 'a',
    DateTime? at,
  }) async =>
      (await MessageStore.send(
        chatId: chat,
        authorId: author,
        body: text,
        now: at ?? base,
      ))!;

  group('срок жизни', () {
    test('новое сообщение получает месяц жизни', () async {
      final m = await send('Привет');
      expect(m.expiresAt, base.add(const Duration(days: 30)));
      expect(m.isExpired(base), isFalse);
    });

    test('через месяц с небольшим исчезает', () async {
      await send('Старое');
      final later = base.add(const Duration(days: 31));
      expect(MessageStore.of('c1', now: later), isEmpty);
      expect(await MessageStore.sweep(now: later), 1);
    });

    test('истёкшее не показывается ещё до чистки', () async {
      // Показать сообщение, которое исчезнет через секунду, хуже, чем не
      // показать вовсе: человек успеет на него ответить.
      await send('Старое');
      final later = base.add(const Duration(days: 31));
      expect(MessageStore.of('c1', now: later), isEmpty);
      expect(Hive.box<ChatMessage>(MessageStore.boxName).length, 1,
          reason: 'чистка ещё не проходила — проверяем именно показ');
    });

    test('срок хранится датой, а не считается от времени написания', () async {
      // Иначе смена правила задним числом стёрла бы чужую переписку,
      // написанную при старом правиле.
      final m = await send('Письмо');
      expect(m.expiresAt, isNotNull);
      final stored = MessageStore.byId(m.id)!;
      expect(stored.expiresAt, m.expiresAt);
    });

    test('свой срок жизни уважается', () async {
      final m = (await MessageStore.send(
        chatId: 'c1',
        authorId: 'a',
        body: 'Однодневка',
        lifetime: const Duration(days: 1),
        now: base,
      ))!;
      expect(m.isExpired(base.add(const Duration(days: 2))), isTrue);
    });

    test('пустое сообщение не отправляется', () async {
      expect(await MessageStore.send(chatId: 'c1', authorId: 'a', body: '   '),
          isNull);
    });
  });

  group('архив', () {
    test('архивное не исчезает никогда', () async {
      final m = await send('Важное');
      await MessageStore.archiveMessage(m.id);

      final muchLater = base.add(const Duration(days: 3650));
      expect(MessageStore.byId(m.id)!.isExpired(muchLater), isFalse);
      expect(await MessageStore.sweep(now: muchLater), 0);
      expect(MessageStore.byId(m.id), isNotNull,
          reason: 'десять лет спустя архив должен быть на месте');
    });

    test('при отправке в архив срок снимается совсем', () async {
      // Оставить срок — значит оставить в архиве бомбу на случай, если
      // проверку на archived где-нибудь забудут.
      final m = await send('Важное');
      await MessageStore.archiveMessage(m.id);
      expect(MessageStore.byId(m.id)!.expiresAt, isNull);
    });

    test('архивное нельзя удалить обычным способом', () async {
      final m = await send('Важное');
      await MessageStore.archiveMessage(m.id);
      expect(await MessageStore.remove(m.id), isFalse,
          reason: 'вызывающий должен узнать об отказе, а не думать, что удалил');
      expect(MessageStore.byId(m.id), isNotNull);
    });

    test('очистка чата архив не трогает', () async {
      final keep = await send('Важное');
      await send('Обычное');
      await send('Ещё обычное');
      await MessageStore.archiveMessage(keep.id);

      expect(await MessageStore.clearChat('c1'), 2);
      expect(MessageStore.byId(keep.id), isNotNull);
    });

    test('возврат из архива снова даёт срок', () async {
      final m = await send('Важное');
      await MessageStore.archiveMessage(m.id);
      await MessageStore.unarchive(m.id, now: base);

      final back = MessageStore.byId(m.id)!;
      expect(back.archived, isFalse);
      expect(back.expiresAt, base.add(const Duration(days: 30)));
    });

    test('архив собирается из всех чатов, новое сверху', () async {
      final a = await send('Из первого', chat: 'c1', at: base);
      final b = await send('Из второго',
          chat: 'c2', at: base.add(const Duration(hours: 1)));
      await MessageStore.archiveMessage(a.id);
      await MessageStore.archiveMessage(b.id);

      final archive = MessageStore.archive();
      expect(archive.length, 2);
      expect(archive.first.id, b.id, reason: 'новое сверху');
    });
  });

  group('чтение', () {
    test('чаты не смешиваются', () async {
      await send('Первый', chat: 'c1');
      await send('Второй', chat: 'c2');
      expect(MessageStore.of('c1').length, 1);
      expect(MessageStore.of('c2').length, 1);
    });

    test('порядок по времени, а не по записи', () async {
      await send('Позже', at: base.add(const Duration(minutes: 5)));
      await send('Раньше', at: base);
      expect(MessageStore.of('c1', now: base.add(const Duration(minutes: 6)))
          .map((m) => m.body)
          .toList(),
          ['Раньше', 'Позже']);
    });

    test('последнее сообщение — для списка разговоров', () async {
      await send('Первое', at: base);
      await send('Последнее', at: base.add(const Duration(minutes: 5)));
      expect(
          MessageStore.lastOf('c1', now: base.add(const Duration(minutes: 6)))!
              .body,
          'Последнее');
    });
  });

  group('состояние и темы', () {
    test('состояние доставки меняется', () async {
      final m = await send('Привет');
      expect(m.state, DeliveryState.pending);
      await MessageStore.markState(m.id, DeliveryState.delivered);
      expect(MessageStore.byId(m.id)!.state, DeliveryState.delivered);
    });

    test('привязка к теме и отвязка обратно', () async {
      final m = await send('Про склад');
      await MessageStore.assignTopic([m.id], 't1');
      expect(MessageStore.byId(m.id)!.topicId, 't1');

      await MessageStore.assignTopic([m.id], null);
      expect(MessageStore.byId(m.id)!.topicId, isNull,
          reason: 'без метки «не передано» отвязать было бы нельзя');
    });
  });

  group('идентификаторы', () {
    test('два сообщения в одну микросекунду не затирают друг друга', () async {
      // Раньше идентификатор складывался из времени и автора, и такая пара
      // получала один и тот же ключ. На живом устройстве редкость, но когда
      // переписка приезжает с сервера пачкой — обычное дело.
      final a = await send('Первое', chat: 'c1', at: base);
      final b = await send('Второе', chat: 'c1', at: base);
      expect(a.id, isNot(b.id));
      expect(MessageStore.of('c1').length, 2);
    });

    test('идентификатор начинается со времени — записи лежат по порядку', () {
      final id = MessageStore.newId(base, 'автор');
      expect(id.startsWith('${base.microsecondsSinceEpoch}-'), isTrue);
    });

    test('тысяча подряд — ни одного повтора', () {
      final ids = {
        for (var i = 0; i < 1000; i++) MessageStore.newId(base, 'a'),
      };
      expect(ids.length, 1000);
    });
  });

  group('перенос в JSON', () {
    test('сообщение переживает круг', () async {
      final m = await send('Текст со «скобками» и —тире—');
      final back = ChatMessage.tryParse(m.toJson())!;
      expect(back.id, m.id);
      expect(back.body, m.body);
      expect(back.at, m.at);
      expect(back.expiresAt, m.expiresAt);
      expect(back.kind, m.kind);
    });

    test('битая запись не разбирается, а не подставляет пустоту', () {
      expect(ChatMessage.tryParse({'id': 'x'}), isNull);
      expect(ChatMessage.tryParse({'chatId': 'c', 'at': 'вчера'}), isNull);
    });
  });
}
