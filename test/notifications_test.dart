import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/notifications/wesi_notifications.dart';

/// Уведомления.
///
/// Проверяется не системный лоток, а решения: показывать или молчать,
/// повторять или нет, что делать с выключенным видом. Именно на них
/// уведомления и портятся — либо приходят по три раза, либо вываливаются
/// пачкой после включения.
class _FakeBackend implements NotificationBackend {
  final List<WesiNotification> shown = [];
  bool initialised = false;

  @override
  Future<void> init() async => initialised = true;

  @override
  Future<void> show(WesiNotification notification) async =>
      shown.add(notification);
}

void main() {
  late Directory dir;
  late _FakeBackend backend;

  WesiNotification note(String id, {NotifyKind kind = NotifyKind.alert}) =>
      WesiNotification(id: id, title: 'Заголовок', body: 'Текст', kind: kind);

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_notify');
    Hive.init(dir.path);
    await Hive.openBox<dynamic>('wesios_settings');
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    await Hive.box<dynamic>('wesios_settings').clear();
    WesiNotifications.reset();
    backend = _FakeBackend();
    WesiNotifications.backend = backend;
  });

  tearDown(WesiNotifications.reset);

  group('показ', () {
    test('новое событие показывается', () async {
      expect(await WesiNotifications.show(note('a')), isTrue);
      expect(backend.shown.single.id, 'a');
    });

    test('то же событие второй раз не показывается', () async {
      await WesiNotifications.show(note('a'));
      expect(await WesiNotifications.show(note('a')), isFalse);
      expect(backend.shown.length, 1,
          reason: 'повторы — главная причина, по которой уведомления '
              'выключают');
    });

    test('разные события показываются оба', () async {
      await WesiNotifications.show(note('a'));
      await WesiNotifications.show(note('b'));
      expect([for (final n in backend.shown) n.id], ['a', 'b']);
    });
  });

  group('первый запуск молчит', () {
    test('помеченное как виденное не показывается', () async {
      WesiNotifications.markSeen(['a', 'b']);

      expect(await WesiNotifications.show(note('a')), isFalse);
      expect(await WesiNotifications.show(note('b')), isFalse);
      expect(backend.shown, isEmpty,
          reason: 'накопленное к моменту запуска человек видит на главной, '
              'а пачка уведомлений в первую секунду — способ добиться, '
              'чтобы их выключили');
    });

    test('появившееся после — показывается', () async {
      WesiNotifications.markSeen(['a']);
      expect(await WesiNotifications.show(note('c')), isTrue);
    });
  });

  group('настройки', () {
    test('выключенные уведомления ничего не показывают', () async {
      await WesiNotifications.setEnabled(false);
      expect(await WesiNotifications.show(note('a')), isFalse);
      expect(backend.shown, isEmpty);
    });

    test('выключенный вид не показывается, остальные — да', () async {
      await WesiNotifications.setKindEnabled(NotifyKind.message, false);

      expect(await WesiNotifications.show(note('m', kind: NotifyKind.message)),
          isFalse);
      expect(await WesiNotifications.show(note('a')), isTrue);
    });

    test('пропущенное при выключенных не приходит пачкой после включения',
        () async {
      // Отпечаток запоминается, даже когда показывать нельзя. Иначе
      // выключенный вид копил бы «непоказанное», и включение оборачивалось
      // бы обвалом уведомлений за неделю.
      await WesiNotifications.setEnabled(false);
      for (final id in ['a', 'b', 'c']) {
        await WesiNotifications.show(note(id));
      }

      await WesiNotifications.setEnabled(true);
      for (final id in ['a', 'b', 'c']) {
        await WesiNotifications.show(note(id));
      }

      expect(backend.shown, isEmpty);
    });

    test('переключение поднимает отметку — экран настроек перечитывает',
        () async {
      final before = WesiNotifications.revision.value;
      await WesiNotifications.setEnabled(false);
      expect(WesiNotifications.revision.value, greaterThan(before));
    });
  });

  group('устойчивость', () {
    test('отказ платформы не роняет вызов', () async {
      WesiNotifications.backend = _BrokenBackend();
      expect(await WesiNotifications.show(note('a')), isFalse);
    });

    test('без платформы уведомления просто не показываются', () async {
      WesiNotifications.backend = null;
      expect(await WesiNotifications.show(note('a')), isFalse);
    });
  });
}

/// Платформа, которая отказывает. Так ведут себя Linux без демона
/// уведомлений и Android, где разрешение не выдали.
class _BrokenBackend implements NotificationBackend {
  @override
  Future<void> init() async => throw Exception('нет службы уведомлений');

  @override
  Future<void> show(WesiNotification notification) async =>
      throw Exception('нет службы уведомлений');
}
