import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesi_aero/src/models/gateway_models.dart';

void main() {
  group('GatewayConfigParser', () {
    test('accepts VLESS REALITY URI', () {
      final config = GatewayConfigParser.parse(
        'vless://123e4567-e89b-42d3-a456-426614174000@example.com:443'
        '?security=reality&encryption=none&pbk=server-public-key&sni=example.com'
        '#Frankfurt',
      );
      expect(config.protocol, GatewayProtocol.vlessReality);
      expect(config.displayName, 'Frankfurt');
    });

    test('rejects VLESS without REALITY', () {
      expect(
        () => GatewayConfigParser.parse(
          'vless://123e4567-e89b-42d3-a456-426614174000@example.com:443'
          '?security=tls',
        ),
        throwsFormatException,
      );
    });

    test('accepts standard VMess base64 JSON URI', () {
      final payload = base64.encode(
        utf8.encode(
          jsonEncode({
            'v': '2',
            'ps': 'Wesi Aero VMess',
            'add': 'wesi.example',
            'port': '8444',
            'id': '123e4567-e89b-42d3-a456-426614174000',
            'aid': '0',
            'scy': 'auto',
            'net': 'tcp',
            'tls': '',
          }),
        ),
      );
      final config = GatewayConfigParser.parse('vmess://$payload');
      expect(config.protocol, GatewayProtocol.vmessXray);
      expect(config.displayName, 'Wesi Aero VMess');
    });

    test('rejects malformed VMess URI', () {
      expect(
        () => GatewayConfigParser.parse('vmess://not-base64'),
        throwsFormatException,
      );
    });

    test('accepts AmneziaWG style INI', () {
      final config = GatewayConfigParser.parse('''
[Interface]
PrivateKey = private-key-placeholder
Address = 10.8.0.2/32

[Peer]
PublicKey = public-key-placeholder
Endpoint = gateway.example:51820
AllowedIPs = 0.0.0.0/0, ::/0
''');
      expect(config.protocol, GatewayProtocol.amneziaWg);
    });

    test('rejects empty input', () {
      expect(() => GatewayConfigParser.parse('  '), throwsFormatException);
    });
  });
}
