import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/sync/pocketbase_transport.dart';

void main() {
  group('PocketBaseTransport.revisionFromResponse', () {
    test('uses newest record id and PocketBase updated field', () {
      final revision = PocketBaseTransport.revisionFromResponse({
        'items': [
          {
            'id': 'abc123',
            'updated': '2026-08-07 06:00:01.123Z',
            'stamp': '2026-08-07T06:00:00Z',
          },
        ],
      });
      expect(revision, 'abc123|2026-08-07 06:00:01.123Z');
    });

    test('empty server has stable watermark', () {
      expect(PocketBaseTransport.revisionFromResponse({'items': []}), 'empty');
    });

    test('falls back to sync stamp for older server response', () {
      final revision = PocketBaseTransport.revisionFromResponse({
        'items': [
          {'id': 'old', 'stamp': '2026-08-07T06:00:00Z'},
        ],
      });
      expect(revision, 'old|2026-08-07T06:00:00Z');
    });
  });
}
