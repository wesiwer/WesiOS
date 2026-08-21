import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AdminSecretStore {
  AdminSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _urlKey = 'wesi_aero_admin_url';
  static const _tokenKey = 'wesi_aero_admin_token';

  Future<(String?, String?)> readConnection() async => (
        await _storage.read(key: _urlKey),
        await _storage.read(key: _tokenKey),
      );

  Future<void> saveConnection(String url, String token) async {
    await Future.wait([
      _storage.write(key: _urlKey, value: url),
      _storage.write(key: _tokenKey, value: token),
    ]);
  }

  Future<void> clearConnection() async {
    await Future.wait([
      _storage.delete(key: _urlKey),
      _storage.delete(key: _tokenKey),
    ]);
  }
}
