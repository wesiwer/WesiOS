import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_activity.dart';
import 'package:wesios/features/ai/widgets/wesi_ai_rich_message.dart';

void main() {
  test(
      'rich parser separates code quotes and removes markdown markers for copy',
      () {
    const source = '''
Обычный **жирный** текст.

```dart
void main() => print('ok');
```

> Готовое сообщение
> в две строки
''';
    final blocks = WesiAiRichParser.parse(source);
    expect(
        blocks.any((block) =>
            block.kind == WesiAiRichBlockKind.code && block.language == 'dart'),
        isTrue);
    expect(
        blocks.any((block) => block.kind == WesiAiRichBlockKind.quote), isTrue);
    final plain = WesiAiRichParser.plainText(source);
    expect(plain, contains('жирный'));
    expect(plain, isNot(contains('**')));
  });

  test('display markdown normalizes inline latex without touching currency',
      () {
    const source =
        r'Счёт: $3 + 4 = 7$. Итог: $10 + 4 = \mathbf{14}$. Цена: $100';
    final display = WesiAiRichParser.displayMarkdown(source);
    expect(display, contains('3 + 4 = 7'));
    expect(display, contains('10 + 4 = 14'));
    expect(display, contains(r'$100'));
    expect(display, isNot(contains(r'$3 + 4 = 7$')));
    expect(display, isNot(contains(r'\mathbf')));
  });

  test('activity model preserves per tool diff and source', () {
    final event = WesiAiActivityEvent.fromJson({
      'id': 'tool-1',
      'type': 'tool',
      'name': 'github_file_upsert',
      'phase': 'result',
      'textOffset': 18,
      'additions': 42,
      'deletions': 7,
      'files': ['lib/a.dart'],
    });
    expect(event, isNotNull);
    expect(event!.kind, WesiAiActivityKind.tool);
    expect(event.sourceName, 'github_file_upsert');
    expect(event.additions, 42);
    expect(event.deletions, 7);
    expect(event.files, ['lib/a.dart']);
  });

  testWidgets('code and quote blocks expose quick copy controls',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: WesiAiRichMessage(
          messageId: 'm1',
          text: '```dart\nprint(1);\n```\n\n> Скопируй меня',
        ),
      ),
    ));
    expect(find.text('dart'), findsOneWidget);
    expect(find.byTooltip('Копировать код'), findsOneWidget);
    expect(find.byTooltip('Копировать'), findsOneWidget);
  });

  testWidgets('read-only tool does not render fake +0 -0 diff counters',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: WesiAiRichMessage(
          messageId: 'finance-tool',
          text: '',
          activityRaw: [
            {
              'id': 'finance-result',
              'kind': 'tool',
              'sourceName': 'finance_summary',
              'label': 'Инструмент · finance_summary',
              'status': 'result',
              'detail': '40 операций · Wesi Inc',
            }
          ],
        ),
      ),
    ));
    expect(find.text('Инструмент · finance_summary'), findsOneWidget);
    expect(find.text('40 операций · Wesi Inc'), findsOneWidget);
    expect(find.text('+0'), findsNothing);
    expect(find.text('-0'), findsNothing);
  });

  testWidgets('live work log is expanded before final answer', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WesiAiRichMessage(
          messageId: 'm2',
          text: '',
          streaming: true,
          showWorkLog: true,
          expandWorkLog: true,
          activityRaw: [
            {
              'id': 'r1',
              'kind': 'reasoning',
              'label': 'Контекст подготовлен',
            }
          ],
        ),
      ),
    ));
    expect(find.text('Ход работы…'), findsOneWidget);
    expect(find.text('Контекст подготовлен'), findsOneWidget);
  });
}
