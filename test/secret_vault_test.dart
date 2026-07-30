import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/security/secret_vault.dart';

void main() {
  late Directory tempDir;
  late Box<dynamic> box;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('wesios_vault_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox<dynamic>('wesios_settings');
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await box.clear();
    SecretVault.lock();
  });

  group('закрытое хранилище', () {
    test('без разблокировки не читается и не пишется', () async {
      expect(SecretVault.read('firebase_apiKey'), isNull);
      expect(await SecretVault.write('firebase_apiKey', 'AIza…'), isFalse);
    });

    test('без пароля Shield причина — «пароль не задан»', () {
      expect(SecretVault.lockReason, VaultLockReason.noPassword);
    });

    test('после unlock причина исчезает', () async {
      await SecretVault.unlock('correct horse battery staple');
      expect(SecretVault.lockReason, isNull);
      expect(SecretVault.unlocked.value, isTrue);
    });
  });

  group('запись и чтение', () {
    setUp(() async {
      await SecretVault.unlock('correct horse battery staple');
    });

    test('что записали, то и прочитали', () async {
      await SecretVault.write('firebase_apiKey', 'AIzaSyExample123');
      expect(SecretVault.read('firebase_apiKey'), 'AIzaSyExample123');
    });

    test('в Hive лежит шифротекст, а не значение', () async {
      await SecretVault.write('token', 'очень-секретное-значение');
      final stored = box.get('vault_secret_token');
      expect(stored, isA<String>());
      expect(stored as String, isNot(contains('очень-секретное')));
      // И в base64 тоже не должно проглядывать.
      expect(utf8.decode(base64.decode(stored), allowMalformed: true),
          isNot(contains('очень-секретное')));
    });

    test('одно значение дважды даёт разный шифротекст', () async {
      // Одинаковый результат означал бы фиксированный nonce: по совпадению
      // записей стало бы видно, что два ключа равны между собой.
      await SecretVault.write('a', 'одно и то же');
      final first = box.get('vault_secret_a') as String;
      await SecretVault.write('a', 'одно и то же');
      final second = box.get('vault_secret_a') as String;
      expect(first, isNot(second));
      expect(SecretVault.read('a'), 'одно и то же');
    });

    test('юникод и длинные значения переживают цикл', () async {
      final long = 'Ключ №1 — ${'я' * 5000} 🔐';
      await SecretVault.write('long', long);
      expect(SecretVault.read('long'), long);
    });

    test('пустое значение тоже шифруется и читается', () async {
      await SecretVault.write('empty', '');
      expect(SecretVault.read('empty'), '');
    });

    test('имена видны, значения — нет', () async {
      await SecretVault.write('firebase_apiKey', 'x');
      await SecretVault.write('stripe', 'y');
      expect(SecretVault.names, ['firebase_apiKey', 'stripe']);

      SecretVault.lock();
      // Список остаётся: сам факт наличия ключа не секрет.
      expect(SecretVault.names, ['firebase_apiKey', 'stripe']);
      expect(SecretVault.read('stripe'), isNull);
    });
  });

  group('чужой пароль', () {
    test('другим паролем значение не открывается', () async {
      await SecretVault.unlock('правильный-пароль');
      await SecretVault.write('token', 'секрет');

      SecretVault.lock();
      await SecretVault.unlock('неправильный-пароль');
      expect(SecretVault.read('token'), isNull);
    });

    test('и не превращается в мусор, который приняли бы за данные', () async {
      // Ровно за это выбран GCM: он проверяет тег и честно отказывается,
      // а не отдаёт правдоподобную с виду строку.
      await SecretVault.unlock('правильный-пароль');
      await SecretVault.write('token', 'секрет');
      SecretVault.lock();
      await SecretVault.unlock('неправильный-пароль');

      final result = SecretVault.read('token');
      expect(result, isNull);
      expect(result, isNot('секрет'));
    });

    test('верный пароль после неверного снова открывает', () async {
      await SecretVault.unlock('правильный-пароль');
      await SecretVault.write('token', 'секрет');
      SecretVault.lock();
      await SecretVault.unlock('чужой');
      expect(SecretVault.read('token'), isNull);
      SecretVault.lock();
      await SecretVault.unlock('правильный-пароль');
      expect(SecretVault.read('token'), 'секрет');
    });
  });

  group('порча данных', () {
    setUp(() async {
      await SecretVault.unlock('пароль');
    });

    test('изменённый шифротекст не расшифровывается', () async {
      await SecretVault.write('token', 'секрет');
      final stored = base64.decode(box.get('vault_secret_token') as String);
      // Переворачиваем один бит в теле сообщения.
      stored[stored.length - 5] ^= 0x01;
      await box.put('vault_secret_token', base64.encode(stored));

      expect(SecretVault.read('token'), isNull);
    });

    test('подменённый тег аутентификации тоже отвергается', () async {
      await SecretVault.write('token', 'секрет');
      final stored = base64.decode(box.get('vault_secret_token') as String);
      stored[stored.length - 1] ^= 0xFF;
      await box.put('vault_secret_token', base64.encode(stored));

      expect(SecretVault.read('token'), isNull);
    });

    test('обрезанная запись не роняет чтение', () async {
      await box.put('vault_secret_token', base64.encode([1, 2, 3]));
      expect(SecretVault.read('token'), isNull);
    });

    test('мусор вместо base64 не роняет чтение', () async {
      await box.put('vault_secret_token', 'не-base64-вовсе!!!');
      expect(SecretVault.read('token'), isNull);
    });
  });

  group('удаление', () {
    test('delete убирает и запись, и имя', () async {
      await SecretVault.unlock('пароль');
      await SecretVault.write('token', 'секрет');
      await SecretVault.delete('token');
      expect(SecretVault.names, isEmpty);
      expect(box.get('vault_secret_token'), isNull);
    });

    test('wipe стирает всё и закрывает хранилище', () async {
      await SecretVault.unlock('пароль');
      await SecretVault.write('a', '1');
      await SecretVault.write('b', '2');
      await SecretVault.wipe();

      expect(SecretVault.names, isEmpty);
      expect(box.get('vault_kdf_salt'), isNull);
      expect(SecretVault.unlocked.value, isFalse);
    });
  });

  group('соль', () {
    test('переживает перезапуск — иначе тот же пароль дал бы другой ключ',
        () async {
      await SecretVault.unlock('пароль');
      final salt = box.get('vault_kdf_salt');
      expect(salt, isA<String>());

      SecretVault.lock();
      await SecretVault.unlock('пароль');
      expect(box.get('vault_kdf_salt'), salt);
    });

    test('соль хранилища отличается от соли пароля Shield', () async {
      // Из одного пароля не должно получаться одинакового материала для
      // разных целей: иначе хэш пароля и ключ шифрования оказались бы
      // связаны напрямую.
      await box.put('shield_salt', 'shield-salt-value');
      await SecretVault.unlock('пароль');
      expect(box.get('vault_kdf_salt'), isNot('shield-salt-value'));
    });
  });
}
