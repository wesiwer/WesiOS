import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/security/shield_service.dart';

void main() {
  group('PBKDF2 — соответствие RFC 6070', () {
    // Официальные тест-векторы PBKDF2-HMAC-SHA256. Без них «работает» значило
    // бы только «не падает»: самодельная реализация KDF может давать
    // стабильный, но неправильный — и потому более слабый — результат.
    test('P="password", S="salt", c=1', () {
      final hex = base64
          .decode(ShieldService.derive('password', 'salt', 1))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      expect(
        hex,
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });

    test('P="password", S="salt", c=2', () {
      final hex = base64
          .decode(ShieldService.derive('password', 'salt', 2))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      expect(
        hex,
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
    });

    test('P="password", S="salt", c=4096', () {
      final hex = base64
          .decode(ShieldService.derive('password', 'salt', 4096))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      expect(
        hex,
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
    });
  });

  group('derive', () {
    test('разная соль даёт разный ключ при одном пароле — иначе одинаковые '
        'пароли двух пользователей имели бы одинаковый хэш', () {
      final a = ShieldService.derive('secret', 'salt-a', 1000);
      final b = ShieldService.derive('secret', 'salt-b', 1000);
      expect(a, isNot(b));
    });

    test('одинаковый вход даёт одинаковый выход', () {
      expect(
        ShieldService.derive('secret', 'salt', 1000),
        ShieldService.derive('secret', 'salt', 1000),
      );
    });

    test('число итераций входит в результат — иначе понизить стойкость можно '
        'было бы, просто подменив счётчик в хранилище', () {
      expect(
        ShieldService.derive('secret', 'salt', 1000),
        isNot(ShieldService.derive('secret', 'salt', 2000)),
      );
    });

    test('ключ имеет полную длину SHA-256', () {
      expect(base64.decode(ShieldService.derive('x', 'y', 10)).length, 32);
    });
  });

  group('passwordStrength', () {
    test('слишком короткий пароль — ноль', () {
      expect(ShieldService.passwordStrength('abc'), 0);
    });

    test('длина и разнообразие символов повышают оценку', () {
      final short = ShieldService.passwordStrength('abcdefgh');
      final withDigits = ShieldService.passwordStrength('abcdefgh1');
      final long = ShieldService.passwordStrength('abcdefgh1234');
      final withSymbols = ShieldService.passwordStrength('abcdefgh1234!');

      expect(withDigits, greaterThan(short));
      expect(long, greaterThan(withDigits));
      expect(withSymbols, greaterThan(long));
    });

    test('оценка не выходит за 0..4', () {
      expect(
        ShieldService.passwordStrength('Very-Long-Password-1234!@#\$%^&*'),
        4,
      );
      expect(ShieldService.passwordStrength(''), 0);
    });
  });

  group('перенос старого замка на ключах', () {
    late Directory tempDir;
    late Box<dynamic> box;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('wesios_shield_test');
      Hive.init(tempDir.path);
      box = await Hive.openBox<dynamic>('wesios_settings');
    });

    tearDownAll(() async {
      await Hive.close();
      tempDir.deleteSync(recursive: true);
    });

    setUp(() async {
      await box.clear();
    });

    /// Кладёт в хранилище пароль ровно в том виде, в каком его писал прежний
    /// VaultLockService: SHA-256 от «соль + пароль».
    Future<void> writeLegacy(String password, {bool biometrics = false}) async {
      const salt = 'legacy-salt';
      await box.put(
        'vault_pass_hash',
        sha256.convert(utf8.encode('$salt$password')).toString(),
      );
      await box.put('vault_pass_salt', salt);
      if (biometrics) await box.put('vault_biometrics_enabled', true);
    }

    test('старый пароль продолжает подходить после обновления', () async {
      await writeLegacy('old-secret');
      expect(ShieldService.isConfigured, isTrue);
      expect(await ShieldService.verify('old-secret'), isTrue);
    });

    test('чужой пароль по-прежнему не подходит', () async {
      await writeLegacy('old-secret');
      expect(await ShieldService.verify('not-it'), isFalse);
      // Неудача не должна стирать старый пароль: иначе одна ошибка чужого
      // человека отрезала бы владельца от собственных ключей.
      expect(ShieldService.hasLegacyPassword, isTrue);
    });

    test('после успешного входа слабый SHA-256 заменяется на PBKDF2', () async {
      await writeLegacy('old-secret');
      await ShieldService.verify('old-secret');

      expect(box.get('vault_pass_hash'), isNull);
      expect(box.get('vault_pass_salt'), isNull);
      expect(box.get('shield_hash'), isA<String>());
      expect(box.get('shield_iterations'), isA<int>());
      // И тот же пароль работает уже через новую схему.
      expect(await ShieldService.verify('old-secret'), isTrue);
    });

    test('включённая биометрия переносится вместе с паролем', () async {
      await writeLegacy('old-secret', biometrics: true);
      await ShieldService.verify('old-secret');
      expect(ShieldService.biometricsEnabled, isTrue);
    });

    test('без старого пароля и без нового защита не считается настроенной',
        () async {
      expect(ShieldService.isConfigured, isFalse);
      expect(await ShieldService.verify('anything'), isFalse);
    });
  });
}
