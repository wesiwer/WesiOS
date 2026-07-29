import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:local_auth/local_auth.dart';

/// Замок на секции с ключами Firebase.
///
/// Ключи Firebase — это доступ к бэкенду проекта, и до сих пор они лежали
/// в профиле открытым текстом: любой, кто взял разблокированное устройство,
/// мог их прочитать. Теперь секция закрыта паролем, а на телефоне её можно
/// открыть отпечатком или сканом лица.
///
/// Пароль **не хранится**: в Hive лежит только соль и SHA-256 от
/// «соль + пароль». Проверка сравнивает хэши, поэтому даже полный доступ
/// к хранилищу не выдаёт исходный пароль.
class VaultLockService {
  static const String _box = 'wesios_settings';
  static const String _hashKey = 'vault_pass_hash';
  static const String _saltKey = 'vault_pass_salt';
  static const String _bioKey = 'vault_biometrics_enabled';

  static final LocalAuthentication _auth = LocalAuthentication();

  /// Пароль уже задан (при первом запуске или позже в профиле).
  static bool get isConfigured {
    try {
      final box = Hive.box(_box);
      final h = box.get(_hashKey);
      return h is String && h.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt$password')).toString();

  static String _newSalt() {
    // Random.secure() — криптографический источник; обычный Random
    // предсказуем и для соли не годится.
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64Url.encode(bytes);
  }

  static Future<void> setPassword(String password) async {
    final salt = _newSalt();
    final box = Hive.box(_box);
    await box.put(_saltKey, salt);
    await box.put(_hashKey, _hash(password, salt));
  }

  static bool verify(String password) {
    try {
      final box = Hive.box(_box);
      final salt = box.get(_saltKey);
      final stored = box.get(_hashKey);
      if (salt is! String || stored is! String) return false;
      return _hash(password, salt) == stored;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clear() async {
    final box = Hive.box(_box);
    await box.delete(_hashKey);
    await box.delete(_saltKey);
    await box.delete(_bioKey);
  }

  // ===== Биометрия =====

  static bool get biometricsEnabled {
    try {
      return Hive.box(_box).get(_bioKey, defaultValue: false) as bool;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setBiometricsEnabled(bool value) async {
    await Hive.box(_box).put(_bioKey, value);
  }

  /// Есть ли на устройстве настроенный отпечаток/скан лица.
  ///
  /// Только мобильные: на десктопе local_auth либо не поддерживается, либо
  /// ведёт себя непредсказуемо, поэтому там опция просто не предлагается.
  static Future<bool> get isBiometricAvailable async {
    if (kIsWeb) return false;
    if (!(Platform.isAndroid || Platform.isIOS)) return false;
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Запрашивает биометрию. false — не подтвердил или недоступно; вызывающий
  /// код должен в этом случае предложить обычный пароль, а не блокировать
  /// доступ насовсем.
  static Future<bool> authenticateBiometric(String reason) async {
    if (!await isBiometricAvailable) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
