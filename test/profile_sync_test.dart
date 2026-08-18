import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_endpoint.dart';
import 'package:wesios/core/sync/sync_engine.dart';
import 'package:wesios/core/sync/sync_journal.dart';
import 'package:wesios/features/profile/services/profile_service.dart';

import 'fake_sync_transport.dart';

/// «Чтобы у меня на моих устройствах профили были одинаковыми».
///
/// Профиль лежал в `wesios_settings` вместе с адресом сервера и пропуском
/// сессии, а тот бокс не синхронизируется — и не должен. Заполнив профиль на
/// компьютере, человек видел на телефоне пустые поля.
void main() {
  late Directory dir;
  final base = DateTime.utc(2026, 8, 12, 10);

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_profile_sync');
    Hive.init(dir.path);
    await Hive.openBox('wesios_settings');
    await Hive.openBox(SyncJournal.boxName);
    await Hive.openBox<String>(ProfileService.boxName);
  });

  tearDownAll(() async {
    await SyncEngine.reset();
    await SyncEndpoint.clearSession();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    await SyncEngine.reset();
    await SyncEndpoint.clearSession();
    await Hive.box('wesios_settings').clear();
    await Hive.box(SyncJournal.boxName).clear();
    await ProfileService.clearForTest();
  });

  test('профиль участвует в обмене', () {
    final names = [for (final c in SyncCodec.collections) c.name];
    expect(names, contains('profile'));
  });

  test('заполненный профиль уезжает на сервер', () async {
    await ProfileService.write(
      name: 'Веси',
      email: 'wesi@example.com',
      gender: 'Мужской',
      country: 'Россия',
      birth: DateTime.utc(1998, 5, 17),
      avatarIndex: 3,
    );
    await Future<void>.delayed(Duration.zero);

    final t = FakeSyncTransport();
    final report = await SyncEngine.run(transport: t, now: base);

    expect(report.ok, isTrue, reason: report.describe());
    final record = t.store['profile']?[ProfileService.recordKey];
    expect(record, isNotNull, reason: 'профиль обязан оказаться на сервере');
    expect(record!.fields['name'], 'Веси');
    expect(record.fields['email'], 'wesi@example.com');
    expect(record.fields['avatarIndex'], 3);
  });

  test('профиль с другого устройства виден на экране сразу', () async {
    final t = FakeSyncTransport();
    t.seed('profile', ProfileService.recordKey, {
      'name': 'Веси',
      'email': 'wesi@example.com',
      'gender': 'Мужской',
      'country': 'Россия',
      'birth': '1998-05-17T00:00:00.000Z',
      'avatarIndex': 5,
    }, base);

    await SyncEngine.run(transport: t, now: base);

    final settings = Hive.box('wesios_settings');
    expect(settings.get('profile_name'), 'Веси');
    expect(settings.get('profile_email'), 'wesi@example.com');
    expect(settings.get('profile_country'), 'Россия');
    expect(settings.get('avatar_index'), 5);
  });

  test('загруженная аватарка переезжает вместе с профилем', () async {
    final photo = Uint8List.fromList(List<int>.generate(128, (i) => i % 256));
    await ProfileService.write(
      name: 'Веси',
      email: '',
      gender: '',
      country: '',
      photo: photo,
    );
    await Future<void>.delayed(Duration.zero);

    final t = FakeSyncTransport();
    await SyncEngine.run(transport: t, now: base);

    final record = t.store['profile']![ProfileService.recordKey]!;
    expect(record.fields['photo'], base64Encode(photo));

    await ProfileService.clearForTest();
    await Hive.box('wesios_settings').clear();
    await SyncEngine.reset();
    await SyncEngine.prepare(now: base);
    await SyncEngine.run(
        transport: t, now: base.add(const Duration(minutes: 1)));

    final stored = Hive.box('wesios_settings').get('avatar_custom');
    expect(stored, isNotNull);
    expect(Uint8List.fromList(List<int>.from(stored as List)), photo);
  });

  test('слишком большая картинка не уезжает целиком', () async {
    final huge = Uint8List(ProfileService.maxPhotoBytes + 1);
    await ProfileService.write(
      name: 'Веси',
      email: '',
      gender: '',
      country: '',
      photo: huge,
    );
    final data = await ProfileService.read();
    expect(data.containsKey('photo'), isFalse,
        reason: 'запись с картинкой больше лимита сервер отвергнет целиком, '
            'и профиль перестанет синхронизироваться вообще');
    expect(data['name'], 'Веси', reason: 'остальной профиль обязан сохраниться');
  });

  test('legacy профиль ждёт подтверждённый auth-user и затем переносится',
      () async {
    final settings = Hive.box('wesios_settings');
    await settings.put('profile_name', 'Старое имя');
    await settings.put('profile_email', 'old@example.com');
    await settings.put('avatar_index', 2);

    final beforeLogin = await ProfileService.read();
    expect(beforeLogin, isEmpty,
        reason: 'legacy private data нельзя присваивать anonymous namespace');
    expect(settings.get('profile_name'), 'Старое имя',
        reason: 'до входа legacy профиль нельзя уничтожать');

    await SyncEndpoint.saveSession(
      token: 'test-token',
      userId: 'legacy-auth-user',
      sessionId: 'test-session',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );

    final data = await ProfileService.read();
    expect(data['name'], 'Старое имя',
        reason: 'первый подтверждённый auth-user обязан забрать legacy профиль');
    expect(data['email'], 'old@example.com');
    expect(data['avatarIndex'], 2);
  });

  test('пустой профиль не отправляется и не затирает чужой', () async {
    final data = await ProfileService.read();
    expect(data, isEmpty);

    final t = FakeSyncTransport();
    t.seed('profile', ProfileService.recordKey, {
      'name': 'Настоящий профиль',
      'email': 'real@example.com',
      'avatarIndex': 0,
    }, base);

    await SyncEngine.run(transport: t, now: base);

    expect(t.store['profile']![ProfileService.recordKey]!.fields['name'],
        'Настоящий профиль',
        reason: 'пустая заготовка не должна затирать заполненный профиль');
    expect(Hive.box('wesios_settings').get('profile_name'),
        'Настоящий профиль');
  });

  test('секреты в профиль не попадают', () async {
    final settings = Hive.box('wesios_settings');
    await settings.put('sync_session', {'token': 'секрет'});
    await settings.put('sync_url', 'https://api.example.com');
    await settings.put('profile_name', 'Веси');

    final data = await ProfileService.read();
    final flat = jsonEncode(data);
    expect(flat.contains('секрет'), isFalse);
    expect(flat.contains('api.example.com'), isFalse);
  });
}