import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/widgets/wesi_ai_rich_message.dart';

void main() {
  const activity = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'reasoning_1',
      'kind': 'reasoning',
      'label': 'Проверяю данные',
      'detail': 'Тестовый безопасный work log',
      'status': 'done',
    },
  ];

  Future<void> pumpMessage(
    WidgetTester tester, {
    required bool showWorkLog,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WesiAiRichMessage(
            messageId: 'message_1',
            text: 'Готовый ответ',
            activityRaw: activity,
            showWorkLog: showWorkLog,
            expandWorkLog: showWorkLog,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('classic mode does not render work log banner', (tester) async {
    await pumpMessage(tester, showWorkLog: false);
    expect(find.text('Ход работы'), findsNothing);
    expect(find.text('Готовый ответ'), findsOneWidget);
  });

  testWidgets('thinking mode renders work log banner', (tester) async {
    await pumpMessage(tester, showWorkLog: true);
    expect(find.text('Ход работы'), findsOneWidget);
    expect(find.text('Проверяю данные'), findsOneWidget);
  });
}
