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

class _StampCollection extends SyncCollection<String> {
  static const String testBox = 'wesios_push_stamp_probe';

  @override
  String get name => 'push_stamp_probe';

  @override
  String get boxName => testBox;

  @override
  String idOf(String value) => value.split(':').first;

  @override
  Map<String, dynamic> encode(String value) => {'value': value};

  @override
  String? decode(Map<String, dynamic> fields) => fields['value'] as String?;
}

class _StampTransport implements SyncTransport {
  final DateTime? acceptedStamp;
  final bool omitStamp;
  final Map<String, SyncRecord> server = {};

  _StampTransport({this.acceptedStamp, this.omitStamp = false});

  @override
  bool get isSignedIn => true;

  @override
  Future<SyncResult<Map<String, SyncRecord>>> fetch(String collection) async =>
      SyncResult.ok(Map<String, SyncRecord>.from(server));

  @override
  Future<SyncPushResult> push(
    String collection,
    List<SyncRecord> records,
  ) async {
    final delivered = <String>[];
    final stamps = <String, DateTime>{};
    for (final record in records) {
      final stamp = acceptedStamp ?? record.updatedAt;
      server[record.id] = SyncRecord(
        id: record.id,
        fields: record.fields,
        updatedAt: stamp,
        deleted: record.deleted,
      );
      delivered.add(record.id);
      if (!omitStamp) stamps[record.id] = stamp;
    }
    return SyncPushResult(
      deliveredIds: delivered,
      acceptedStamps: stamps,
      failure: omitStamp
          ? const SyncFailure(
              'REMOTE_DATA_INVALID',
              'Сервер принял запись, но не вернул stamp',
            )
          : null,
    );
  }

  @override
  Future<SyncResult<String>> signIn(String login, String password) async =>
      const SyncResult.ok('test');

  @override
  void signOut() {}
}

class _DelayedFirstPushTransport implements SyncTransport {
  final DateTime firstAcceptedStamp;
  final Map<String, SyncRecord> server = {};
  final Completer<void> firstPushStarted = Completer<void>();
  final Completer<void> releaseFirstPush = Completer<void>();
  int pushCount = 0;

  _DelayedFirstPushTransport(this.firstAcceptedStamp);

  @override
  bool get isSignedIn => true;

  @override
  Future<SyncResult<Map<String, SyncRecord>>> fetch(String collection) async =>
      SyncResult.ok(Map<String, SyncRecord>.from(server));

  @override
  Future<SyncPushResult> push(
    String collection,
    List<SyncRecord> records,
  ) async {
    pushCount++;
    final thisPush = pushCount;
    if (thisPush == 1) {
      if (!firstPushStarted.isCompleted) firstPushStarted.complete();
      await releaseFirstPush.future;
    }

    final stamps = <String, DateTime>{};
    for (final record in records) {
      final stamp = thisPush == 1 ? firstAcceptedStamp : record.updatedAt;
      server[record.id] = SyncRecord(
        id: record.id,
        fields: Map<String, dynamic>.from(record.fields),
        updatedAt: stamp,
        deleted: record.deleted,
      );
      stamps[record.id] = stamp;
    }
    return SyncPushResult(
      deliveredIds: records.map((r) => r.id).toList(),
      acceptedStamps: stamps,
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
  final collection = _StampCollection();
  final base = DateTime.utc(2026, 8, 18, 6);

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_push_stamp_');
    Hive.init(dir.path);
    await Hive.openBox<dynamic>('wesios_settings');
    await Hive.openBox<String>(_StampCollection.testBox);
  });

