import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FirebaseConfigService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const String _configuredKey = 'firebase_configured';

  Future<bool> isConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_configuredKey) ?? false;
  }

  Future<Map<String, String?>> getConfig() async {
    return {
      'apiKey': await _storage.read(key: 'firebase_apiKey'),
      'appId': await _storage.read(key: 'firebase_appId'),
      'messagingSenderId': await _storage.read(key: 'firebase_messagingSenderId'),
      'projectId': await _storage.read(key: 'firebase_projectId'),
      'authDomain': await _storage.read(key: 'firebase_authDomain'),
      'storageBucket': await _storage.read(key: 'firebase_storageBucket'),
      'measurementId': await _storage.read(key: 'firebase_measurementId'),
    };
  }

  Future<void> saveConfig({
    required String apiKey,
    required String appId,
    required String messagingSenderId,
    required String projectId,
    String? authDomain,
    String? storageBucket,
    String? measurementId,
  }) async {
    await _storage.write(key: 'firebase_apiKey', value: apiKey);
    await _storage.write(key: 'firebase_appId', value: appId);
    await _storage.write(key: 'firebase_messagingSenderId', value: messagingSenderId);
    await _storage.write(key: 'firebase_projectId', value: projectId);
    if (authDomain != null) await _storage.write(key: 'firebase_authDomain', value: authDomain);
    if (storageBucket != null) await _storage.write(key: 'firebase_storageBucket', value: storageBucket);
    if (measurementId != null) await _storage.write(key: 'firebase_measurementId', value: measurementId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_configuredKey, true);
  }

  Future<void> clearConfig() async {
    await _storage.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_configuredKey, false);
  }
}
