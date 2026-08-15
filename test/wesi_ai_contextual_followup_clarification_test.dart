import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_chat_models.dart';
import 'package:wesios/features/ai/wesi_ai_chat_ui.dart';
import 'package:wesios/features/ai/widgets/wesi_ai_rich_message.dart';

void main() {
  test('follow-up suggestions follow the current conversation topic', () {
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

    expect(android.join(' ').toLowerCase(), contains('android'));
    expect(android.join(' ').toLowerCase(), contains('kotlin'));
    expect(domain.join(' ').toLowerCase(), contains('домен'));
    expect(android, isNot(equals(domain)));
  });

  testWidgets('question block sends a selected quick answer', (tester) async {
    String? answer;
    const text = '''Нужно уточнение.\n\n```question\n{"prompt":"Какая платформа нужна?","options":["Android","iOS","Windows"],"allowOther":true}\n```''';

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

  testWidgets('malformed question JSON fails closed to code rendering', (tester) async {
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
