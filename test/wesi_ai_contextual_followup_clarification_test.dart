import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_chat_models.dart';
import 'package:wesios/features/ai/wesi_ai_chat_ui.dart';
import 'package:wesios/features/ai/widgets/wesi_ai_rich_message.dart';

void main() {
  test('follow-up suggestions follow topic and user intent', () {
    final android = WesiAiChatUi.followUps(
      answer: 'Проверил сборку.',
      lastUserText: 'Почему Android release падает на Kotlin plugin?',
      persona: WesiAiPersona.zane,
    );
    final domain = WesiAiChatUi.followUps(
      answer: 'Проверил DNS.',
      lastUserText: 'Почему домен перестал делегироваться после регистрации?',
      persona: WesiAiPersona.zane,
    );
    final creative = WesiAiChatUi.followUps(
      answer: 'Можно сделать несколько визуальных направлений.',
      lastUserText: 'Придумай концепцию обложки для ночного рэп-релиза',
      persona: WesiAiPersona.nirvana,
    );
    final budget = WesiAiChatUi.followUps(
      answer: 'Бюджет можно разложить по сценариям.',
      lastUserText: 'Посчитай бюджет рекламной кампании на месяц',
      persona: WesiAiPersona.zane,
    );

    final androidText = android.join(' ').toLowerCase();
    final creativeText = creative.join(' ').toLowerCase();
    final budgetText = budget.join(' ').toLowerCase();
    expect(androidText, contains('android'));
    expect(androidText, contains('kotlin'));
    expect(androidText,
        anyOf(contains('причин'), contains('исправ'), contains('лог')));
    expect(domain.join(' ').toLowerCase(), contains('домен'));
    expect(creativeText, contains('облож'));
    expect(creativeText,
        anyOf(contains('направлен'), contains('иде'), contains('альтернатив')));
    expect(budgetText, contains('бюджет'));
    expect(budgetText,
        anyOf(contains('расч'), contains('допущ'), contains('сценар')));
    expect(android, isNot(equals(domain)));
    expect(android, isNot(equals(creative)));
    expect(creative, isNot(equals(budget)));
  });

  testWidgets('question block sends a selected quick answer', (tester) async {
    String? answer;
    const text =
        '''Нужно уточнение.\n\n```question\n{"prompt":"Какая платформа нужна?","options":["Android","iOS","Windows"],"allowOther":true}\n```''';

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WesiAiRichMessage(
          messageId: 'm1',
          text: text,
          onQuickReply: (value) async => answer = value,
        ),
      ),
    ));

    expect(WesiAiRichParser.hasClarification(text), isTrue);
    expect(find.text('Какая платформа нужна?'), findsOneWidget);
    expect(find.text('Свой ответ'), findsOneWidget);
    await tester.tap(find.text('Android'));
    await tester.pump();
    expect(answer, 'Android');
  });

  testWidgets('malformed question JSON fails closed to code rendering',
      (tester) async {
    const text = '```question\nnot-json\n```';
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: WesiAiRichMessage(messageId: 'm2', text: text),
      ),
    ));
    expect(WesiAiRichParser.hasClarification(text), isFalse);
    expect(find.text('question'), findsOneWidget);
    expect(find.text('not-json'), findsOneWidget);
  });
}
