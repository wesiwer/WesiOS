import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/chats/models/chat_message.dart';
import 'package:wesios/features/chats/widgets/topic_divider.dart';

/// Кнопка «Разделить» в карточке вопроса.
///
/// Она записывала метку темы на сообщения — и всё. Разметку ленты никто по
/// этой метке не строил: в хранилище что-то менялось, на экране не менялось
/// ничего. Со стороны человека кнопка просто не работала, и заметить это
/// тестом было нечем — проверялось хранилище, а не картинка.
///
/// Здесь проверяется именно то, что видит человек: где встанет заголовок.
void main() {
  final base = DateTime.utc(2026, 8, 5, 10);

  ChatMessage msg(int i, String text, {String? topicId, bool system = false}) =>
      ChatMessage(
        id: 'm$i',
        chatId: 'c',
        authorId: i.isEven ? 'a' : 'b',
        body: text,
        at: base.add(Duration(minutes: i * 2)),
        kind: system ? MessageKind.system : MessageKind.text,
        topicId: topicId,
      );

  /// Разговор об одном: сам по себе делиться не должен.
  List<ChatMessage> smooth({String? topicFrom, int at = 0}) => [
        for (var i = 0; i < 6; i++)
          msg(
            i,
            'Договор с поставщиком, приложение с ценами, всё по договору $i',
            topicId: topicFrom != null && i >= at ? topicFrom : null,
          ),
      ];

  test('без ручного разделения заголовков нет', () {
    final layout = TopicDivider.planFor(smooth());
    expect(layout.headers, isEmpty,
        reason: 'ровный разговор об одном делить не за что');
  });

  test('после разделения заголовок появляется ровно там, где разделили', () {
    final layout = TopicDivider.planFor(smooth(topicFrom: 't1', at: 3));
    expect(layout.headers.keys, contains(3));
    expect(layout.headerAt(3), isNotNull);
    expect(layout.headerAt(3), isNot('Без темы'));
  });

  test('у ручного блока осмысленное название, а не заглушка', () {
    final messages = [
      msg(0, 'Отгрузка на склад в Пушкино, двести коробок'),
      msg(1, 'Принял, машина будет в четверг'),
      msg(2, 'Зарплату переводим в четверг всем сотрудникам', topicId: 't1'),
      msg(3, 'Зарплата это отдельно, предупрежу людей', topicId: 't1'),
      msg(4, 'По зарплате вопросов нет', topicId: 't1'),
    ];
    final title = TopicDivider.planFor(messages).headerAt(2);
    expect(title, isNotNull);
    // Название считается из слов самого блока — значит там про зарплату,
    // а не про склад.
    expect(title!.toLowerCase(), contains('зарплат'));
  });

  test('про разделённое место больше не спрашивают', () {
    // Иначе человек отвечает на вопрос, а вопрос возвращается — и кнопка
    // выглядит бесполезной даже когда работает.
    final messages = [
      for (var i = 0; i < 4; i++) msg(i, 'Про склад и отгрузку номер $i'),
      for (var i = 4; i < 8; i++)
        msg(i, 'Совершенно другие слова: прайс поставщика комплектующие $i',
            topicId: 't1'),
    ];
    final layout = TopicDivider.planFor(messages);
    expect(layout.headers.keys, contains(4));
    expect(layout.questionAt(4), isNull);
  });

  test('служебные строки не сдвигают заголовок', () {
    // Разбор идёт без служебных строк, а лента рисует их наравне со всеми.
    // Без пересчёта позиций заголовок уезжал вверх на столько строк,
    // сколько служебных оказалось выше.
    final messages = [
      msg(0, 'Иван — в группе', system: true),
      msg(1, 'Отгрузка на склад, двести коробок'),
      msg(2, 'Принял, машина в четверг'),
      msg(3, 'Прайс поставщика вырос на восемь процентов', topicId: 't1'),
      msg(4, 'Прайс придётся пересматривать', topicId: 't1'),
      msg(5, 'По прайсу решим завтра', topicId: 't1'),
    ];
    final layout = TopicDivider.planFor(messages);
    expect(layout.headers.keys, contains(3),
        reason: 'граница стоит на том сообщении, где её поставил человек');
  });

  test('два разделения дают два заголовка', () {
    final messages = [
      msg(0, 'Про склад и отгрузку коробок'),
      msg(1, 'Принял по складу'),
      msg(2, 'Прайс поставщика вырос', topicId: 't1'),
      msg(3, 'По прайсу решим завтра', topicId: 't1'),
      msg(4, 'Зарплата в четверг всем', topicId: 't2'),
      msg(5, 'Предупрежу людей про зарплату', topicId: 't2'),
    ];
    final layout = TopicDivider.planFor(messages);
    expect(layout.headers.keys, containsAll([2, 4]));
  });

  test('короткая переписка тоже делится вручную', () {
    // Автоматическая разметка на трёх сообщениях не работает — данных мало.
    // Но если человек разделил сам, показать это обязаны.
    final messages = [
      msg(0, 'Первое'),
      msg(1, 'Второе про другое совсем', topicId: 't1'),
      msg(2, 'Третье'),
    ];
    expect(TopicDivider.planFor(messages).headers.keys, contains(1));
  });
}
