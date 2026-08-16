import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_activity.dart';
import 'package:wesios/features/ai/widgets/wesi_ai_rich_message.dart';

void main() {
  const timelineRaw = <Map<String, dynamic>>[
    <String, dynamic>{
      'type': 'activity',
      'kind': 'reasoning',
      'phase': 'done',
      'label': 'Зейн → Нирвана',
      'detail': 'Передан только ограниченный контекст задачи.',
    },
    <String, dynamic>{
      'type': 'activity',
      'kind': 'reasoning',
      'phase': 'done',
      'label': 'Нирвана · Co-Agent проверка',
      'detail': 'Независимая проверка своей специализации.',
    },
    <String, dynamic>{
      'type': 'activity',
      'kind': 'reasoning',
      'phase': 'done',
      'label': 'Нирвана → Зейн',
      'detail': 'Структурированный результат передан Lead Persona.',
    },
    <String, dynamic>{
      'type': 'activity',
      'kind': 'reasoning',
      'phase': 'done',
      'label': 'Зейн · проверка Co-Agent результата',
      'detail': 'Проверка перед интеграцией.',
    },
  ];

  test('Co-Agent activity payload remains observable status, not hidden reasoning', () {
    final events = WesiAiActivityEvent.listFrom(timelineRaw);
    expect(events, hasLength(4));
    expect(events.every((event) => event.kind == WesiAiActivityKind.reasoning), isTrue);
    expect(events.map((event) => event.label), containsAllInOrder(<String>[
      'Зейн → Нирвана',
      'Нирвана · Co-Agent проверка',
      'Нирвана → Зейн',
      'Зейн · проверка Co-Agent результата',
    ]));
    final encoded = events.map((event) => event.toJson()).toList(growable: false).toString();
    expect(encoded, isNot(contains('chain_of_thought')));
    expect(encoded, isNot(contains('hidden_reasoning')));
    expect(encoded, isNot(contains('system_prompt')));
  });

  testWidgets('Thinking shows Co-Agent work timeline', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WesiAiRichMessage(
            messageId: 'coagent-thinking',
            text: 'Финальный ответ Lead.',
            activityRaw: timelineRaw,
            showWorkLog: true,
            expandWorkLog: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Зейн → Нирвана'), findsOneWidget);
    expect(find.text('Нирвана · Co-Agent проверка'), findsOneWidget);
    expect(find.text('Нирвана → Зейн'), findsOneWidget);
    expect(find.text('Зейн · проверка Co-Agent результата'), findsOneWidget);
    expect(find.text('Финальный ответ Lead.'), findsOneWidget);
  });

  testWidgets('Classic hides Co-Agent work timeline completely', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WesiAiRichMessage(
            messageId: 'coagent-classic',
            text: 'Финальный ответ Lead.',
            activityRaw: timelineRaw,
            showWorkLog: false,
            expandWorkLog: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Зейн → Нирвана'), findsNothing);
    expect(find.text('Нирвана · Co-Agent проверка'), findsNothing);
    expect(find.text('Нирвана → Зейн'), findsNothing);
    expect(find.text('Зейн · проверка Co-Agent результата'), findsNothing);
    expect(find.text('Финальный ответ Lead.'), findsOneWidget);
  });
}
