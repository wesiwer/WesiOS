import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../models/commerce_models.dart';

abstract interface class AeroCommerceService {
  bool get isDemo;

  Future<AeroCatalog> fetchCatalog();

  Future<AeroQuote> quote({
    required String planId,
    required AeroIpMode ipMode,
    required int deviceLimit,
    required int durationDays,
  });

  Future<CheckoutOrder> createOrder({
    required String planId,
    required AeroIpMode ipMode,
    required int deviceLimit,
    required int durationDays,
    required AeroPaymentProvider provider,
  });

  Future<CheckoutOrder> refreshOrder(CheckoutOrder order);

  Future<AeroLicense> redeemKey({
    required String key,
    required String deviceId,
    required String deviceName,
    required String platform,
  });

  Future<Map<String, dynamic>> secureCall({
    required String key,
    required Map<String, dynamic> payload,
  });

  void close();
}

AeroCommerceService createAeroCommerceService() {
  const baseUrl = String.fromEnvironment('WESI_AERO_CONTROL_URL');
  if (baseUrl.trim().isEmpty) return DemoAeroCommerceService();
  return RemoteAeroCommerceService(Uri.parse(baseUrl));
}

class RemoteAeroCommerceService implements AeroCommerceService {
  RemoteAeroCommerceService(this.baseUri) {
    final secure = baseUri.scheme == 'https';
    final local = const {'localhost', '127.0.0.1', '::1'}.contains(baseUri.host);
    if (!secure && !local) {
      throw ArgumentError('WESI_AERO_CONTROL_URL must use HTTPS outside localhost.');
    }
    _client.connectionTimeout = const Duration(seconds: 12);
  }

  final Uri baseUri;
  final HttpClient _client = HttpClient();
  final AeroSecureEnvelopeCodec _secureCodec = AeroSecureEnvelopeCodec();

  @override
  bool get isDemo => false;

  @override
  Future<AeroCatalog> fetchCatalog() async {
    final json = await _request('GET', '/v1/catalog');
    return AeroCatalog.fromJson(json);
  }

  @override
  Future<AeroQuote> quote({
    required String planId,
    required AeroIpMode ipMode,
    required int deviceLimit,
    required int durationDays,
  }) async {
    final json = await _request('POST', '/v1/quotes', body: {
      'planId': planId,
      'ipMode': ipMode.wireName,
      'deviceLimit': deviceLimit,
      'durationDays': durationDays,
    });
    return AeroQuote.fromJson(json['quote'] as Map<String, dynamic>);
  }

  @override
  Future<CheckoutOrder> createOrder({
    required String planId,
    required AeroIpMode ipMode,
    required int deviceLimit,
    required int durationDays,
    required AeroPaymentProvider provider,
  }) async {
    final json = await _request(
      'POST',
      '/v1/orders',
      headers: {'idempotency-key': _uuid()},
      body: {
        'provider': provider.wireName,
        'planId': planId,
        'ipMode': ipMode.wireName,
        'deviceLimit': deviceLimit,
        'durationDays': durationDays,
      },
    );
    final claimToken = json['claimToken'] as String?;
    if (claimToken == null || claimToken.isEmpty) {
      throw const AeroApiException('INVALID_ORDER', 'Сервер не вернул секрет заказа.');
    }
    return CheckoutOrder.fromJson(json, claimToken: claimToken);
  }

  @override
  Future<CheckoutOrder> refreshOrder(CheckoutOrder order) async {
    final json = await _request(
      'GET',
      '/v1/orders/${order.id}',
      headers: {'x-order-claim': order.claimToken},
    );
    return CheckoutOrder.fromJson(json, claimToken: order.claimToken);
  }

  @override
  Future<AeroLicense> redeemKey({
    required String key,
    required String deviceId,
    required String deviceName,
    required String platform,
  }) async {
    final json = await _request('POST', '/v1/licenses/redeem', body: {
      'key': key.trim(),
      'deviceId': deviceId,
      'deviceName': deviceName,
      'platform': platform,
    });
    return AeroLicense.fromJson(json['license'] as Map<String, dynamic>);
  }

  @override
  Future<Map<String, dynamic>> secureCall({
    required String key,
    required Map<String, dynamic> payload,
  }) async {
    final requestId = _uuid();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final envelope = await _secureCodec.encrypt(
      payload,
      key,
      requestId: requestId,
      timestamp: timestamp,
      direction: 'request',
    );
    final response = await _request(
      'POST',
      '/v1/secure',
      headers: {'authorization': 'Bearer $key'},
      body: envelope,
    );
    final clear = await _secureCodec.decrypt(response, key, direction: 'response');
    if (clear['ok'] != true) {
      final error = clear['error'] as Map<String, dynamic>? ?? const {};
      throw AeroApiException(
        error['code'] as String? ?? 'SECURE_CALL_FAILED',
        error['message'] as String? ?? 'Защищённый запрос отклонён.',
      );
    }
    return clear['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String> headers = const {},
    Map<String, dynamic>? body,
  }) async {
    final uri = baseUri.resolve(path);
    final request = await _client.openUrl(method, uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 18));
    final text = await utf8.decoder.bind(response).join();
    Map<String, dynamic> json = const {};
    if (text.isNotEmpty) {
      final value = jsonDecode(text);
      if (value is Map<String, dynamic>) json = value;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = json['error'] as Map<String, dynamic>? ?? const {};
      throw AeroApiException(
        error['code'] as String? ?? 'HTTP_${response.statusCode}',
        error['message'] as String? ?? 'Сервер отклонил запрос.',
      );
    }
    return json;
  }

  @override
  void close() => _client.close(force: true);
}

