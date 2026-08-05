import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/chats/services/russian_stem.dart';
import 'package:wesios/features/chats/services/topic_chunker.dart';

/// Разбиение переписки на темы проверяется на диалогах, похожих на
/// настоящие. Тесты на выдуманных «слово1 слово2» здесь бесполезны: весь
/// смысл в том, как алгоритм ведёт себя на живой речи с короткими репликами,
/// паузами и ответами невпопад.
void main() {
  final day = DateTime.utc(2026, 8, 4, 10);

  /// Диалог из строк вида «кто|через сколько минут|текст».
  List<ChunkInput> dialog(List<String> lines) {
    var at = day;
    final out = <ChunkInput>[];
    for (var i = 0; i < lines.length; i++) {
      final parts = lines[i].split('|');
      at = at.add(Duration(minutes: int.parse(parts[1])));
      out.add(ChunkInput(
        id: 'm$i',
        authorId: parts[0],
        at: at,
        text: parts[2],
      ));
    }
    return out;
  }

  group('приведение к основе', () {
    test('падежи одного слова дают одну основу', () {
      final forms = ['договор', 'договора', 'договору', 'договором'];
      final stems = forms.map(RussianStem.of).toSet();
      expect(stems.length, 1,
          reason: 'иначе два сообщения про одно и то же выглядят как разные темы');
    });

    test('служебные слова выбрасываются', () {
      final t = RussianStem.tokens('и в не что как а то все она так');
      expect(t, isEmpty,
          reason: 'иначе самыми частыми словами каждой темы будут предлоги');
    });

    test('числа темы не описывают', () {
      expect(RussianStem.tokens('заплатили 50000 рублей'), isNot(contains('50000')));
    });

    test('короткие слова не калечатся', () {
      expect(RussianStem.of('дом'), 'дом');
      expect(RussianStem.of('склад'), 'склад');
    });

    test('ё и е — одна буква', () {
      expect(RussianStem.of('ёлка'), RussianStem.of('елка'));
    });
  });

  group('границы тем', () {
    test('долгая пауза режет сама, без вопроса', () {
      final messages = dialog([
        'a|0|Отправил документы по складу, посмотри пожалуйста',
        'b|5|Хорошо, гляну сегодня',
        'a|3|Там во втором пункте про аренду поправь',
        'b|4|Понял, поправлю аренду',
        // Следующий день.
        'a|1500|Слушай, а что по машине для доставки решили',
        'b|10|Машину берём в лизинг, доставка со следующей недели',
        'a|5|Лизинг на сколько лет получается',
      ]);

      final plan = TopicChunker.plan(messages);
      expect(plan.chunks.length, greaterThanOrEqualTo(2),
          reason: 'разговор через сутки — почти наверняка другой разговор');
      expect(plan.chunks.first.end, lessThan(4));
    });

    test('ответ на вопрос темой не считается', () {
      // Ни одного общего слова, но это явно одна тема. Без поправки на
      // «вопрос — ответ» здесь всегда находилась бы граница.
      final messages = dialog([
        'a|0|Сколько стоит доставка до Казани',
        'b|2|Четыре тысячи',
        'a|1|А если две машины',
        'b|2|Тогда семь',
      ]);

      final plan = TopicChunker.plan(messages);
      expect(plan.chunks.length, 1,
          reason: 'короткий ответ на вопрос — не новая тема');
    });

    test('слово-переключатель поднимает уверенность', () {
      final withMarker = dialog([
        'a|0|Погрузку на складе закончили, накладные подписаны',
        'b|3|Отлично, накладные сегодня отправлю',
        'a|5|Кстати, по отпуску Марины что решаем',
        'b|4|Отпуск с понедельника, замена нашлась',
      ]);
      final plan = TopicChunker.plan(withMarker);
      final noticed = plan.chunks.length > 1 ||
          plan.questions.any((b) => b.index == 2);
      expect(noticed, isTrue,
          reason: 'человек сам объявил смену темы словом «кстати»');
    });

    test('в сомнительном случае спрашивают, а не режут молча', () {
      final messages = dialog([
        'a|0|По складу в Химках всё готово, паллеты завезли',
        'b|4|Паллеты принял, разместил в третьем ряду',
        'a|50|Про новый прайс для оптовиков подумал',
        'b|6|Прайс надо пересчитать под новую скидку',
        'a|3|Скидку оптовикам оставляем прежнюю',
      ]);

      final plan = TopicChunker.plan(messages);
      final asked = plan.questions;
      expect(asked, isNotEmpty,
          reason: 'ошибочно разрезанный разговор раздражает сильнее целого');
      expect(asked.first.confidence, lessThan(TopicChunker.splitAbove));
      expect(asked.first.reason.trim(), isNotEmpty,
          reason: 'вопрос без объяснения — каприз программы, на него '
              'отвечают наугад');
    });

    test('ровный разговор на одну тему не режется', () {
      final messages = dialog([
        'a|0|Договор с поставщиком надо продлить до конца года',
        'b|3|Договор у юриста, обещал посмотреть завтра',
        'a|4|Поставщик просит поднять цену на пять процентов',
        'b|3|По договору цена фиксируется на год, пусть смотрит',
        'a|2|Тогда продлеваем договор на прежних условиях',
      ]);

      final plan = TopicChunker.plan(messages);
      expect(plan.chunks.length, 1);
      expect(plan.questions, isEmpty,
          reason: 'вопросы после каждой реплики перестают читать');
    });

    test('очень короткая переписка не режется вовсе', () {
      final messages = dialog(['a|0|Привет', 'b|1|Привет']);
      expect(TopicChunker.plan(messages).chunks.length, 1);
      expect(TopicChunker.plan(messages).questions, isEmpty);
    });

    test('пустая переписка не роняет разбор', () {
      final plan = TopicChunker.plan(const []);
      expect(plan.chunks, isEmpty);
      expect(plan.questions, isEmpty);
    });

    test('темы из одного сообщения не выделяются', () {
      final messages = dialog([
        'a|0|Аренда склада продлена на год, документы у бухгалтера',
        'b|600|Хорошо',
        'a|600|Зарплату переводим в четверг всем сотрудникам',
        'b|600|Понял, предупрежу людей про четверг',
      ]);
      final plan = TopicChunker.plan(messages);
      // Было `greaterThanOrEqualTo(1)` — проверка, которая не проверяет
      // ничего: кусок короче одного сообщения невозможен по построению, и
      // условие выполнялось бы при любой поломке. Название теста при этом
      // обещало обратное. Найдено при разборе ТЗ.
      for (final c in plan.chunks) {
        expect(c.length, greaterThanOrEqualTo(2),
            reason: 'тема из одной реплики почти всегда означает ошибку '
                'разбиения, а не настоящую тему');
      }
      // Границы не должны стоять вплотную друг к другу.
      final starts = [for (final c in plan.chunks) c.start];
      for (var i = 1; i < starts.length; i++) {
        expect(starts[i] - starts[i - 1], greaterThanOrEqualTo(2));
      }
    });
  });

  group('название темы', () {
    test('берётся из характерных слов, а не из частых', () {
      final messages = dialog([
        'a|0|По заказу нужно уточнить сроки доставки паллет',
        'b|3|Заказ подтвердил, паллеты приедут во вторник',
        'a|2|Заказ большой, паллет сорок штук',
      ]);
      final plan = TopicChunker.plan(messages);
      final title = plan.chunks.first.title.toLowerCase();
      expect(title, isNotEmpty);
      expect(title, isNot('без темы'));
    });

    test('в названии настоящие слова, а не обрубки основ', () {
      final messages = dialog([
        'a|0|Поставщик прислал новый прайс на комплектующие',
        'b|3|Прайс посмотрю вечером, комплектующие нужны срочно',
        'a|2|Комплектующие заканчиваются на складе',
      ]);
      final title = TopicChunker.plan(messages).chunks.first.title;
      // Обрубок вида «поставщ» читать нельзя — в названии должно стоять
      // слово, которое человек видел в переписке.
      expect(title, isNot(contains('поставщ,')));
      expect(title[0], title[0].toUpperCase());
    });

    test('переписка без значимых слов честно называется «без темы»', () {
      final messages = dialog([
        'a|0|да',
        'b|1|ок',
        'a|1|ну',
        'b|1|так',
      ]);
      expect(TopicChunker.plan(messages).chunks.first.title, 'Без темы');
    });

    test('название не меняется от запуска к запуску', () {
      final messages = dialog([
        'a|0|Смета по ремонту офиса выросла вдвое',
        'b|3|Смету пересчитаем, ремонт отложим до осени',
        'a|2|Ремонт офиса всё равно придётся делать',
      ]);
      final first = TopicChunker.plan(messages).chunks.first.title;
      for (var i = 0; i < 5; i++) {
        expect(TopicChunker.plan(messages).chunks.first.title, first);
      }
    });
  });
}
