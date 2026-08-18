import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_endpoint.dart';
import 'package:wesios/core/sync/sync_engine.dart';
import 'package:wesios/core/sync/sync_journal.dart';
import 'package:wesios/core/sync/sync_merge.dart';
import 'package:wesios/core/sync/sync_transport.dart';

class _ReceiveRaceCollection extends SyncCollection<String> {
  static const String testBox = 'wesios_receive_race_probe';

  @override
  String get name => 'receive_race_probe';

  @override
  String get boxName => testBox;

  @override
  String idOf(String value) => value.split(':').first;

  @override
  Map<String, dynamic> encode(String value) => {'value': value};

  @override
  String? decode(Map<String, dynamic> fields) => fields['value'] as String?;
}

class _GatedFetchTransport implements SyncTransport {
  final Map<String, SyncRecord> server = {};
  final Completer<void> firstFetchStarted = Completer<void>();
  final Completer<void> releaseFirstFetch = Completer<void>();
  int fetchCount = 0;

  @override
  bool get isSignedIn => true;

  @override
  Future<SyncResult<Map<String, SyncRecord>>> fetch(String collection) async {
    fetchCount++;
    if (fetchCount == 1) {
      if (!firstFetchStarted.isCompleted) firstFetchStarted.complete();
      await releaseFirstFetch.future;
    }
    return SyncResult.ok(Map<String, SyncRecord>.from(server));
  }

  @override
  Future<SyncPushResult> push(
    String collection,
    List<SyncRecord> records,
  ) async {
    for (final record in records) {
      server[record.id] = SyncRecord(
        id: record.id,
        fields: Map<String, dynamic>.from(record.fields),
        updatedAt: record.updatedAt,
        deleted: record.deleted,
      );
    }
    return SyncPushResult(
      deliveredIds: records.map((r) => r.id).toList(),
      acceptedStamps: {
        for (final record in records) record.id: record.updatedAt,
      },
    );
  }

  @override
  Future<SyncResult<String>> signIn(String login, String password) async =>
      const SyncResult.ok('test');

  @override
  void signOut() {}
}

void main() {
  late Directory dir;
  late List<SyncCollection<dynamic>> originalCollections;
  final collection = _ReceiveRaceCollection();
  final base = DateTime.utc(2026, 8, 18, 8);

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_receive_race_');
    Hive.init(dir.path);
    await Hive.openBox<dynamic>('wesios_settings');
    await Hive.openBox<String>(_ReceiveRaceCollection.testBox);
  });

  setUp(() async {
    originalCollections = List<SyncCollection<dynamic>>.from(SyncCodec.collections);
    await SyncEngine.reset();
    SyncCodec.collections
      ..clear()
      ..add(collection);
    await Hive.box<dynamic>('wesios_settings').clear();
    await Hive.box<String>(_ReceiveRaceCollection.testBox).clear();
    await SyncJournal.open();
    await Hive.box<dynamic>(SyncJournal.boxName).clear();
    await SyncEndpoint.markRun(base.subtract(const Duration(days: 1)));
    await SyncEngine.prepare(now: base);
  });

  tearDown(() async {
    await SyncEngine.reset();
    SyncCodec.collections
      ..clear()
      ..addAll(originalCollections);
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('remote apply never overwrites edit made after merge snapshot', () async {
    final box = Hive.box<String>(_ReceiveRaceCollection.testBox);
    final oldLocalStamp = base.add(const Duration(minutes: 1));
    final remoteStamp = base.add(const Duration(minutes: 2));
    final newLocalStamp = base.add(const Duration(minutes: 3));

    await box.put('row', 'row:old-local');
    await Future<void>.delayed(Duration.zero);
    await SyncJournal.record(
      collection.name,
      'row',
      SyncStamp(oldLocalStamp),
    );

    final transport = _GatedFetchTransport()
      ..server['row'] = SyncRecord(
        id: 'row',
        updatedAt: remoteStamp,
        fields: const {'value': 'row:remote'},
      );

    final firstRun = SyncEngine.run(
      transport: transport,
      now: base.add(const Duration(minutes: 4)),
      only: {collection.name},
    );
    await transport.firstFetchStarted.future;

    // The engine continuation after the fetch runs as a microtask, builds its
    // merge snapshot, then yields on the optimistic precondition's zero-delay
    // Future. This already-queued Timer runs in that gap and simulates a user
    // edit arriving after the merge was calculated.
    final editDone = Completer<void>();
    Timer.run(() async {
      await box.put('row', 'row:new-user-edit');
      await Future<void>.delayed(Duration.zero);
      await SyncJournal.record(
        collection.name,
        'row',
        SyncStamp(newLocalStamp),
      );
      editDone.complete();
    });

    transport.releaseFirstFetch.complete();
    final firstReport = await firstRun;
    await editDone.future;

    expect(firstReport.ok, isFalse);
    expect(firstReport.firstFailure?.code, 'LOCAL_CHANGED_DURING_SYNC');
    expect(box.get('row'), 'row:new-user-edit');
    expect(
      SyncJournal.stampOf(collection.name, 'row')?.updatedAt,
      newLocalStamp,
      reason: 'new local edit must survive the stale receive plan',
    );
    expect(transport.server['row']?.fields['value'], 'row:remote');

    final secondReport = await SyncEngine.run(
      transport: transport,
      now: base.add(const Duration(minutes: 5)),
      only: {collection.name},
    );
    expect(secondReport.ok, isTrue, reason: secondReport.describe());
    expect(transport.server['row']?.fields['value'], 'row:new-user-edit');
  });
}
