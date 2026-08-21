import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/admin_models.dart';

abstract interface class AdminApi {
  bool get isDemo;

  Future<AdminSnapshot> fetchSnapshot();

  Future<void> upsertServer(Map<String, dynamic> value, {String? id});

  Future<void> deleteServer(String id);

  Future<void> upsertPlan(Map<String, dynamic> value, {String? id});

  Future<String> generateLicense({
    required String? planId,
    required String ipMode,
    required int deviceLimit,
    required int durationDays,
    required String note,
  });

  Future<String> revealLicenseKey(String id);

  Future<void> revokeLicense(String id);

  Future<void> confirmMockPayment(String id);

  Future<void> reconcilePayment(String id);

  Future<void> updatePaymentSetting({
    required String provider,
    required bool enabled,
    required bool testMode,
    required String label,
  });

  Future<Map<String, dynamic>> paymentSecretStatus();

  void close();
}

class RemoteAdminApi implements AdminApi {
  RemoteAdminApi(this.baseUri, this.adminToken) {
    final secure = baseUri.scheme == 'https';
    final local = const {'localhost', '127.0.0.1', '::1'}.contains(baseUri.host);
    if (!secure && !local) {
      throw ArgumentError('Адрес Admin API должен использовать HTTPS.');
    }
    if (adminToken.length < 32) {
      throw ArgumentError('Admin token должен содержать минимум 32 символа.');
    }
    _client.connectionTimeout = const Duration(seconds: 12);
  }

  final Uri baseUri;
  final String adminToken;
  final HttpClient _client = HttpClient();

  @override
  bool get isDemo => false;

  @override
  Future<AdminSnapshot> fetchSnapshot() async =>
      AdminSnapshot.fromJson(await _request('GET', '/v1/admin/snapshot'));

  @override
  Future<void> upsertServer(Map<String, dynamic> value, {String? id}) async {
    await _request(
      id == null ? 'POST' : 'PUT',
      id == null ? '/v1/admin/servers' : '/v1/admin/servers/$id',
      body: value,
    );
  }

  @override
  Future<void> deleteServer(String id) =>
      _request('DELETE', '/v1/admin/servers/$id');

  @override
  Future<void> upsertPlan(Map<String, dynamic> value, {String? id}) async {
    await _request(
      id == null ? 'POST' : 'PUT',
      id == null ? '/v1/admin/plans' : '/v1/admin/plans/$id',
      body: value,
    );
  }

  @override
  Future<String> generateLicense({
    required String? planId,
    required String ipMode,
    required int deviceLimit,
    required int durationDays,
    required String note,
  }) async {
    final json = await _request('POST', '/v1/admin/licenses', body: {
      'planId': planId,
      'ipMode': ipMode,
      'deviceLimit': deviceLimit,
      'durationDays': durationDays,
      'note': note,
    });
    return json['key'] as String;
  }

  @override
  Future<String> revealLicenseKey(String id) async =>
      (await _request('GET', '/v1/admin/licenses/$id/key'))['key'] as String;

  @override
  Future<void> revokeLicense(String id) async {
    await _request('POST', '/v1/admin/licenses/$id/revoke');
  }

  @override
  Future<void> confirmMockPayment(String id) async {
    await _request('POST', '/v1/admin/payments/$id/confirm-mock');
  }

  @override
  Future<void> reconcilePayment(String id) async {
    await _request('POST', '/v1/admin/payments/$id/reconcile');
  }

  @override
  Future<void> updatePaymentSetting({
    required String provider,
    required bool enabled,
    required bool testMode,
    required String label,
  }) async {
    await _request('PUT', '/v1/admin/payment-settings/$provider', body: {
      'enabled': enabled,
      'testMode': testMode,
      'publicConfig': {'label': label},
    });
  }

