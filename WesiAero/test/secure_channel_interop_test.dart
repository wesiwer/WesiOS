import 'package:flutter_test/flutter_test.dart';
import 'package:wesi_aero/src/services/aero_commerce_service.dart';

void main() {
  const key =
      'WA1-0123456789abcdef0123456789abcdef-abcdefghijklmnopqrstuvwxyz123456';
  const vector = <String, dynamic>{
    'v': 1,
    'requestId': '123e4567-e89b-42d3-a456-426614174000',
    'timestamp': 1787313600000,
    'salt': 'AAECAwQFBgcICQoLDA0ODw',
    'nonce': 'EBESExQVFhcYGRob',
    'ciphertext':
        'MPpytKt9-_riXcf11TJaFbPTL39I6_4Q3IHW35dQd7ugZ3PAMogyI2ZoDKxuRcEcVTHQh0h7Gg',
    'tag': 'L2HEWwJ0WN1IvHtrz2l5FQ',
  };

  test('Dart decrypts the deterministic Node.js AES-GCM vector', () async {
    final codec = AeroSecureEnvelopeCodec();
    expect(
      await codec.decrypt(vector, key, direction: 'request'),
      {'action': 'nodes.list', 'deviceId': 'android-device-001'},
    );
  });

  test('Dart encrypts exactly the deterministic Node.js vector', () async {
    final codec = AeroSecureEnvelopeCodec();
    final envelope = await codec.encrypt(
      {'action': 'nodes.list', 'deviceId': 'android-device-001'},
      key,
      requestId: vector['requestId'] as String,
      timestamp: vector['timestamp'] as int,
      direction: 'request',
      salt: List<int>.generate(16, (index) => index),
      nonce: List<int>.generate(12, (index) => index + 16),
    );
    expect(envelope, vector);
  });
}
