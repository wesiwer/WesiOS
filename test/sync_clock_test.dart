import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_clock.dart';

/// Споры между устройствами решает время правки, и до этой версии его брали
/// с часов самого устройства. Часы расходятся: на телефоне их ведёт оператор,
/// на компьютере — сеть или никто. Правка, сделанная позже, проигрывала
/// правке с отстающего устройства, и человек видел это как «мои изменения не
/// сохранились».
void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_clock');
    Hive.init(dir.path);
    await Hive.openBox('wesios_settings');
  });

  tearDownAll(() async {
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    await Hive.box('wesios_settings').clear();
    await SyncClock.reset();
  });

  test('без сверки часы остаются своими', () {
    expect(SyncClock.offset, Duration.zero);
    final delta = SyncClock.now().difference(DateTime.now()).abs();
    expect(delta, lessThan(const Duration(seconds: 1)));
  });

  test('отстающие часы подтягиваются к серверу', () async {
    // Наши часы показывают 12:00, сервер отвечает, что сейчас 12:10.
    final ours = DateTime.utc(2026, 8, 12, 12);
    await SyncClock.observeServerDate(
      'Wed, 12 Aug 2026 12:10:00 GMT',
      sentAt: ours,
      receivedAt: ours.add(const Duration(milliseconds: 40)),
    );

    // Половина сетевой задержки честно вычитается, поэтому сравниваем с
    // допуском, а не с ровным числом минут.
    expect((SyncClock.offset - const Duration(minutes: 10)).abs(),
        lessThan(const Duration(seconds: 1)),
        reason: 'смещение обязано быть замечено целиком');
  });

  test('спешащие часы тоже выправляются', () async {
    final ours = DateTime.utc(2026, 8, 12, 12, 5);
    await SyncClock.observeServerDate(
      'Wed, 12 Aug 2026 12:00:00 GMT',
      sentAt: ours,
      receivedAt: ours.add(const Duration(milliseconds: 40)),
    );
    expect((SyncClock.offset + const Duration(minutes: 5)).abs(),
        lessThan(const Duration(seconds: 1)));
  });

  test('сетевая задержка делится пополам, а не приписывается серверу',
      () async {
    // Запрос ушёл в 12:00:00, ответ пришёл в 12:00:04 — сервер сформировал
    // его примерно в 12:00:02. Часы совпадают, смещения быть не должно.
    final sent = DateTime.utc(2026, 8, 12, 12, 0, 0);
    await SyncClock.observeServerDate(
      'Wed, 12 Aug 2026 12:00:02 GMT',
      sentAt: sent,
      receivedAt: sent.add(const Duration(seconds: 4)),
    );
    expect(SyncClock.offset.abs(), lessThan(const Duration(seconds: 2)));
  });

  test('смещение переживает перезапуск', () async {
    final ours = DateTime.utc(2026, 8, 12, 12);
    await SyncClock.observeServerDate(
      'Wed, 12 Aug 2026 12:07:00 GMT',
      sentAt: ours,
      receivedAt: ours.add(const Duration(milliseconds: 20)),
    );
    expect(Hive.box('wesios_settings').get('sync_clock_offset_ms'), isNotNull,
        reason: 'правки до первого обмена должны попасть в ту же шкалу');
  });

  test('бессмысленный заголовок не уносит правки в другой век', () async {
    final ours = DateTime.utc(2026, 8, 12, 12);
    await SyncClock.observeServerDate(
      'Mon, 01 Jan 1990 00:00:00 GMT',
      sentAt: ours,
      receivedAt: ours.add(const Duration(milliseconds: 20)),
    );
    expect(SyncClock.offset, Duration.zero);
  });

  test('мусор вместо заголовка просто не учитывается', () async {
    final ours = DateTime.utc(2026, 8, 12, 12);
    for (final raw in ['', 'вообще не дата', 'Xyz, 99 Zzz 2026']) {
      await SyncClock.observeServerDate(raw,
          sentAt: ours, receivedAt: ours.add(const Duration(milliseconds: 5)));
      expect(SyncClock.offset, Duration.zero, reason: 'на «$raw»');
    }
    await SyncClock.observeServerDate(null,
        sentAt: ours, receivedAt: ours);
    expect(SyncClock.offset, Duration.zero);
  });

  test('дрожание в пределах секунды не переписывает смещение', () async {
    final ours = DateTime.utc(2026, 8, 12, 12);
    await SyncClock.observeServerDate(
      'Wed, 12 Aug 2026 12:10:00 GMT',
      sentAt: ours,
      receivedAt: ours.add(const Duration(milliseconds: 20)),
    );
    final first = SyncClock.offset;

    // Тот же сервер, тот же ответ, но секундная точность заголовка дала
    // соседнюю секунду. Это не расхождение часов.
    await SyncClock.observeServerDate(
      'Wed, 12 Aug 2026 12:10:01 GMT',
      sentAt: ours,
      receivedAt: ours.add(const Duration(milliseconds: 20)),
    );
    expect(SyncClock.offset, first);
  });

  test('время по общей шкале сдвинуто ровно на смещение', () async {
    final ours = DateTime.utc(2026, 8, 12, 12);
    await SyncClock.observeServerDate(
      'Wed, 12 Aug 2026 12:03:00 GMT',
      sentAt: ours,
      receivedAt: ours.add(const Duration(milliseconds: 20)),
    );
    final shift = SyncClock.now().difference(DateTime.now());
    expect((shift - const Duration(minutes: 3)).abs(),
        lessThan(const Duration(seconds: 2)));
  });
}