  @override
  Future<Map<String, dynamic>> paymentSecretStatus() =>
      _request('GET', '/v1/admin/payment-secret-status');

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final request = await _client.openUrl(method, baseUri.resolve(path));
    request.headers.set('x-admin-token', adminToken);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 18));
    final text = await utf8.decoder.bind(response).join();
    Map<String, dynamic> json = const {};
    if (text.isNotEmpty) {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) json = decoded;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = json['error'] as Map<String, dynamic>? ?? const {};
      throw AdminApiException(
        error['code'] as String? ?? 'HTTP_${response.statusCode}',
        error['message'] as String? ?? 'Сервер отклонил запрос.',
      );
    }
    return json;
  }

  @override
  void close() => _client.close(force: true);
}

class DemoAdminApi implements AdminApi {
  int _revision = 7;
  final List<Map<String, dynamic>> _servers = [
    {
      'id': 'wesi-relay-demo',
      'displayName': 'Wesi Relay',
      'city': 'Wesi Relay',
      'country': 'Foreign VPS',
      'countryCode': '',
      'endpoint': 'wesi-ai-178-236-247-194.nip.io:8443',
      'protocols': ['vless-reality', 'amneziawg'],
      'load': 0.24,
      'online': true,
      'recommended': true,
      'capacity': 500,
      'tags': ['relay', 'candidate'],
      'notes': 'Demo-конфигурация без production tunnel.',
      'transportConfig': {'realityPort': 8443, 'amneziaWgPort': 51820},
    },
    {
      'id': 'nl-ams-01',
      'displayName': 'Amsterdam One',
      'city': 'Amsterdam',
      'country': 'Netherlands',
      'countryCode': 'NL',
      'endpoint': 'ams-01.example.net:443',
      'protocols': ['vless-reality', 'amneziawg'],
      'load': 0.41,
      'online': true,
      'recommended': false,
      'capacity': 1000,
      'tags': ['eu'],
      'notes': '',
      'transportConfig': {},
    },
  ];
  final List<Map<String, dynamic>> _plans = [_demoPlan];
  final List<Map<String, dynamic>> _licenses = [];
  final Map<String, String> _keys = {};
  final List<Map<String, dynamic>> _payments = [
    {
      'id': '0f44bd4d-f719-4dfd-8053-07f08c521001',
      'provider': 'mock',
      'status': 'pending',
      'amountMinor': 34900,
      'currency': 'RUB',
      'planId': 'aero-flex',
      'ipMode': 'shared',
      'deviceLimit': 1,
      'durationDays': 30,
      'createdAt': DateTime.now().subtract(const Duration(minutes: 8)).toIso8601String(),
    },
  ];
  final List<Map<String, dynamic>> _settings = [
    {
      'provider': 'mock',
      'enabled': true,
      'testMode': true,
      'publicConfig': {'label': 'Тестовая оплата'},
    },
    {
      'provider': 'yookassa',
      'enabled': false,
      'testMode': true,
      'publicConfig': {'label': 'СБП'},
    },
    {
      'provider': 'crypto_pay',
      'enabled': false,
      'testMode': true,
      'publicConfig': {'label': 'Криптовалюта'},
    },
  ];

  @override
  bool get isDemo => true;

