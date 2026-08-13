import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_engine.dart';
import 'package:wesios/core/sync/sync_journal.dart';
import 'package:wesios/features/audio/models/audio_vault_models.dart';
import 'package:wesios/features/audio/services/audio_vault_service.dart';

import 'fake_sync_transport.dart';

/// Каталог битов не синхронизировался: он хранился одной строкой на весь
/// список и в обмене не участвовал. При этом аренда бита — это деньги и
/// сроки, и знать о ней должна вся команда, а не одно устройство.
///
/// Главная тонкость здесь — файлы. Путь `/data/.../AudioVault/<id>/mp3_…`
/// принадлежит устройству, а не карточке: приехав на другой телефон, он
/// указывал бы в пустоту.
void main() {
  late Directory dir;
  final base = DateTime.utc(2026, 8, 12, 10);

  BeatEntry beat(
    String id,
    String title, {
    String? mp3Path,
    BeatStage stage = BeatStage.idea,
    BeatLease? lease,
    DateTime? updatedAt,
  }) =>
      BeatEntry(
        id: id,
        title: title,
        authorEmployeeId: 'wesi',
        bpm: 140,
        musicalKey: 'Am',
        stage: stage,
        mp3Path: mp3Path,
        lease: lease,
        createdAt: base,
        updatedAt: updatedAt ?? base,
      );

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_audio_sync');
    Hive.init(dir.path);
    await Hive.openBox('wesios_settings');
    await Hive.openBox(SyncJournal.boxName);
    await Hive.openBox<String>(AudioVaultService.beatsBoxName);
  });

  tearDownAll(() async {
    await SyncEngine.reset();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    await SyncEngine.reset();
    await Hive.box('wesios_settings').clear();
    await Hive.box(SyncJournal.boxName).clear();
    await Hive.box<String>(AudioVaultService.beatsBoxName).clear();
    if (Hive.isBoxOpen(AudioVaultService.boxName)) {
      await Hive.box<dynamic>(AudioVaultService.boxName).clear();
    }
  });

  test('каталог битов участвует в обмене', () {
    final names = [for (final c in SyncCodec.collections) c.name];
    expect(names, contains('audio_beats'));
  });

  test('карточка уезжает, а путь к файлу — нет', () async {
    await AudioVaultService.save(
      beat('B1', 'Ночной', mp3Path: '/data/user/0/wesios/AudioVault/B1/x.mp3'),
    );
    await Future<void>.delayed(Duration.zero);

    final t = FakeSyncTransport();
    final report = await SyncEngine.run(transport: t, now: base);

    expect(report.ok, isTrue, reason: report.describe());
    final record = t.store['audio_beats']?['B1'];
    expect(record, isNotNull);
    expect(record!.fields['title'], 'Ночной');
    expect(record.fields['bpm'], 140);
    expect(record.fields.containsKey('mp3Path'), isFalse,
        reason: 'чужой путь на другом устройстве указывает в пустоту');
  });

  test('приехавшая карточка не затирает свои файлы', () async {
    // У нас бит уже есть, и файл лежит на диске.
    const myPath = '/data/user/0/wesios/AudioVault/B2/mine.mp3';
    await AudioVaultService.save(beat('B2', 'Старое имя', mp3Path: myPath));
    await Future<void>.delayed(Duration.zero);

    // Коллега переименовал его и перевёл в другую стадию.
    final t = FakeSyncTransport();
    final later = base.add(const Duration(hours: 1));
    t.seed(
      'audio_beats',
      'B2',
      beat('B2', 'Новое имя', stage: BeatStage.ready, updatedAt: later)
          .toJson()
        ..remove('mp3Path'),
      later,
    );

    await SyncEngine.run(
        transport: t, now: base.add(const Duration(hours: 2)));

    final mine = (await AudioVaultService.all()).firstWhere((b) => b.id == 'B2');
    expect(mine.title, 'Новое имя', reason: 'правка коллеги обязана доехать');
    expect(mine.stage, BeatStage.ready);
    expect(mine.mp3Path, myPath,
        reason: 'свой файл никуда не делся — путь обязан сохраниться');
  });

  test('условия аренды доезжают до команды', () async {
    final t = FakeSyncTransport();
    final leased = beat(
      'B3',
      'Сданный',
      lease: BeatLease(
        id: 'L1',
        artistName: 'Студия',
        socialUrl: '',
        startsAt: base,
        endsAt: base.add(const Duration(days: 365)),
        amount: 25000,
        currency: 'RUB',
        notes: '',
      ),
    );
    t.seed('audio_beats', 'B3', leased.toJson(), base);

    await SyncEngine.run(transport: t, now: base);

    final arrived =
        (await AudioVaultService.all()).firstWhere((b) => b.id == 'B3');
    expect(arrived.lease?.artistName, 'Студия');
    expect(arrived.lease?.amount, 25000);
  });

  test('удалённый бит не возвращается', () async {
    await AudioVaultService.save(beat('B4', 'Лишний'));
    await Future<void>.delayed(Duration.zero);

    final t = FakeSyncTransport();
    await SyncEngine.run(transport: t, now: base);
    expect(t.store['audio_beats']?['B4'], isNotNull);

    await AudioVaultService.delete(beat('B4', 'Лишний'));
    await Future<void>.delayed(Duration.zero);
    await SyncEngine.run(
        transport: t, now: base.add(const Duration(hours: 1)));

    expect(t.store['audio_beats']!['B4']!.deleted, isTrue);
    await SyncEngine.run(
        transport: t, now: base.add(const Duration(hours: 2)));
    expect((await AudioVaultService.all()).map((b) => b.id),
        isNot(contains('B4')));
  });

  test('правка одного бита не тянет за собой весь каталог', () async {
    for (var i = 1; i <= 6; i++) {
      await AudioVaultService.save(beat('K$i', 'Бит $i'));
    }
    await Future<void>.delayed(Duration.zero);

    final t = FakeSyncTransport();
    await SyncEngine.run(transport: t, now: base);
    t.calls.clear();

    await AudioVaultService.save(beat('K3', 'Бит 3',
        updatedAt: base.add(const Duration(hours: 1))));
    await Future<void>.delayed(Duration.zero);
    await SyncJournal.record('audio_beats', 'K3',
        SyncStamp(base.add(const Duration(hours: 1))));

    await SyncEngine.run(
        transport: t, now: base.add(const Duration(hours: 2)));

    final pushes =
        t.calls.where((c) => c.startsWith('push:audio_beats:')).toList();
    expect(pushes, ['push:audio_beats:1'],
        reason: 'на сервер уехал лишний каталог: $pushes');
  });

  test('каталог из старого формата переносится, а не пропадает', () async {
    final legacy = await Hive.openBox<dynamic>(AudioVaultService.boxName);
    await legacy.clear();
    await legacy.put('beats_v1', [
      beat('OLD1', 'Старый бит').toJson(),
      beat('OLD2', 'Второй старый').toJson(),
    ]);

    final all = await AudioVaultService.all();
    expect(all.map((b) => b.id), containsAll(['OLD1', 'OLD2']));

    // Повторное обращение не плодит дублей и не откатывает правки.
    await AudioVaultService.save(beat('OLD1', 'Переименован'));
    final again = await AudioVaultService.all();
    expect(again.where((b) => b.id == 'OLD1').length, 1);
    expect(again.firstWhere((b) => b.id == 'OLD1').title, 'Переименован');
  });

  test('запись, которую эта версия не понимает, не попадает в каталог',
      () async {
    final t = FakeSyncTransport();
    t.seed('audio_beats', 'BROKEN', {'somethingNew': 1}, base);
    t.seed('audio_beats', 'FINE', beat('FINE', 'Обычный').toJson(), base);

    await SyncEngine.run(transport: t, now: base);

    final ids = (await AudioVaultService.all()).map((b) => b.id);
    expect(ids, contains('FINE'));
    expect(ids, isNot(contains('BROKEN')));
  });

  test('в боксе лежит ровно то, что можно прочитать обратно', () async {
    await AudioVaultService.save(beat('B9', 'Проверка'));
    final raw = Hive.box<String>(AudioVaultService.beatsBoxName).get('B9');
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!);
    expect(decoded, isA<Map<String, dynamic>>());
    expect(BeatEntry.fromJson(decoded as Map<String, dynamic>).title,
        'Проверка');
  });
}
