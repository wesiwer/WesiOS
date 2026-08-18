import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_engine.dart';
import 'package:wesios/core/sync/sync_journal.dart';
import 'package:wesios/core/sync/sync_merge.dart';
import 'package:wesios/core/sync/sync_transport.dart';

class _StringCollection extends SyncCollection<String> {
  @override
  String get name => 'lifecycle_test';

  @override
  String get boxName => 'wesios_sync_lifecycle_test';

  @override
  String idOf(String value) => value.split(':').first;

  @override
  Map<String, dynamic> encode(String value) => {'value': value};

  @override
  String? decode(Map<String, dynamic> fields) => fields['value'] as String?;
}

class _DelayedTransport implements SyncTransport {
  final Completer<void> fetchStarted = Completer<void>();
  final Completer<SyncResult<Map<String, SyncRecord>>> fetchResult =
      Completer<SyncResult<Map<String, SyncRecord>>>();

  @override
  bool get isSignedIn => true;

  @override
  Future<SyncResult<Map<String, SyncRecord>>> fetch(String collection) {
    if (!fetchStarted.isCompleted) fetchStarted.complete();
    return fetchResult.future;
  }

  @override
  Future<SyncPushResult> push(String collection, List<SyncRecord> records) async =>
      SyncPushResult(deliveredIds: records.map((e) => e.id).toList());

  @override
  Future<SyncResult<String>> signIn(String login, String password) async =>
      const SyncResult.ok('test');

  @override
  void signOut() {}
}

void main() {
  late Directory dir;
  late List<SyncCollection<dynamic>> originalCollections;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_sync_lifecycle_');
    Hive.init(dir.path);
    await Hive.openBox<dynamic>('wesios_settings');
  });

  setUp(() async {
    originalCollections = List<SyncCollection<dynamic>>.from(SyncCodec.collections);
    await SyncEngine.reset();
    SyncCodec.collections
      ..clear()
      ..add(_StringCollection());
    await Hive.openBox<String>('wesios_sync_lifecycle_test');
    await Hive.box<String>('wesios_sync_lifecycle_test').clear();
    await SyncJournal.open();
    await Hive.box<dynamic>(SyncJournal.boxName).clear();
    await Hive.box<dynamic>('wesios_settings').clear();
  });

  tearDown(() async {
    await SyncEngine.reset();
    SyncCodec.collections
      ..clear()
      ..addAll(originalCollections);
    if (Hive.isBoxOpen('wesios_sync_lifecycle_test')) {
      await Hive.box<String>('wesios_sync_lifecycle_test').close();
    }
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('invalidated run cannot apply a fetch that completed after account switch',
      () async {
    final transport = _DelayedTransport();
    final run = SyncEngine.run(
      transport: transport,
      now: DateTime.utc(2026, 8, 18, 1),
    );

    await transport.fetchStarted.future;
    SyncEngine.invalidateActiveRun();
    transport.fetchResult.complete(SyncResult.ok({
      'remote': SyncRecord(
        id: 'remote',
        updatedAt: DateTime.utc(2026, 8, 18, 2),
        fields: const {'value': 'remote:secret'},
      ),
    }));

    final report = await run;
    expect(report.ok, isFalse);
    expect(report.firstFailure?.code, 'SESSION_CHANGED');
    expect(
      Hive.box<String>('wesios_sync_lifecycle_test').containsKey('remote'),
      isFalse,
      reason: 'remote data from the old lifecycle must never reach a new box',
    );
  });
}
