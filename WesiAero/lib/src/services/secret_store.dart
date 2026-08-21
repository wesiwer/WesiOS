import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/gateway_models.dart';

class GatewaySecretStore {
  GatewaySecretStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _profileKey = 'active_gateway_profile';
  static const String _profileNameKey = 'active_gateway_profile_name';
  static const String _profileProtocolKey = 'active_gateway_profile_protocol';

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
}
