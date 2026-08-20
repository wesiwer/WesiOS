import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_activity.dart';
import 'package:wesios/features/ai/widgets/wesi_ai_rich_message.dart';

// Thinking показывает один наблюдаемый журнал работы: публичные мысли,
// специалистов и инструменты. Детальный payload инструмента/специалиста
// открывается уже вторым нажатием и не подменяет первый уровень.
void main() {
  const timeline = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'a1',
      'kind': 'agent',
      'phase': 'planned',
      'label': 'Зову специалиста · Security Reviewer (субагент)',
      'detail': 'Поручаю: проверить форму входа на слабые проверки',
      'status': 'start',
      'textOffset': 0,
    },
    <String, dynamic>{
      'id': 'a2',
      // Инструмент субагента идёт по agent-envelope, но phase=tool должен
      // классифицироваться как инструмент для глубокого уровня.
      'kind': 'agent',
      'phase': 'tool',
      'label': 'Security Reviewer · инструмент knowledge_search (субагент)',
      'status': 'result',
      'input': '{"query": "форма входа"}',
      'output': '{"articles": []}',
      'textOffset': 0,
    },
    <String, dynamic>{
      'id': 'a3',
      'kind': 'agent',
      'phase': 'result',
      'label': 'Security Reviewer · готово (субагент)',
      'task': 'проверить форму входа на слабые проверки',
      'detail': 'Краткий вывод: Найдено две слабости в проверке пароля.\n\n'
          'Наблюдения:\n• Проверка длины недостаточна.\n\n'
          'Рекомендация: усилить серверную валидацию.',
      'status': 'result',
      'textOffset': 0,
    },
    <String, dynamic>{
      'id': 'r1',
      'kind': 'reasoning',
      'label': 'Что дал Security Reviewer',
      'detail': 'Учту найденные слабости при сборке итогового ответа.',
      'status': 'done',
      'textOffset': 0,
    },
    <String, dynamic>{
      'id': 't1',
      'kind': 'tool',
      'phase': 'result',
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

  testWidgets('на первом уровне видно, что поручено специалисту',
      (tester) async {
    await pump(tester, showWorkLog: true);
    expect(inWorkLog('проверить форму входа на слабые проверки'),
        findsOneWidget);
  });

  testWidgets('в ходе работы виден инструмент специалиста', (tester) async {
    await pump(tester, showWorkLog: true);
    expect(inWorkLog('Security Reviewer · инструмент knowledge_search'),
        findsOneWidget);
  });

  testWidgets('на первом уровне виден результат специалиста', (tester) async {
    await pump(tester, showWorkLog: true);
    expect(inWorkLog('Найдено две слабости в проверке пароля'), findsOneWidget);
  });

  testWidgets('инструмент ведущей персоны находится в ходе работы Thinking',
      (tester) async {
    await pump(tester, showWorkLog: true);
    expect(inWorkLog('finance_summary'), findsOneWidget);
    expect(find.text('Итоговый ответ по форме входа.'), findsOneWidget);
  });

  testWidgets('инструмент раскрывается вторым уровнем с входом и результатом',
      (tester) async {
    await pump(tester, showWorkLog: true);

    await tester.tap(inWorkLog('инструмент knowledge_search').first);
    await tester.pumpAndSettle();

    expect(find.text('Вход инструмента / код'), findsOneWidget);
    expect(find.text('Результат инструмента'), findsOneWidget);
    expect(find.text('{"query": "форма входа"}'), findsOneWidget);
    expect(find.text('{"articles": []}'), findsOneWidget);
  });

  testWidgets('результат субагента раскрывает поручение и подробный вывод',
      (tester) async {
    await pump(tester, showWorkLog: true);

    await tester.tap(inWorkLog('Security Reviewer · готово').first);
    await tester.pumpAndSettle();

    expect(find.text('Поручение специалисту'), findsOneWidget);
    expect(find.text('проверить форму входа на слабые проверки'), findsOneWidget);
    expect(find.text('Результат специалиста'), findsOneWidget);
    // Результат остаётся виден на первом уровне и повторяется в открытом
    // detail-sheet: это и есть ожидаемая двухуровневая навигация.
    expect(find.textContaining('Рекомендация: усилить серверную валидацию'),
        findsWidgets);
  });

  test('agent-envelope phase=tool сохраняет настоящий tool payload', () {
    final events = WesiAiActivityEvent.listFrom(timeline);
    final specialistTool = events.firstWhere((event) => event.id == 'a2');
    final specialistResult = events.firstWhere((event) => event.id == 'a3');

    expect(specialistTool.kind, WesiAiActivityKind.tool);
    expect(specialistTool.input, contains('форма входа'));
    expect(specialistTool.output, contains('articles'));
    expect(specialistResult.kind, WesiAiActivityKind.agent);
    // `task` приходит отдельным полем сервера, но второй уровень UI уже
    // умеет показывать agent input как «Поручение специалисту».
    expect(specialistResult.input,
        contains('проверить форму входа на слабые проверки'));
  });
}
