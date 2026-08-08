import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/sync/pocketbase_transport.dart';

void main() {
  group('PocketBaseTransport.revisionFromResponse', () {
    test('uses newest record id and WesiOS sync stamp', () {
      final revision = PocketBaseTransport.revisionFromResponse({
        'items': [
          {
            'id': 'abc123',
            // `wesios_records` — base collection и поля `updated` в ней нет.
            // Даже если похожее поле когда-нибудь попадёт в ответ, ревизия
            // обязана следовать тому же `stamp`, по которому работает merge.
            'updated': '2099-01-01 00:00:00.000Z',
            'stamp': '2026-08-07T06:00:00Z',
          },
        ],
      });
      expect(revision, 'abc123|2026-08-07T06:00:00Z');
    });

    test('empty server has stable watermark', () {
      expect(PocketBaseTransport.revisionFromResponse({'items': []}), 'empty');
    });

    test('sync stamp is the canonical revision timestamp', () {
      final revision = PocketBaseTransport.revisionFromResponse({
        'items': [
          {'id': 'old', 'stamp': '2026-08-07T06:00:00Z'},
        ],
      });
      expect(revision, 'old|2026-08-07T06:00:00Z');
    });
  });
}
