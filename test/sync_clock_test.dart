import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_clock.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_clock');
    Hive.init(dir.path);
    await Hive.openBox('wesios_settings');
  });

  tearDownAll(() async {
    await Hive.close();
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

  test('локальные sync timestamps строго возрастают и имеют миллисекундную точность',
      () {
    final stamps = List<DateTime>.generate(100, (_) => SyncClock.now());
    for (var i = 1; i < stamps.length; i++) {
      expect(stamps[i].isAfter(stamps[i - 1]), isTrue,
          reason:
              'две быстрые локальные правки не должны схлопываться в server timestamp tie');
      expect(stamps[i].microsecond, 0,
          reason: 'сервер JavaScript Date не сохраняет микросекунды');
    }
    expect(stamps.first.microsecond, 0);
  });

  test('логический watermark сохраняется в Hive', () async {
    final issued = SyncClock.now();
    await Hive.box('wesios_settings').flush();

    expect(
      Hive.box('wesios_settings').get('sync_clock_last_logical_ms'),
      issued.millisecondsSinceEpoch,
      reason:
          'последняя LWW-координата должна переживать завершение процесса',
    );
  });

  test('после перезапуска и отката системных часов timestamp не идёт назад',
      () async {
    final persisted =
        DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch;
    await Hive.box('wesios_settings')
        .put('sync_clock_last_logical_ms', persisted);

    // Новый процесс: память пустая, persisted Hive state остаётся.
    SyncClock.reloadProcessStateForTesting();
    final next = SyncClock.now();

    expect(next.millisecondsSinceEpoch, persisted + 1,
        reason:
            'физические часы позади persisted watermark, поэтому LWW clock обязан продолжить с +1ms');
  });

  test('полный reset удаляет и offset, и logical watermark', () async {
    SyncClock.now();
    await Hive.box('wesios_settings').flush();
    expect(
      Hive.box('wesios_settings').get('sync_clock_last_logical_ms'),
      isNotNull,
    );

    await SyncClock.reset();

    expect(Hive.box('wesios_settings').get('sync_clock_offset_ms'), isNull);
    expect(
      Hive.box('wesios_settings').get('sync_clock_last_logical_ms'),
      isNull,
    );
  });

  test('отстающие часы подтягиваются к серверу', () async {
    final ours = DateTime.utc(2026, 8, 12, 12);
    await SyncClock.observeServerDate(
      'Wed, 12 Aug 2026 12:10:00 GMT',
      sentAt: ours,
      receivedAt: ours.add(const Duration(milliseconds: 40)),
    );

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

    final before = SyncClock.offset;
    SyncClock.reloadProcessStateForTesting();
    expect(SyncClock.offset, before,
        reason: 'новый процесс обязан перечитать persisted offset');
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