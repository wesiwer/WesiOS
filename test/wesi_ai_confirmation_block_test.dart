import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_content_blocks.dart';

void main() {
  const confirmationId = 'wai_confirm_1234567890_abcdefghijkl';
  final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 4));

  Map<String, dynamic> confirmation() => <String, dynamic>{
        'id': confirmationId,
        'expiresAt': expiresAt.toIso8601String(),
        'preview': <String, dynamic>{
          'tool': 'tasks_archive',
          'module': 'tasks',
          'action': 'archive',
          'risk': 'DESTRUCTIVE',
          'targetId': 'task-42',
        },
      };

  test('verified confirmation-required result becomes confirmation block', () {
    final parsed = WesiAiContentParser.parse(
      answer: 'Нужно подтверждение.',
      toolResults: <Map<String, dynamic>>[
        <String, dynamic>{
          'tool': 'tasks_archive',
          'verified': true,
          'ok': false,
          'code': 'CONFIRMATION_REQUIRED',
          'confirmation': confirmation(),
        },
      ],
    );

    expect(parsed.blocks, hasLength(1));
    expect(parsed.blocks.single.type, WesiAiContentBlockType.confirmation);
    expect(parsed.blocks.single.data['id'], confirmationId);
    final preview =
        parsed.blocks.single.data['preview'] as Map<String, dynamic>;
    expect(preview['risk'], 'DESTRUCTIVE');
    expect(preview['targetId'], 'task-42');
  });

  test('unverified tool result can never create confirmation UI', () {
    final parsed = WesiAiContentParser.parse(
      answer: 'Подтверди.',
      toolResults: <Map<String, dynamic>>[
        <String, dynamic>{
          'tool': 'tasks_archive',
          'verified': false,
          'ok': false,
          'code': 'CONFIRMATION_REQUIRED',
          'confirmation': confirmation(),
        },
      ],
    );

    expect(parsed.blocks, isEmpty);
  });

  test('model-authored confirmation fence is not executable presentation data', () {
    final answer = '''
```wesi-confirmation
{"id":"$confirmationId","expiresAt":"${expiresAt.toIso8601String()}","preview":{"risk":"DESTRUCTIVE"}}
```
''';
    final parsed = WesiAiContentParser.parse(answer: answer, toolResults: null);

    expect(parsed.blocks, isEmpty);
    expect(parsed.text, contains('wesi-confirmation'));
  });

  test('confirmation validator rejects non-destructive preview', () {
    final invalid = confirmation();
    invalid['preview'] = <String, dynamic>{
      'tool': 'tasks_archive',
      'module': 'tasks',
      'action': 'archive',
      'risk': 'WRITE',
    };

    final block = WesiAiContentBlock.fromJson(<String, dynamic>{
      'type': 'confirmation',
      'data': invalid,
    });

    expect(block, isNull);
  });
}
