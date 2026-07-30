import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/services/github_auth_service.dart';

void main() {
  late Directory tempDir;
  late Box<dynamic> box;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('wesios_gh_test');
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

  group('client_id', () {
    test('без правки в настройках берётся зашитый', () {
      expect(GitHubAuthService.clientId, GitHubAuthService.defaultClientId);
      expect(GitHubAuthService.isConfigured, isTrue);
    });

    test('зашитое значение похоже на настоящий id GitHub', () {
      // Не проверка «правильности» — её из тестов не сделать. Это ловушка на
      // порчу при переносе: лишний перевод строки или обрезанная строка
      // выглядели бы как рабочий id, а вход молча не начинался бы.
      const id = GitHubAuthService.defaultClientId;
      expect(id, startsWith('Ov23li'));
      expect(id.trim(), id, reason: 'по краям пробелы или перевод строки');
      expect(RegExp(r'^[A-Za-z0-9]+$').hasMatch(id), isTrue, reason: id);
      expect(id.length, greaterThanOrEqualTo(16));
    });

    test('значение из настроек перекрывает зашитое', () async {
      await GitHubAuthService.setClientId('Ov23liExample');
      expect(GitHubAuthService.clientId, 'Ov23liExample');
      expect(GitHubAuthService.isConfigured, isTrue);
    });

    test('пробелы по краям обрезаются — вставка из буфера часто тащит их',
        () async {
      await GitHubAuthService.setClientId('  Ov23liExample \n');
      expect(GitHubAuthService.clientId, 'Ov23liExample');
    });

    test('пустое значение возвращает к зашитому, а не отключает вход',
        () async {
      // Очистить поле — это «пользуйся встроенным», а не «сломай мне вход».
      await GitHubAuthService.setClientId('Ov23liExample');
      await GitHubAuthService.setClientId('   ');
      expect(GitHubAuthService.clientId, GitHubAuthService.defaultClientId);
      expect(GitHubAuthService.isConfigured, isTrue);
    });
  });

  group('состояние входа', () {
    test('без токена вход не выполнен и заголовков нет', () async {
      expect(GitHubAuthService.isSignedIn, isFalse);
      expect(await GitHubAuthService.authHeaders(), isEmpty);
    });

    test('с токеном появляется заголовок авторизации', () async {
      await box.put('github_token', 'gho_test');
      expect(GitHubAuthService.isSignedIn, isTrue);
      final headers = await GitHubAuthService.authHeaders();
      expect(headers['Authorization'], 'Bearer gho_test');
    });

    test('пустой токен не считается входом', () async {
      await box.put('github_token', '');
      expect(GitHubAuthService.isSignedIn, isFalse);
    });

    test('выход стирает токен, refresh, срок и имя аккаунта', () async {
      await box.putAll({
        'github_token': 'gho_test',
        'github_refresh_token': 'ghr_test',
        'github_token_expires': DateTime(2030).toIso8601String(),
        'github_login': 'wesiwer',
      });
      await GitHubAuthService.signOut();

      for (final key in [
        'github_token',
        'github_refresh_token',
        'github_token_expires',
        'github_login',
      ]) {
        expect(box.get(key), isNull, reason: key);
      }
      expect(GitHubAuthService.isSignedIn, isFalse);
    });

    test('client_id переживает выход — это не секрет и не часть сессии',
        () async {
      await GitHubAuthService.setClientId('Ov23liExample');
      await box.put('github_token', 'gho_test');
      await GitHubAuthService.signOut();
      expect(GitHubAuthService.clientId, 'Ov23liExample');
    });
  });

  group('срок действия', () {
    test('без срока токен считается бессрочным — так у OAuth-приложений',
        () async {
      await box.put('github_token', 'gho_test');
      expect(GitHubAuthService.expiresAt, isNull);
      expect(await GitHubAuthService.validToken(), 'gho_test');
    });

    test('живой токен отдаётся как есть', () async {
      await box.putAll({
        'github_token': 'gho_test',
        'github_token_expires':
            DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
      });
      expect(await GitHubAuthService.validToken(), 'gho_test');
    });

    test('просроченный токен без refresh не выдаётся', () async {
      await box.putAll({
        'github_token': 'gho_test',
        'github_token_expires':
            DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
      });
      expect(await GitHubAuthService.validToken(), isNull);
      expect(await GitHubAuthService.authHeaders(), isEmpty);
    });

    test('токен, который истечёт через полминуты, уже считается негодным', () async {
      // Иначе он протух бы посреди скачивания APK — то есть ровно тогда,
      // когда всё уже почти получилось.
      await box.putAll({
        'github_token': 'gho_test',
        'github_token_expires':
            DateTime.now().add(const Duration(seconds: 30)).toIso8601String(),
      });
      expect(await GitHubAuthService.validToken(), isNull);
    });

    test('битая дата срока не роняет проверку', () async {
      await box.putAll({
        'github_token': 'gho_test',
        'github_token_expires': 'не-дата',
      });
      expect(GitHubAuthService.expiresAt, isNull);
      expect(await GitHubAuthService.validToken(), 'gho_test');
    });
  });
}
