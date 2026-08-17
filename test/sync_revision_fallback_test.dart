import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/sync/pocketbase_transport.dart';

void main() {
  test('legacy revision fallback accepts current compact server response', () {
    expect(
      PocketBaseTransport.revisionFromResponse(
        <String, dynamic>{'revision': 'record|2026-08-17T20:00:00Z'},
      ),
      'record|2026-08-17T20:00:00Z',
    );
  });

  test('legacy revision fallback still accepts historical items response', () {
    expect(
      PocketBaseTransport.revisionFromResponse(<String, dynamic>{
        'items': <Object>[
          <String, dynamic>{
            'id': 'abc',
            'stamp': '2026-08-17T19:00:00Z',
          },
        ],
      }),
      'abc|2026-08-17T19:00:00Z',
    );
  });

  test('legacy revision fallback keeps empty semantics', () {
    expect(
        PocketBaseTransport.revisionFromResponse(<String, dynamic>{}), 'empty');
  });
}
