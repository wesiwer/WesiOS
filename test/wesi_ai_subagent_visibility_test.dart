import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_activity.dart';
import 'package:wesios/features/ai/widgets/wesi_ai_rich_message.dart';

// Работа специалистов должна быть видна в ходе мыслей.
//
// Раньше события агентов шли врезками внутрь текста ответа по смещению.
// Специалисты отрабатывают ДО первой буквы ответа, поэтому смещение у всех
// нулевое: весь их след сваливался одной кучей перед первым абзацем, а в
// «Думающем» режиме — там, где человек его и ищет, — не было ничего.
void main() {
  const timeline = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'a1',
      'kind': 'agent',
      'label': 'Зову специалиста · Security Reviewer (субагент)',
      'detail': 'Поручаю: проверить форму входа на слабые проверки',
      'status': 'start',
      'textOffset': 0,
    },
    <String, dynamic>{
      'id': 'a2',
      'kind': 'agent',
      'label': 'Security Reviewer · инструмент knowledge_search (субагент)',
      'status': 'result',
      'input': '{"query": "форма входа"}',
      'output': '{"articles": []}',
      'textOffset': 0,
    },
    <String, dynamic>{
      'id': 'a3',
      'kind': 'agent',
      'label': 'Security Reviewer · готово (субагент)',
      'detail': 'Найдено две слабости в проверке пароля',
      'status': 'result',
      'textOffset': 0,
    },
    <String, dynamic>{
      'id': 'r1',
      'kind': 'reasoning',
      'label': 'Что дал Security Reviewer',
      'detail': 'Учту при сборке итогового ответа',
      'status': 'done',
      'textOffset': 0,
    },
    <String, dynamic>{
      'id': 't1',
      'kind': 'tool',
      'label': 'Инструмент · finance_summary',
      'status': 'result',
      'textOffset': 0,
    },
  ];

  Future<void> pump(WidgetTester tester, {required bool showWorkLog}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WesiAiRichMessage(
            messageId: 'm1',
            text: 'Итоговый ответ по форме входа.',
            activityRaw: timeline,
            showWorkLog: showWorkLog,
            expandWorkLog: showWorkLog,
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
  }

  // Ищем строго ВНУТРИ журнала работы. Просто find.textContaining нашёл бы
  // текст и во врезке внутри ответа — то есть проходил бы и на старом
  // поведении, которое эта правка и чинит.
  Finder inWorkLog(String text) => find.descendant(
        of: find.byType(WesiAiWorkLog),
        matching: find.textContaining(text),
      );

  testWidgets('призыв специалиста виден в ходе мыслей', (tester) async {
    await pump(tester, showWorkLog: true);
    expect(inWorkLog('Зову специалиста · Security Reviewer'), findsOneWidget);
  });

  testWidgets('призыв специалиста подписан как (субагент)', (tester) async {
    await pump(tester, showWorkLog: true);
    expect(inWorkLog('(субагент)'), findsWidgets);
  });

  testWidgets('видно, что именно поручено специалисту', (tester) async {
    await pump(tester, showWorkLog: true);
    expect(inWorkLog('проверить форму входа на слабые проверки'),
        findsOneWidget);
  });

  testWidgets('видно, каким инструментом специалист пользовался',
      (tester) async {
    await pump(tester, showWorkLog: true);
    expect(inWorkLog('Security Reviewer · инструмент knowledge_search'),
        findsOneWidget);
  });



  testWidgets('видно, чем специалист закончил', (tester) async {
    await pump(tester, showWorkLog: true);
    expect(inWorkLog('Найдено две слабости в проверке пароля'), findsOneWidget);
  });

  testWidgets('инструмент ведущей персоны остаётся врезкой в ответе',
      (tester) async {
    await pump(tester, showWorkLog: true);
    expect(inWorkLog('finance_summary'), findsNothing);
    expect(find.textContaining('finance_summary'), findsOneWidget);
  });

  testWidgets('шаг раскрывается и показывает запрос и ответ', (tester) async {
    await pump(tester, showWorkLog: true);
    // Свёрнутый шаг показывает только подпись — иначе журнал превратится в
    // простыню JSON.
    expect(find.textContaining('форма входа'), findsNothing);

    await tester.tap(inWorkLog('инструмент knowledge_search').first);
    await tester.pumpAndSettle();

    expect(find.text('Запрос'), findsOneWidget);
    expect(find.text('Ответ'), findsOneWidget);
    expect(find.textContaining('форма входа'), findsOneWidget);
    expect(find.textContaining('articles'), findsOneWidget);
  });

  test('в ход мыслей попадает всё, кроме инструментов ведущей персоны', () {
    final events = WesiAiActivityEvent.listFrom(timeline);
    final work = events
        .where((event) => event.kind != WesiAiActivityKind.tool)
        .toList();
    final inline = events
        .where((event) => event.kind == WesiAiActivityKind.tool)
        .toList();

    // Три события специалиста и одна мысль — в журнале работы.
    expect(work, hasLength(4));
    expect(work.where((e) => e.kind == WesiAiActivityKind.agent), hasLength(3));
    // Инструмент ведущей персоны остаётся врезкой: его место в тексте осмысленно.
    expect(inline, hasLength(1));
    expect(inline.single.label, contains('finance_summary'));
  });
}
