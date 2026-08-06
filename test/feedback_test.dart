import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/feedback/wesi_feedback.dart';

/// Отклик на действие.
///
/// Проверять здесь можно ровно одно, но именно оно и ломается: решение
/// «звать платформу или молчать». Сама вибрация и звук в тестовой среде
/// недоступны, а если бы и были — проверять надо не колонки.
void main() {
  late Directory dir;
  final calls = <(FeedbackKind, bool, bool)>[];

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_feedback');
    Hive.init(dir.path);
    await Hive.openBox<dynamic>('wesios_settings');
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    calls.clear();
    await Hive.box<dynamic>('wesios_settings').clear();
    WesiFeedback.sink = (kind, haptic, sound) =>
        calls.add((kind, haptic, sound));
  });

  tearDown(WesiFeedback.reset);

  group('что умеет устройство', () {
    test('вибрация и звук не предлагаются на одной платформе сразу', () {
      // Телефон, пищащий на каждое нажатие, выключают в первый же день;
      // компьютер, обещающий вибрацию, врёт о своём железе.
      expect(WesiFeedback.supportsHaptics && WesiFeedback.supportsSound,
          isFalse);
    });

    test('на этой платформе доступно хоть что-то одно', () {
      // Тесты идут на настольной системе, значит звук.
      expect(WesiFeedback.supportsSound, isTrue);
      expect(WesiFeedback.supportsHaptics, isFalse);
    });
  });

  group('настройки', () {
    test('по умолчанию включено', () {
      expect(WesiFeedback.sound, isTrue);
    });

    test('выключенное не зовёт платформу', () async {
      await WesiFeedback.setSound(false);
      WesiFeedback.tap();

      expect(calls.single.$3, isFalse,
          reason: 'настройка, которая ничего не выключает, хуже её отсутствия');
    });

    test('переключение поднимает отметку — экраны перечитывают', () async {
      final before = WesiFeedback.revision.value;
      await WesiFeedback.setSound(false);
      expect(WesiFeedback.revision.value, greaterThan(before));
    });

    test('вибрация не включается там, где её нет', () async {
      await WesiFeedback.setHaptics(true);
      expect(WesiFeedback.haptics, isFalse,
          reason: 'сохранённая настройка не создаёт вибромотор');
    });
  });

  group('события', () {
    test('каждое событие доходит своим видом', () {
      WesiFeedback.tap();
      WesiFeedback.select();
      WesiFeedback.success();
      WesiFeedback.warning();
      WesiFeedback.error();
      WesiFeedback.send();
      WesiFeedback.receive();
      WesiFeedback.notify();

      expect([for (final c in calls) c.$1], FeedbackKind.values,
          reason: 'вид события не должен подменяться по дороге');
    });

    test('общий вход равнозначен именованному', () {
      WesiFeedback.of(FeedbackKind.error);
      expect(calls.single.$1, FeedbackKind.error);
    });

    test('вызов ничего не ждёт', () {
      // Отклик, из-за которого подтормаживает нажатие, хуже отсутствия
      // отклика. Сигнатура без Future — это и есть гарантия.
      expect(WesiFeedback.tap, isA<void Function()>());
    });
  });
}
