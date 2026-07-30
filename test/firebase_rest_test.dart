import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/services/firebase_rest_service.dart';

void main() {
  late Directory tempDir;
  late Box<dynamic> box;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('wesios_fb_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox<dynamic>('wesios_settings');
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await box.clear();
    await FirebaseRestService.signOut();
  });

  group('настройка проекта', () {
    test('по умолчанию берётся проект из google-services.json', () {
      expect(FirebaseProject.apiKey, FirebaseProject.defaultApiKey);
      expect(FirebaseProject.projectId, FirebaseProject.defaultProjectId);
      expect(FirebaseProject.isConfigured, isTrue);
    });

    test('зашитые значения не пустые и похожи на настоящие', () {
      // Ловушка на порчу при переносе, а не проверка правильности: пустой
      // или обрезанный ключ выглядел бы рабочим, а вход молча не проходил бы.
      expect(FirebaseProject.defaultApiKey, startsWith('AIza'));
      expect(FirebaseProject.defaultApiKey.length, greaterThan(30));
      expect(FirebaseProject.defaultProjectId, isNotEmpty);
      expect(FirebaseProject.defaultProjectId.trim(),
          FirebaseProject.defaultProjectId);
    });

    test('значения из настроек перекрывают зашитые', () async {
      await FirebaseProject.configure(
          apiKey: 'AIzaTest', projectId: 'wesios-test');
      expect(FirebaseProject.apiKey, 'AIzaTest');
      expect(FirebaseProject.projectId, 'wesios-test');
      expect(FirebaseProject.isConfigured, isTrue);
    });

    test('пробелы обрезаются — вставка из консоли часто тащит их', () async {
      await FirebaseProject.configure(
          apiKey: '  AIzaTest\n', projectId: ' wesios-test ');
      expect(FirebaseProject.apiKey, 'AIzaTest');
      expect(FirebaseProject.projectId, 'wesios-test');
    });

    test('пустое переопределение возвращает к зашитому, а не ломает вход',
        () async {
      await FirebaseProject.configure(apiKey: 'AIzaTest', projectId: '');
      expect(FirebaseProject.apiKey, 'AIzaTest');
      expect(FirebaseProject.projectId, FirebaseProject.defaultProjectId);
      expect(FirebaseProject.isConfigured, isTrue);
    });
  });

  group('вход при пустом проекте', () {
    test('честно говорит «не настроен», а не молчит', () {
      // Прямой проверки без сети тут не сделать, поэтому проверяем сам
      // текст отказа: он должен объяснять причину, а не быть пустым.
      expect(
        const FirebaseFailure('NOT_CONFIGURED', '').describe(),
        'Проект Firebase не настроен',
      );
    });
  });

  group('сессия', () {
    FirebaseSession make({Duration offset = const Duration(hours: 1)}) =>
        FirebaseSession(
          idToken: 'id-token',
          refreshToken: 'refresh-token',
          uid: 'uid-123',
          email: 'ceo@wesi.inc',
          expiresAt: DateTime.now().add(offset),
        );

    test('переживает перезапуск', () async {
      await box.put('firebase_session', jsonEncode(make().toJson()));
      expect(FirebaseRestService.isSignedIn, isTrue);
      expect(FirebaseRestService.session!.uid, 'uid-123');
      expect(FirebaseRestService.session!.email, 'ceo@wesi.inc');
    });

    test('выход стирает её', () async {
      await box.put('firebase_session', jsonEncode(make().toJson()));
      await FirebaseRestService.signOut();
      expect(FirebaseRestService.isSignedIn, isFalse);
      expect(box.get('firebase_session'), isNull);
    });

    test('«не запоминать» стирает копию на диске, но не выкидывает из входа',
        () async {
      // Выкинуть человека из уже выполненного входа было бы странным
      // прочтением «не запоминай».
      await box.put('firebase_session', jsonEncode(make().toJson()));
      expect(FirebaseRestService.isSignedIn, isTrue);

      await FirebaseRestService.forgetOnExit();
      expect(box.get('firebase_session'), isNull);
      expect(FirebaseRestService.isSignedIn, isTrue,
          reason: 'сессия в памяти должна остаться');
    });

    test('битая запись не считается сессией и не роняет чтение', () async {
      await box.put('firebase_session', 'не-json');
      expect(FirebaseRestService.isSignedIn, isFalse);
    });

    test('запись без обязательных полей отбрасывается', () async {
      await box.put('firebase_session', jsonEncode({'email': 'a@b.c'}));
      expect(FirebaseRestService.isSignedIn, isFalse);
    });

    test('живая сессия не считается истёкшей', () {
      expect(make().isExpired, isFalse);
    });

    test('истёкшая — считается', () {
      expect(make(offset: const Duration(minutes: -5)).isExpired, isTrue);
    });

    test('сессия, истекающая через полминуты, уже негодна', () {
      // Иначе токен протух бы посреди запроса — то есть ровно тогда, когда
      // всё уже почти получилось.
      expect(make(offset: const Duration(seconds: 30)).isExpired, isTrue);
    });
  });

  group('человеческие сообщения об ошибках', () {
    test('коды Firebase переводятся, а не показываются как есть', () {
      const cases = {
        'EMAIL_NOT_FOUND': 'Неверная почта или пароль',
        'INVALID_PASSWORD': 'Неверная почта или пароль',
        'INVALID_LOGIN_CREDENTIALS': 'Неверная почта или пароль',
        'USER_DISABLED': 'Учётная запись отключена',
        'PERMISSION_DENIED':
            'Доступ к ключам не разрешён для этой учётной записи',
      };
      cases.forEach((code, expected) {
        expect(const FirebaseFailure('', '').runtimeType, FirebaseFailure);
        expect(FirebaseFailure(code, 'raw').describe(), expected);
      });
    });

    test('неверная почта и неверный пароль звучат одинаково', () {
      // Разные формулировки подсказали бы подбирающему, что почта угадана.
      expect(
        const FirebaseFailure('EMAIL_NOT_FOUND', '').describe(),
        const FirebaseFailure('INVALID_PASSWORD', '').describe(),
      );
    });

    test('незнакомый код показывается как есть, а не глотается', () {
      expect(
        const FirebaseFailure('WEIRD_NEW_CODE', 'что-то новое').describe(),
        'что-то новое',
      );
    });
  });
}