class DemoAeroCommerceService implements AeroCommerceService {
  final Map<String, _DemoOrder> _orders = {};
  final Map<String, AeroLicense> _licenses = {};
  final Map<String, Set<String>> _devices = {};

  @override
  bool get isDemo => true;

  late final AeroCatalog _catalog = AeroCatalog.fromJson(_demoCatalog, demo: true);

  @override
  Future<AeroCatalog> fetchCatalog() async {
    await Future<void>.delayed(const Duration(milliseconds: 260));
    return _catalog;
  }

  @override
  Future<AeroQuote> quote({
    required String planId,
    required AeroIpMode ipMode,
    required int deviceLimit,
    required int durationDays,
  }) async {
    final plan = _catalog.plans.firstWhere((item) => item.id == planId);
    final amount = plan.amountFor(ipMode, deviceLimit, durationDays);
    return AeroQuote(
      amountMinor: amount,
      currency: plan.currency,
      displayAmount: '${(amount / 100).toStringAsFixed(0)} ₽',
    );
  }

  @override
  Future<CheckoutOrder> createOrder({
    required String planId,
    required AeroIpMode ipMode,
    required int deviceLimit,
    required int durationDays,
    required AeroPaymentProvider provider,
  }) async {
    final price = await quote(
      planId: planId,
      ipMode: ipMode,
      deviceLimit: deviceLimit,
      durationDays: durationDays,
    );
    final id = _uuid();
    final claim = base64Url.encode(_randomBytes(32)).replaceAll('=', '');
    final compact = _randomBytes(16)
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    final key = 'WA1-$compact-${base64Url.encode(_randomBytes(24)).replaceAll('=', '')}';
    final license = AeroLicense(
      id: _uuid(),
      planId: planId,
      ipMode: ipMode,
      deviceLimit: deviceLimit,
      deviceCount: 0,
      durationDays: durationDays,
      status: 'active',
      expiresAt: DateTime.now().add(Duration(days: durationDays)),
      maskedKey: 'WA1-${compact.substring(0, 8)}-••••••••',
    );
    _licenses[key] = license;
    _orders[id] = _DemoOrder(
      createdAt: DateTime.now(),
      key: key,
      license: license,
    );
    return CheckoutOrder(
      id: id,
      provider: provider,
      status: 'pending',
      amountMinor: price.amountMinor,
      currency: price.currency,
      claimToken: claim,
    );
  }

  @override
  Future<CheckoutOrder> refreshOrder(CheckoutOrder order) async {
    final record = _orders[order.id];
    if (record == null) {
      throw const AeroApiException('PAYMENT_NOT_FOUND', 'Заказ не найден.');
    }
    if (DateTime.now().difference(record.createdAt).inMilliseconds < 900) {
      return order;
    }
    return CheckoutOrder(
      id: order.id,
      provider: order.provider,
      status: 'paid',
      amountMinor: order.amountMinor,
      currency: order.currency,
      claimToken: order.claimToken,
      key: record.key,
      license: record.license,
    );
  }

  @override
  Future<AeroLicense> redeemKey({
    required String key,
    required String deviceId,
    required String deviceName,
    required String platform,
  }) async {
    final license = _licenses[key.trim()];
    if (license == null) {
      throw const AeroApiException('INVALID_LICENSE_KEY', 'Ключ не найден.');
    }
    if (!license.isActive) {
      throw const AeroApiException('LICENSE_EXPIRED', 'Срок действия ключа истёк.');
    }
    final devices = _devices.putIfAbsent(key.trim(), () => <String>{});
    if (!devices.contains(deviceId) && devices.length >= license.deviceLimit) {
      throw const AeroApiException(
        'DEVICE_LIMIT_EXCEEDED',
        'Превышено максимальное количество устройств.',
      );
    }
    devices.add(deviceId);
    return AeroLicense(
      id: license.id,
      planId: license.planId,
      ipMode: license.ipMode,
      deviceLimit: license.deviceLimit,
      deviceCount: devices.length,
      durationDays: license.durationDays,
      status: license.status,
      expiresAt: license.expiresAt,
      maskedKey: license.maskedKey,
    );
  }

  @override
  Future<Map<String, dynamic>> secureCall({
    required String key,
    required Map<String, dynamic> payload,
  }) async {
    if (!_licenses.containsKey(key)) {
      throw const AeroApiException('INVALID_LICENSE_KEY', 'Ключ не найден.');
    }
    return {'accepted': true, 'action': payload['action']};
  }

