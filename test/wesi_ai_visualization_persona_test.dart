import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/widgets/wesi_ai_rich_message.dart';
import 'package:wesios/features/ai/widgets/wesi_ai_visualization.dart';

void main() {
  group('Wesi AI inline visualizations', () {
    test('parses a markdown table into a bounded table block', () {
      const markdown = '''
| Модель | Балл |
| --- | ---: |
| A | 8 |
| B | 9 |
''';
      final blocks = WesiAiRichParser.parse(markdown.trim());
      expect(blocks, hasLength(1));
      expect(blocks.single.kind, WesiAiRichBlockKind.table);
      final table =
          WesiAiTableData.tryParseMarkdown(blocks.single.text.split('\n'));
      expect(table, isNotNull);
      expect(table!.headers, ['Модель', 'Балл']);
      expect(table.rows, [
        ['A', '8'],
        ['B', '9'],
      ]);
      expect(table.toTsv(), contains('Модель\tБалл'));
    });

    test('accepts bounded bar and scatter chart specs', () {
      final bar = WesiAiChartSpec.tryParse('''
{"type":"bar","title":"Продажи","labels":["Янв","Фев"],"series":[{"name":"₽","values":[10,15]}]}
''');
      expect(bar, isNotNull);
      expect(bar!.type, WesiAiChartType.bar);
      expect(bar.series.single.values, [10.0, 15.0]);

      final scatter = WesiAiChartSpec.tryParse('''
{"type":"scatter","title":"Связь","points":[{"x":1,"y":2},{"x":2,"y":3}]}
''');
      expect(scatter, isNotNull);
      expect(scatter!.points, hasLength(2));
    });

    test('fails closed for malformed or oversized chart specs', () {
      expect(WesiAiChartSpec.tryParse('{"type":"bar","labels":[]}'), isNull);
      expect(
        WesiAiChartSpec.tryParse(
          '{"type":"pie","labels":["A"],"series":[{"name":"x","values":[1]},{"name":"y","values":[2]}]}',
        ),
        isNull,
      );
      expect(
        WesiAiChartSpec.tryParse(
          '{"type":"bar","labels":["A"],"series":[{"name":"x","values":[1e309]}]}',
        ),
        isNull,
      );
    });

    test('recognizes wesi-chart fenced blocks separately from code', () {
      const markdown = '''
Сравнение:

```wesi-chart
{"type":"line","labels":["1","2"],"series":[{"name":"Рост","values":[2,4]}]}
```
''';
      final blocks = WesiAiRichParser.parse(markdown);
      expect(blocks.any((block) => block.kind == WesiAiRichBlockKind.chart),
          isTrue);
    });
  });

  test(
      'Nirvana keeps ordinary no-profanity voice but allows explicit creative exception',
      () {
    final text =
        File('docs/wesi_ai/personas/NIRVANA_PERSONA.md').readAsStringSync();
    expect(text, contains('ПРОФЕССИОНАЛЬНОЕ ТВОРЧЕСКОЕ ИСКЛЮЧЕНИЕ'));
    expect(text, contains('рэп/песню/художественный текст/диалог/роль'));
    expect(text, contains('В обычной речи ты не материшься'));
    expect(text, contains('не является причиной для handoff'));
  });
}
