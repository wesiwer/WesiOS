import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  Future<void> saveProfile(ImportedGatewayConfig config) async {
    await _storage.write(key: _profileKey, value: config.rawValue);
    await _storage.write(key: _profileNameKey, value: config.displayName);
    await _storage.write(
      key: _profileProtocolKey,
      value: config.protocol.wireName,
    );
  }

  Future<void> clearProfile() async {
    await Future.wait([
      _storage.delete(key: _profileKey),
      _storage.delete(key: _profileNameKey),
      _storage.delete(key: _profileProtocolKey),
    ]);
  }

  Future<String?> readLicenseKey() => _storage.read(key: _licenseKey);

  Future<void> saveLicenseKey(String value) =>
      _storage.write(key: _licenseKey, value: value.trim());

  Future<void> clearLicenseKey() => _storage.delete(key: _licenseKey);

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
