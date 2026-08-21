import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/commerce_models.dart';
import '../models/gateway_models.dart';

class GatewaySecretStore {
  GatewaySecretStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _profileKey = 'active_gateway_profile';
  static const String _profileNameKey = 'active_gateway_profile_name';
  static const String _profileProtocolKey = 'active_gateway_profile_protocol';
  static const String _licenseKey = 'wesi_aero_license_key';
  static const String _deviceIdKey = 'wesi_aero_device_id';
  static const String _pendingOrderKey = 'wesi_aero_pending_order';

  Future<void> saveProfile(ImportedGatewayConfig config) async {
    await _storage.write(key: _profileKey, value: config.rawValue);
    await _storage.write(key: _profileNameKey, value: config.displayName);
    await _storage.write(
      key: _profileProtocolKey,
      value: config.protocol.wireName,
    );
  }

  Future<ImportedGatewayConfig?> readProfile() async {
    final values = await Future.wait([
      _storage.read(key: _profileKey),
      _storage.read(key: _profileNameKey),
      _storage.read(key: _profileProtocolKey),
    ]);
    final rawValue = values[0];
    if (rawValue == null || rawValue.trim().isEmpty) return null;

    final protocolName = values[2];
    final protocol = GatewayProtocol.values.firstWhere(
      (item) => item.wireName == protocolName,
      orElse: () => GatewayProtocol.automatic,
    );
    if (protocol == GatewayProtocol.automatic) {
      await clearProfile();
      return null;
    }

    final storedName = values[1]?.trim();
    return ImportedGatewayConfig(
      protocol: protocol,
      displayName: storedName?.isNotEmpty == true
          ? storedName!
          : 'Wesi Aero VPN',
      rawValue: rawValue,
    );
  }

  Future<void> clearProfile() async {
    await Future.wait([
      _storage.delete(key: _profileKey),
      _storage.delete(key: _profileNameKey),
      _storage.delete(key: _profileProtocolKey),
    ]);
  }

  Future<String?> readLicenseKey() async {
    // A Live prototype APK is built against one exact server-backed key. It
    // must win over Secure Storage so an older installed build cannot leave a
    // stale key behind and poison the next update. Normal production builds
    // do not define this value and therefore continue to use Secure Storage.
    const prototypeLicense = String.fromEnvironment(
      'WESI_AERO_PROTOTYPE_LICENSE',
    );
    final embedded = prototypeLicense.trim();
    if (embedded.isNotEmpty) return embedded;

    final stored = (await _storage.read(key: _licenseKey))?.trim();
    return stored == null || stored.isEmpty ? null : stored;
  }

  Future<void> saveLicenseKey(String value) =>
      _storage.write(key: _licenseKey, value: value.trim());

  Future<void> clearLicenseKey() => _storage.delete(key: _licenseKey);

  Future<void> savePendingOrder(CheckoutOrder order) async {
    await _storage.write(
      key: _pendingOrderKey,
      value: jsonEncode({
        'id': order.id,
        'provider': order.provider.wireName,
        'status': order.status,
        'amountMinor': order.amountMinor,
        'currency': order.currency,
        'claimToken': order.claimToken,
        'checkoutUrl': order.checkoutUrl,
      }),
    );
  }

  Future<CheckoutOrder?> readPendingOrder() async {
    final raw = await _storage.read(key: _pendingOrderKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return CheckoutOrder(
        id: json['id'] as String,
        provider: AeroPaymentProvider.fromWire(json['provider'] as String),
        status: json['status'] as String,
        amountMinor: (json['amountMinor'] as num).toInt(),
        currency: json['currency'] as String,
        claimToken: json['claimToken'] as String,
        checkoutUrl: json['checkoutUrl'] as String?,
      );
    } catch (_) {
      await clearPendingOrder();
      return null;
    }
  }

  Future<void> clearPendingOrder() => _storage.delete(key: _pendingOrderKey);

  Future<String> getOrCreateDeviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.length >= 8) return existing;
    final random = Random.secure();
    final value = 'device-${base64Url.encode(
      List<int>.generate(18, (_) => random.nextInt(256)),
    ).replaceAll('=', '')}';
    await _storage.write(key: _deviceIdKey, value: value);
    return value;
  }
}