  setUp(() async {
    originalCollections = List<SyncCollection<dynamic>>.from(SyncCodec.collections);
    await SyncEngine.reset();
    SyncCodec.collections
      ..clear()
      ..add(collection);
    await Hive.box<dynamic>('wesios_settings').clear();
    await Hive.box<String>(_StampCollection.testBox).clear();
    await SyncJournal.open();
    await Hive.box<dynamic>(SyncJournal.boxName).clear();

    await SyncEndpoint.markRun(base.subtract(const Duration(days: 1)));
    await SyncEngine.prepare(now: base);
    await Hive.box<String>(_StampCollection.testBox).put('row', 'row:local');
    await Future<void>.delayed(Duration.zero);
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

  test('server-clamped push timestamp replaces the future local journal stamp',
      () async {
    final localFuture = base.add(const Duration(days: 2));
    final serverAccepted = base.add(const Duration(seconds: 2));
    await SyncJournal.record(collection.name, 'row', SyncStamp(localFuture));

    final transport = _StampTransport(acceptedStamp: serverAccepted);
    final report = await SyncEngine.run(
      transport: transport,
      now: base.add(const Duration(seconds: 5)),
      only: {collection.name},
    );

    expect(report.ok, isTrue, reason: report.describe());
    expect(report.uploaded, 1);
    expect(
      SyncJournal.stampOf(collection.name, 'row')?.updatedAt,
      serverAccepted,
      reason:
          'local LWW coordinate must match the timestamp actually committed by the server',
    );
  });

  test('delivered row without a valid returned stamp is demoted to epoch',
      () async {
    final localFuture = base.add(const Duration(days: 2));
    await SyncJournal.record(collection.name, 'row', SyncStamp(localFuture));

    final transport = _StampTransport(
      acceptedStamp: base.add(const Duration(seconds: 2)),
      omitStamp: true,
    );
    final report = await SyncEngine.run(
      transport: transport,
      now: base.add(const Duration(seconds: 5)),
      only: {collection.name},
    );

    expect(report.ok, isFalse);
    expect(report.firstFailure?.code, 'REMOTE_DATA_INVALID');
    expect(
      SyncJournal.stampOf(collection.name, 'row')?.updatedAt.millisecondsSinceEpoch,
      0,
      reason:
          'unknown accepted server time must force a safe authoritative pull, not preserve a future local stamp',
    );
  });

  test('new local edit made while older push is in flight keeps its newer stamp',
      () async {
    final box = Hive.box<String>(_StampCollection.testBox);
    final firstStamp = base.add(const Duration(minutes: 1));
    await SyncJournal.record(collection.name, 'row', SyncStamp(firstStamp));

    final transport = _DelayedFirstPushTransport(
      base.add(const Duration(minutes: 1, seconds: 1)),
    );
    final firstRun = SyncEngine.run(
      transport: transport,
      now: base.add(const Duration(minutes: 2)),
      only: {collection.name},
    );

    await transport.firstPushStarted.future;

    // The user edits the same record while HTTP still carries the older
    // `row:local` snapshot.
    await box.put('row', 'row:newer-user-edit');
    await Future<void>.delayed(Duration.zero);
    final newerStamp = base.add(const Duration(minutes: 3));
    await SyncJournal.record(collection.name, 'row', SyncStamp(newerStamp));

    transport.releaseFirstPush.complete();
    final firstReport = await firstRun;
    expect(firstReport.ok, isTrue, reason: firstReport.describe());

    expect(box.get('row'), 'row:newer-user-edit');
    expect(
      SyncJournal.stampOf(collection.name, 'row')?.updatedAt,
      newerStamp,
      reason:
          'response for an older plan must never overwrite a newer local journal stamp',
    );
    expect(
      transport.server['row']?.fields['value'],
      'row:local',
      reason: 'the first HTTP request intentionally carried the older snapshot',
    );

    // Because the newer stamp survived, the very next pass can upload the
    // newer payload instead of losing it to an equal/older remote timestamp.
    final secondReport = await SyncEngine.run(
      transport: transport,
      now: base.add(const Duration(minutes: 4)),
      only: {collection.name},
    );
    expect(secondReport.ok, isTrue, reason: secondReport.describe());
    expect(transport.server['row']?.fields['value'], 'row:newer-user-edit');
  });
}
