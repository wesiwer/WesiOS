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
      expect(config.protocol.supportsEngine(TunnelEngine.singBox), isTrue);
      expect(config.protocol.supportsEngine(TunnelEngine.xray), isTrue);
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
      expect(config.protocol, GatewayProtocol.vmess);
      expect(config.displayName, 'Wesi Aero VMess');
    });

    test('rejects malformed VMess URI', () {
      expect(
        () => GatewayConfigParser.parse('vmess://not-base64'),
        throwsFormatException,
      );
    });

    test('accepts Trojan URI', () {
      final config = GatewayConfigParser.parse(
        'trojan://secret@example.com:443?sni=example.com#Trojan',
      );
      expect(config.protocol, GatewayProtocol.trojan);
    });

    test('accepts Hysteria2 URI', () {
      final config = GatewayConfigParser.parse(
        'hysteria2://secret@example.com:8445?sni=example.com#HY2',
      );
      expect(config.protocol, GatewayProtocol.hysteria2);
      expect(config.protocol.supportsEngine(TunnelEngine.singBox), isTrue);
      expect(config.protocol.supportsEngine(TunnelEngine.xray), isFalse);
    });

    test('accepts TUIC URI', () {
      final config = GatewayConfigParser.parse(
        'tuic://123e4567-e89b-42d3-a456-426614174000:secret@example.com:8446#TUIC',
      );
      expect(config.protocol, GatewayProtocol.tuic);
    });

    test('distinguishes standard WireGuard from AmneziaWG', () {
      final wireGuard = GatewayConfigParser.parse('''
[Interface]
PrivateKey = private-key-placeholder
Address = 10.8.0.2/32

[Peer]
PublicKey = public-key-placeholder
Endpoint = gateway.example:51820
AllowedIPs = 0.0.0.0/0
''');
      expect(wireGuard.protocol, GatewayProtocol.wireGuard);

      final amnezia = GatewayConfigParser.parse('''
[Interface]
PrivateKey = private-key-placeholder
Address = 10.9.0.2/32
Jc = 4
Jmin = 40
Jmax = 70
S1 = 0
S2 = 0
H1 = 123456
H2 = 234567
H3 = 345678
H4 = 456789

[Peer]
PublicKey = public-key-placeholder
Endpoint = gateway.example:51821
AllowedIPs = 0.0.0.0/0
''');
      expect(amnezia.protocol, GatewayProtocol.amneziaWg);
    });

    test('declares eight real user protocols', () {
      final userProtocols = GatewayProtocol.values
          .where((value) => value != GatewayProtocol.automatic)
          .toList();
      expect(userProtocols, hasLength(8));
    });

    test('rejects empty input', () {
      expect(() => GatewayConfigParser.parse('  '), throwsFormatException);
    });
  });
}
