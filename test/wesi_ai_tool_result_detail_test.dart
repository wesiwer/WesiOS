import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/wesi_ai_api.dart';

void main() {
  test('tool result detail keeps safe code and human-readable message', () {
    final detail = WesiAiApi.toolResultDetail(<String, dynamic>{
      'code': 'VALIDATION_ERROR',
      'message': 'Некорректная дата события',
    });
    expect(detail, 'VALIDATION_ERROR · Некорректная дата события');
  });

  test('verified tool activity keeps message after final response merge input',
      () {
    final activity = WesiAiApi.toolActivityFromResults(<Map<String, dynamic>>[
      <String, dynamic>{
        'tool': 'calendar_create',
        'verified': true,
        'ok': false,
        'code': 'VALIDATION_ERROR',
        'message': 'Некорректная дата события',
      },
    ]);
    expect(activity, hasLength(1));
    expect(activity.single['sourceName'], 'calendar_create');
    expect(
      activity.single['detail'],
      'VALIDATION_ERROR · Некорректная дата события',
    );
  });

  test('tool result detail does not duplicate identical code/message', () {
    expect(
      WesiAiApi.toolResultDetail(<String, dynamic>{
        'code': 'FORBIDDEN',
        'message': 'FORBIDDEN',
      }),
      'FORBIDDEN',
    );
  });
}