  @override
  Future<AdminSnapshot> fetchSnapshot() async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    return AdminSnapshot.fromJson(_snapshotJson());
  }

  @override
  Future<void> upsertServer(Map<String, dynamic> value, {String? id}) async {
    final target = id ?? value['id'] as String;
    _servers.removeWhere((item) => item['id'] == target);
    _servers.add({...value, 'id': target});
    _revision++;
  }

  @override
  Future<void> deleteServer(String id) async {
    _servers.removeWhere((item) => item['id'] == id);
    _revision++;
  }

  @override
  Future<void> upsertPlan(Map<String, dynamic> value, {String? id}) async {
    final target = id ?? value['id'] as String;
    _plans.removeWhere((item) => item['id'] == target);
    _plans.add({...value, 'id': target});
    _revision++;
  }

  @override
  Future<String> generateLicense({
    required String? planId,
    required String ipMode,
    required int deviceLimit,
    required int durationDays,
    required String note,
  }) async {
    final id = _uuid();
    final compact = id.replaceAll('-', '');
    final key = 'WA1-$compact-${_randomToken(24)}';
    final now = DateTime.now();
    _keys[id] = key;
    _licenses.insert(0, {
      'id': id,
      'maskedKey': 'WA1-${compact.substring(0, 8)}-••••••••',
      'planId': planId,
      'source': 'admin',
      'ipMode': ipMode,
      'deviceLimit': deviceLimit,
      'deviceCount': 0,
      'durationDays': durationDays,
      'status': 'active',
      'issuedAt': now.toIso8601String(),
      'expiresAt': now.add(Duration(days: durationDays)).toIso8601String(),
      'paymentId': null,
      'note': note,
    });
    return key;
  }

  @override
  Future<String> revealLicenseKey(String id) async {
    final key = _keys[id];
    if (key == null) throw const AdminApiException('LICENSE_NOT_FOUND', 'Ключ не найден.');
    return key;
  }

  @override
  Future<void> revokeLicense(String id) async {
    final index = _licenses.indexWhere((item) => item['id'] == id);
    if (index >= 0) _licenses[index] = {..._licenses[index], 'status': 'revoked'};
  }

  @override
  Future<void> confirmMockPayment(String id) async {
    final index = _payments.indexWhere((item) => item['id'] == id);
    if (index >= 0) _payments[index] = {..._payments[index], 'status': 'paid'};
  }

  @override
  Future<void> reconcilePayment(String id) async {}

  @override
  Future<void> updatePaymentSetting({
    required String provider,
    required bool enabled,
    required bool testMode,
    required String label,
  }) async {
    final index = _settings.indexWhere((item) => item['provider'] == provider);
    final value = {
      'provider': provider,
      'enabled': enabled,
      'testMode': testMode,
      'publicConfig': {'label': label},
    };
    if (index >= 0) {
      _settings[index] = value;
    } else {
      _settings.add(value);
    }
    _revision++;
  }

  @override
  Future<Map<String, dynamic>> paymentSecretStatus() async => const {
        'yookassa': false,
        'cryptoPay': false,
        'mockAllowed': true,
      };

  Map<String, dynamic> _snapshotJson() {
    final active = _licenses.where((item) =>
        item['status'] == 'active' &&
        DateTime.parse(item['expiresAt'] as String).isAfter(DateTime.now())).length;
    final paid = _payments.where((item) => item['status'] == 'paid').toList();
    return {
      'revision': _revision,
      'generatedAt': DateTime.now().toIso8601String(),
      'counts': {
        'servers': _servers.length,
        'serversOnline': _servers.where((item) => item['online'] == true).length,
        'licenses': _licenses.length,
        'licensesActive': active,
        'devices': _licenses.fold<int>(
          0,
          (sum, item) => sum + (item['deviceCount'] as int? ?? 0),
        ),
        'payments': _payments.length,
        'paymentsPaid': paid.length,
        'revenueMinor': paid.fold<int>(
          0,
          (sum, item) => sum + (item['amountMinor'] as int),
        ),
      },
      'servers': _servers,
      'plans': _plans,
      'licenses': _licenses,
      'payments': _payments,
      'paymentSettings': _settings,
    };
  }

  @override
  void close() {}
}

class AdminApiException implements Exception {
  const AdminApiException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

String _uuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String _randomToken(int bytes) {
  final random = Random.secure();
  return base64Url
      .encode(List<int>.generate(bytes, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}

const Map<String, dynamic> _demoPlan = {
  'id': 'aero-flex',
  'name': 'Aero Flex',
  'description': 'Гибкий доступ Wesi Aero',
  'currency': 'RUB',
  'enabled': true,
  'sortOrder': 10,
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
};
