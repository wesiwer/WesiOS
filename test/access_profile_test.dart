import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/services/access_profile.dart';
import 'package:wesios/core/services/firebase_rest_service.dart';

void main() {
  late Directory tempDir;
  late Box<dynamic> box;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('wesios_access_test');
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
    await AccessProfile.clear();
  });

  Future<void> signInAs(String uid) async {
    await box.put(
      'firebase_session',
      jsonEncode({
        'idToken': 'token',
        'refreshToken': 'refresh',
        'uid': uid,
        'email': '$uid@wesi.local',
        'expiresAt': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      }),
    );
  }

  group('без входа', () {
    test('открыто всё — ограничивать некого', () {
      expect(AccessProfile.current, AccessProfile.defaults);
      for (final m in AccessProfile.modules) {
        expect(AccessProfile.allows(m), isTrue, reason: m);
      }
    });
  });

  group('умолчания', () {
    test('в наборе по умолчанию перечислены все модули', () {
      // Забытый в defaults модуль стал бы недоступен всем и сразу, причём
      // молча: он просто исчез бы с экрана.
      for (final m in AccessProfile.modules) {
        expect(AccessProfile.defaults.containsKey(m), isTrue, reason: m);
      }
    });

    test('умолчания не пустые', () {
      // Пустой набор означал бы, что человек вошёл и не увидел ничего —
      // это выглядит как поломка, а не как политика.
      expect(AccessProfile.defaults.values.any((v) => v), isTrue);
    });
  });

  group('кеш', () {
    test('читается, когда он от того же аккаунта', () async {
      await signInAs('uid-1');
      await box.put('access_profile_uid', 'uid-1');
      await box.put('access_profile', {
        for (final m in AccessProfile.modules) m: m == 'tasks',
      });

      expect(AccessProfile.allows('tasks'), isTrue);
      expect(AccessProfile.allows('treasury'), isFalse);
    });

    test('кеш чужого аккаунта не применяется', () async {
      // Сменили аккаунт — набор прав должен смениться вместе с ним, а не
      // остаться от предыдущего человека.
      await box.put('access_profile_uid', 'uid-1');
      await box.put('access_profile', {
        for (final m in AccessProfile.modules) m: false,
      });
      await signInAs('uid-2');

      expect(AccessProfile.current, AccessProfile.defaults,
          reason: 'должны быть умолчания, а не чужой урезанный набор');
    });

    test('выход стирает кеш', () async {
      await signInAs('uid-1');
      await box.put('access_profile_uid', 'uid-1');
      await box.put('access_profile', {'tasks': true});

      await AccessProfile.clear();
      expect(box.get('access_profile'), isNull);
      expect(box.get('access_profile_uid'), isNull);
    });

    test('битый кеш не роняет чтение', () async {
      await signInAs('uid-1');
      await box.put('access_profile_uid', 'uid-1');
      await box.put('access_profile', 'не-карта');
      expect(AccessProfile.current, AccessProfile.defaults);
    });
  });

  group('разбор значений из Firestore', () {
    test('неизвестное значение читается как запрет', () async {
      // Firestore отдаёт значения строками через наш REST-слой. Истиной
      // считается только явное 'true': неизвестное безопаснее прочитать как
      // «не открыто», чем как «открыто».
      await signInAs('uid-1');
      await box.put('access_profile_uid', 'uid-1');
      await box.put('access_profile', {
        'treasury': true,
        'tasks': false,
      });

      expect(AccessProfile.allows('treasury'), isTrue);
      expect(AccessProfile.allows('tasks'), isFalse);
      // Модуля нет в кеше вовсе — тоже запрет.
      expect(AccessProfile.allows('analytics'), isFalse);
    });

    test('неизвестный модуль всегда запрещён', () {
      expect(AccessProfile.allows('несуществующий_раздел'), isFalse);
    });
  });
}
