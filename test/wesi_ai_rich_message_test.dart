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
