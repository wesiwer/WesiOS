import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Firebase-параметры поставляются вместе с официальной сборкой WesiOS.
/// Пользователь не должен искать их в Firebase Console и не может оказаться
/// на экране «проект не настроен» только потому, что это новая установка.
class FirebaseConfigService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const String _configuredKey = 'firebase_configured';

  // Те же значения, что у android/app/google-services.json. API key Firebase
  // является идентификатором проекта, а не секретом; права определяют auth и
  // server-side rules. Overrides оставлены только для совместимости со
  // старыми установками, но defaults всегда готовы из коробки.
  static const String _defaultApiKey =
      'AIzaSyAlBRd6z6V0t16wgcOd68o2CXA0n8jtE_k';
  static const String _defaultAppId =
      '1:885912986842:android:6215dc1216db43ce8d31e3';
  static const String _defaultSenderId = '885912986842';
  static const String _defaultProjectId = 'wesios-d7b07';
  static const String _defaultAuthDomain = 'wesios-d7b07.firebaseapp.com';
  static const String _defaultStorageBucket =
      'wesios-d7b07.firebasestorage.app';

  /// У официальной сборки конфигурация всегда есть.
  Future<bool> isConfigured() async => true;

  Future<Map<String, String?>> getConfig() async {
    return {
      'apiKey': await _storage.read(key: 'firebase_apiKey') ?? _defaultApiKey,
      'appId': await _storage.read(key: 'firebase_appId') ?? _defaultAppId,
      'messagingSenderId':
          await _storage.read(key: 'firebase_messagingSenderId') ??
              _defaultSenderId,
      'projectId':
          await _storage.read(key: 'firebase_projectId') ?? _defaultProjectId,
      'authDomain':
          await _storage.read(key: 'firebase_authDomain') ?? _defaultAuthDomain,
      'storageBucket': await _storage.read(key: 'firebase_storageBucket') ??
          _defaultStorageBucket,
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
    await _storage.write(
        key: 'firebase_messagingSenderId', value: messagingSenderId);
    await _storage.write(key: 'firebase_projectId', value: projectId);
    if (authDomain != null) {
      await _storage.write(key: 'firebase_authDomain', value: authDomain);
    }
    if (storageBucket != null) {
      await _storage.write(key: 'firebase_storageBucket', value: storageBucket);
    }
    if (measurementId != null) {
      await _storage.write(key: 'firebase_measurementId', value: measurementId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_configuredKey, true);
  }

  /// Очистка старых overrides возвращает официальные defaults, а не состояние
  /// «покажи человеку setup-форму».
  Future<void> clearConfig() async {
    await _storage.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_configuredKey, true);
  }
}
