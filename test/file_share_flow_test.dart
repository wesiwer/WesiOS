import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_engine.dart';
import 'package:wesios/core/sync/sync_journal.dart';
import 'package:wesios/features/audio/models/audio_vault_models.dart';
import 'package:wesios/features/files/models/file_share_models.dart';
import 'package:wesios/features/files/services/file_access_policy.dart';
import 'package:wesios/features/files/services/file_share_service.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';

import 'fake_sync_transport.dart';

/// Путь запроса целиком: попросил → у владельца появилось → он решил →
/// решение вернулось → файл отдан и записан в журнал.
///
/// Сам файл в обмене не участвует: едет только описание. Проверяется именно
/// это — что описание доезжает и что содержимое за собой не тянет.
void main() {
  late Directory dir;
  final base = DateTime.utc(2026, 8, 13, 10);

  EmployeeModel person(
    String id, {
    List<String> modules = const [TeamModules.audio],
    bool manageTeam = false,
  }) =>
      EmployeeModel(
        id: id,
        login: id,
        fullName: id,
        createdAt: base,
        permissions: TeamPermissions(
          moduleList: modules,
          canManageTeam: manageTeam,
        ),
      );

  BeatEntry beatOf(String authorId) => BeatEntry(
        id: 'B1',
        title: 'Ночной',
        authorEmployeeId: authorId,
        createdAt: base,
        updatedAt: base,
      );

  FileShareRequest request(String id, String requesterId, {String holder = ''}) =>
      FileShareRequest(
        id: id,
        subjectKind: ShareSubjectKind.beat,
        subjectId: 'B1',
        fileKind: ShareFileKind.wav,
        requesterId: requesterId,
        holderId: holder,
        createdAt: base,
      );

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_file_flow');
    Hive.init(dir.path);
    await Hive.openBox('wesios_settings');
    await Hive.openBox(SyncJournal.boxName);
    await Hive.openBox<String>(FileShareService.requestsBoxName);
    await Hive.openBox<String>(FileShareService.grantsBoxName);
    await Hive.openBox<String>(FileShareService.handoversBoxName);
  });

  tearDownAll(() async {
    await SyncEngine.reset();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    await SyncEngine.reset();
    await Hive.box('wesios_settings').clear();
    await Hive.box(SyncJournal.boxName).clear();
    await FileShareService.clearForTest();
  });

  test('запросы, доступы и журнал участвуют в обмене', () {
    final names = [for (final c in SyncCodec.collections) c.name];
    expect(names, containsAll(['file_requests', 'file_grants',
        'file_handovers']));
    // Разрешение обязано приезжать раньше запроса, иначе запрос выглядел бы
    // самовольным, хотя разрешение просто ещё не доехало.
    expect(names.indexOf('file_grants'), lessThan(names.indexOf('file_requests')));
  });

  test('запрос с телефона появляется у владельца на компьютере', () async {
    await FileShareService.saveRequest(request('R1', 'ivan', holder: 'wesi'));
    await Future<void>.delayed(Duration.zero);

    final t = FakeSyncTransport();
    final report = await SyncEngine.run(transport: t, now: base);

    expect(report.ok, isTrue, reason: report.describe());
    final record = t.store['file_requests']?['R1'];
    expect(record, isNotNull);
    expect(record!.fields['requesterId'], 'ivan');
    expect(record.fields['fileKind'], 'wav');
  });

  test('владелец видит только адресованные ему запросы', () async {
    await FileShareService.saveRequest(request('R1', 'ivan', holder: 'wesi'));
    await FileShareService.saveRequest(request('R2', 'petr', holder: 'oleg'));
    await FileShareService.saveRequest(request('R3', 'petr'));

    final mine = await FileShareService.incoming('wesi');
    final ids = mine.map((r) => r.id).toList();
    expect(ids, contains('R1'));
    expect(ids, contains('R3'), reason: 'запрос без адресата — ко всем сразу');
    expect(ids, isNot(contains('R2')));
  });

  test('свой запрос не показывается как входящий', () async {
    await FileShareService.saveRequest(request('R1', 'wesi'));
    expect(await FileShareService.incoming('wesi'), isEmpty);
    expect((await FileShareService.outgoing('wesi')).length, 1);
  });

  test('решение владельца возвращается запросившему', () async {
    await FileShareService.saveRequest(request('R1', 'ivan', holder: 'wesi'));
    await Future<void>.delayed(Duration.zero);
    final t = FakeSyncTransport();
    await SyncEngine.run(transport: t, now: base);

    // Владелец отказал — на его устройстве запись обновилась и уехала.
    final decided = request('R1', 'ivan', holder: 'wesi').copyWith(
      status: ShareRequestStatus.declined,
      decidedAt: base.add(const Duration(minutes: 5)),
      decidedBy: 'wesi',
      declineReason: 'Бит ещё не сведён',
    );
    await FileShareService.saveRequest(decided);
    await Future<void>.delayed(Duration.zero);
    await SyncJournal.record('file_requests', 'R1',
        SyncStamp(base.add(const Duration(minutes: 5))));

    await SyncEngine.run(
        transport: t, now: base.add(const Duration(minutes: 6)));

    final onServer = t.store['file_requests']!['R1']!;
    expect(onServer.fields['status'], 'declined');
    expect(onServer.fields['declineReason'], 'Бит ещё не сведён',
        reason: 'человеку важнее причина, чем факт отказа');
  });

  test('отозванный доступ исчезает на всех устройствах', () async {
    final grant = FileAccessGrant(
      id: 'G1',
      subjectKind: ShareSubjectKind.beat,
      subjectId: 'B1',
      employeeId: 'ivan',
      grantedBy: 'wesi',
      grantedAt: base,
    );
    await FileShareService.saveGrant(grant);
    await Future<void>.delayed(Duration.zero);

    final t = FakeSyncTransport();
    await SyncEngine.run(transport: t, now: base);
    expect(t.store['file_grants']?['G1'], isNotNull);

    await FileShareService.revokeGrant('G1');
    await Future<void>.delayed(Duration.zero);
    // Отметку ставим явно: журнал берёт настоящее «сейчас», а у теста своя
    // шкала времени, и без этого надгробие оказалось бы старше записи на
    // сервере — то есть проиграло бы ей по правилам слияния.
    await SyncJournal.record('file_grants', 'G1',
        SyncStamp(base.add(const Duration(minutes: 30)), deleted: true));
    await SyncEngine.run(
        transport: t, now: base.add(const Duration(hours: 1)));

    expect(t.store['file_grants']!['G1']!.deleted, isTrue,
        reason: 'иначе отозванный доступ вернётся с другого устройства');
  });

  test('запись журнала доезжает вместе с отпечатком файла', () async {
    await FileShareService.recordHandover(FileHandover(
      id: 'H1',
      subjectKind: ShareSubjectKind.beat,
      subjectId: 'B1',
      fileKind: ShareFileKind.wav,
      fromEmployeeId: 'wesi',
      toEmployeeId: 'ivan',
      sizeBytes: 48000000,
      checksum: 'sha256:abc',
      at: base,
      route: ShareRoute.lan,
      requestId: 'R1',
    ));
    await Future<void>.delayed(Duration.zero);

    final t = FakeSyncTransport();
    await SyncEngine.run(transport: t, now: base);

    final record = t.store['file_handovers']!['H1']!;
    expect(record.fields['checksum'], 'sha256:abc');
    expect(record.fields['route'], 'lan');
    expect(record.fields['sizeBytes'], 48000000);
  });

  test('запрос без ответа истекает, а не висит вечно', () async {
    await FileShareService.saveRequest(request('R1', 'ivan', holder: 'wesi'));

    // Через день — ещё ждёт.
    expect(await FileShareService.expireStale(base.add(const Duration(days: 1))),
        0);
    expect((await FileShareService.requests()).first.status,
        ShareRequestStatus.pending);

    // Через восемь дней — истёк.
    expect(await FileShareService.expireStale(base.add(const Duration(days: 8))),
        1);
    final after = (await FileShareService.requests()).first;
    expect(after.status, ShareRequestStatus.expired);
    expect(after.isOpen, isFalse);
  });

  test('истёкший запрос не превращается обратно в ожидающий', () async {
    await FileShareService.saveRequest(request('R1', 'ivan'));
    await FileShareService.expireStale(base.add(const Duration(days: 8)));
    final again =
        await FileShareService.expireStale(base.add(const Duration(days: 9)));
    expect(again, 0, reason: 'повторный проход не должен ничего менять');
  });

  test('весь путь: попросил, получил разрешение, забрал, записалось', () async {
    final ivan = person('ivan');
    final wesi = person('wesi');
    final beat = beatOf('wesi');

    // 1. Ивану нельзя — доступ не открывали.
    var decision = FileAccessPolicy.canRequest(
      requester: ivan,
      subjectKind: ShareSubjectKind.beat,
      subjectId: 'B1',
      beat: beat,
      grants: await FileShareService.grantsFor(ShareSubjectKind.beat, 'B1'),
      now: base,
    );
    expect(decision.allowed, isFalse);

    // 2. Веси открывает доступ.
    await FileShareService.saveGrant(FileAccessGrant(
      id: 'G1',
      subjectKind: ShareSubjectKind.beat,
      subjectId: 'B1',
      employeeId: 'ivan',
      grantedBy: 'wesi',
      grantedAt: base,
    ));

    // 3. Теперь можно просить.
    decision = FileAccessPolicy.canRequest(
      requester: ivan,
      subjectKind: ShareSubjectKind.beat,
      subjectId: 'B1',
      beat: beat,
      grants: await FileShareService.grantsFor(ShareSubjectKind.beat, 'B1'),
      now: base,
    );
    expect(decision.allowed, isTrue);
    await FileShareService.saveRequest(request('R1', 'ivan', holder: 'wesi'));

    // 4. Веси видит запрос и вправе отдать.
    expect((await FileShareService.incoming('wesi')).map((r) => r.id),
        contains('R1'));
    final release = FileAccessPolicy.canRelease(
      holder: wesi,
      requester: ivan,
      subjectKind: ShareSubjectKind.beat,
      subjectId: 'B1',
      beat: beat,
      grants: await FileShareService.grantsFor(ShareSubjectKind.beat, 'B1'),
      now: base,
    );
    expect(release.allowed, isTrue);
    expect(release.needsOwnerConfirmation, isFalse);

    // 5. Отдал — запрос закрыт, в журнале запись.
    await FileShareService.saveRequest(
      request('R1', 'ivan', holder: 'wesi').copyWith(
        status: ShareRequestStatus.delivered,
        decidedAt: base.add(const Duration(minutes: 2)),
        decidedBy: 'wesi',
      ),
    );
    await FileShareService.recordHandover(FileHandover(
      id: 'H1',
      subjectKind: ShareSubjectKind.beat,
      subjectId: 'B1',
      fileKind: ShareFileKind.wav,
      fromEmployeeId: 'wesi',
      toEmployeeId: 'ivan',
      at: base.add(const Duration(minutes: 3)),
      route: ShareRoute.lan,
      requestId: 'R1',
    ));

    expect(await FileShareService.incoming('wesi'), isEmpty,
        reason: 'закрытый запрос не должен висеть у владельца');
    final log =
        await FileShareService.handoversFor(ShareSubjectKind.beat, 'B1');
    expect(log.single.toEmployeeId, 'ivan');
    expect(log.single.requestId, 'R1');
  });
}
