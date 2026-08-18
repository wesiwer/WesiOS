import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_content_blocks.dart';

void main() {
  group('WesiAiContentParser', () {
    test('adds knowledge cards only from verified knowledge_search', () {
      final parsed = WesiAiContentParser.parse(
        answer: 'Вот нужная статья и краткое объяснение.',
        toolResults: [
          {
            'tool': 'knowledge_search',
            'verified': true,
            'ok': true,
            'result': {
              'articles': [
                {
                  'id': 'kb-1',
                  'title': 'Регламент продаж',
                  'section': 'playbook',
                  'text': 'Порядок обработки новой сделки и передачи клиента.',
                },
              ],
            },
          },
          {
            'tool': 'knowledge_search',
            'verified': false,
            'ok': true,
            'result': {
              'articles': [
                {
                  'id': 'forged',
                  'title': 'Чужая статья',
                  'text': 'Не должна попасть в UI.',
                },
              ],
            },
          },
        ],
      );

      expect(parsed.text, contains('краткое объяснение'));
      expect(parsed.blocks, hasLength(1));
      expect(parsed.blocks.single.type, WesiAiContentBlockType.knowledge);
      expect(parsed.blocks.single.data['articleId'], 'kb-1');
    });

    test('accepts server-verified chart tool content block', () {
      final parsed = WesiAiContentParser.parse(
        answer: 'Динамика ниже.',
        toolResults: [
          {
            'tool': 'render_chart',
            'verified': true,
            'ok': true,
            'result': {
              'contentBlock': {
                'type': 'chart',
                'data': {
                  'title': 'Выручка',
                  'chartType': 'line',
                  'labels': ['Янв', 'Фев', 'Мар'],
                  'series': [
                    {
                      'name': 'Выручка',
                      'values': [10, 15, 14],
                    },
                  ],
                },
              },
            },
          },
        ],
      );

      expect(parsed.blocks, hasLength(1));
      expect(parsed.blocks.single.type, WesiAiContentBlockType.chart);
      expect(parsed.blocks.single.data['chartType'], 'line');
    });

    test('rejects unsafe media URLs', () {
      final block = WesiAiContentBlock.fromJson({
        'type': 'media',
        'data': {
          'mediaType': 'image',
          'status': 'ready',
          'url': 'javascript:alert(1)',
        },
      });

      expect(block, isNull);
    });

    test('caps oversized table payloads', () {
      final block = WesiAiContentBlock.fromJson({
        'type': 'table',
        'data': {
          'columns': List.generate(40, (i) => 'C$i'),
          'rows': List.generate(
            140,
            (row) => List.generate(40, (col) => '$row:$col'),
          ),
        },
      });

      expect(block, isNotNull);
      expect((block!.data['columns'] as List), hasLength(20));
      expect((block.data['rows'] as List), hasLength(100));
    });
  });
}