  @override
  void close() {}
}

class AeroSecureEnvelopeCodec {
  AeroSecureEnvelopeCodec()
      : _cipher = AesGcm.with256bits(),
        _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  final AesGcm _cipher;
  final Hkdf _hkdf;

  Future<Map<String, dynamic>> encrypt(
    Map<String, dynamic> payload,
    String key, {
    required String requestId,
    required int timestamp,
    required String direction,
    List<int>? salt,
    List<int>? nonce,
  }) async {
    final actualSalt = salt ?? _randomBytes(16);
    final actualNonce = nonce ?? _randomBytes(12);
    final derived = await _hkdf.deriveKey(
      secretKey: SecretKey(utf8.encode(key)),
      nonce: actualSalt,
      info: utf8.encode('wesi-aero-control-v1'),
    );
    final aad = utf8.encode('1|$requestId|$timestamp|$direction');
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: derived,
      nonce: actualNonce,
      aad: aad,
    );
    return {
      'v': 1,
      'requestId': requestId,
      'timestamp': timestamp,
      'salt': base64Url.encode(actualSalt).replaceAll('=', ''),
      'nonce': base64Url.encode(actualNonce).replaceAll('=', ''),
      'ciphertext': base64Url.encode(box.cipherText).replaceAll('=', ''),
      'tag': base64Url.encode(box.mac.bytes).replaceAll('=', ''),
    };
  }

  Future<Map<String, dynamic>> decrypt(
    Map<String, dynamic> envelope,
    String key, {
    required String direction,
  }) async {
    final requestId = envelope['requestId'] as String;
    final timestamp = (envelope['timestamp'] as num).toInt();
    final salt = _decodeBase64Url(envelope['salt'] as String);
    final nonce = _decodeBase64Url(envelope['nonce'] as String);
    final derived = await _hkdf.deriveKey(
      secretKey: SecretKey(utf8.encode(key)),
      nonce: salt,
      info: utf8.encode('wesi-aero-control-v1'),
    );
    final clear = await _cipher.decrypt(
      SecretBox(
        _decodeBase64Url(envelope['ciphertext'] as String),
        nonce: nonce,
        mac: Mac(_decodeBase64Url(envelope['tag'] as String)),
      ),
      secretKey: derived,
      aad: utf8.encode('1|$requestId|$timestamp|$direction'),
    );
    return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
  }
}

class AeroApiException implements Exception {
  const AeroApiException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class _DemoOrder {
  const _DemoOrder({
    required this.createdAt,
    required this.key,
    required this.license,
  });

  final DateTime createdAt;
  final String key;
  final AeroLicense license;
}

List<int> _randomBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}

String _uuid() {
  final bytes = _randomBytes(16);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

List<int> _decodeBase64Url(String value) {
  final normalized = value.padRight(value.length + (4 - value.length % 4) % 4, '=');
  return base64Url.decode(normalized);
}

const Map<String, dynamic> _demoCatalog = {
  'revision': 1,
  'plans': [
    {
      'id': 'aero-flex',
      'name': 'Aero Flex',
      'description': 'Выберите IP, срок и число устройств.',
      'currency': 'RUB',
      'enabled': true,
      'pricing': {
        'shared': {
          '7': {'base': 14900, 'extraDevice': 5900},
          '30': {'base': 34900, 'extraDevice': 12900},
          '90': {'base': 79900, 'extraDevice': 29900},
          '180': {'base': 139000, 'extraDevice': 49900},
          '365': {'base': 239000, 'extraDevice': 89900},
        },
        'dedicated': {
          '7': {'base': 34900, 'extraDevice': 7900},
          '30': {'base': 79900, 'extraDevice': 17900},
          '90': {'base': 199000, 'extraDevice': 44900},
          '180': {'base': 349000, 'extraDevice': 79900},
          '365': {'base': 599000, 'extraDevice': 139000},
        },
      },
    },
  ],
  'servers': [
    {
      'id': 'wesi-relay-demo',
      'displayName': 'Wesi Relay',
      'city': 'Wesi Relay',
      'country': 'Demo target',
      'countryCode': '',
      'endpoint': 'wesi-ai-178-236-247-194.nip.io:8443',
      'protocols': ['vless-reality', 'amneziawg'],
      'load': 0.24,
      'online': true,
      'recommended': true,
    },
    {
      'id': 'nl-ams-01',
      'displayName': 'Amsterdam',
      'city': 'Amsterdam',
      'country': 'Netherlands',
      'countryCode': 'NL',
      'endpoint': 'ams-01.example.net:443',
      'protocols': ['vless-reality', 'amneziawg'],
      'load': 0.47,
      'online': true,
      'recommended': false,
    },
  ],
  'paymentMethods': [
    {'provider': 'yookassa', 'label': 'СБП · тест', 'testMode': true},
    {'provider': 'crypto_pay', 'label': 'Криптовалюта · тест', 'testMode': true},
  ],
};
