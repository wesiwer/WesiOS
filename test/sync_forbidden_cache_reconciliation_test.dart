import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_endpoint.dart';
import 'package:wesios/core/sync/sync_engine.dart';
import 'package:wesios/core/sync/sync_journal.dart';

import 'fake_sync_transport.dart';

class _PolicyCollection extends SyncCollection<String> {
  static const String testBox = 'wesios_policy_cache_probe';

  @override
  String get name => 'policy_cache_probe';

  @override
  String get boxName => testBox;

  @override
  String idOf(String value) => value.split(':').first;

  @override
  Map<String, dynamic> encode(String value) => {'value': value};

  @override
  String? decode(Map<String, dynamic> fields) => fields['value'] as String?;
}

void main() {
  late Directory dir;
  late List<SyncCollection<dynamic>> originalCollections;
  final collection = _PolicyCollection();
  final base = DateTime.utc(2026, 8, 18, 7);

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_policy_cache_');
    Hive.init(dir.path);
    await Hive.openBox<dynamic>('wesios_settings');
    await Hive.openBox<String>(_PolicyCollection.testBox);
  });

  setUp(() async {
    originalCollections = List<SyncCollection<dynamic>>.from(SyncCodec.collections);
    await SyncEngine.reset();
    SyncCodec.collections
      ..clear()
      ..add(collection);
    await Hive.box<dynamic>('wesios_settings').clear();
    await Hive.box<String>(_PolicyCollection.testBox).clear();
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

  test('row removed from permission-filtered remote snapshot is purged locally',
      () async {
    final box = Hive.box<String>(_PolicyCollection.testBox);
    await box.put('secret', 'secret:cached-from-previous-access');
    await Future<void>.delayed(Duration.zero);

    final transport = FakeSyncTransport()..forbiddenIds.add('secret');
    final report = await SyncEngine.run(
      transport: transport,
      now: base.add(const Duration(minutes: 1)),
      only: {collection.name},
    );

    expect(report.ok, isTrue, reason: report.describe());
    expect(box.containsKey('secret'), isFalse,
        reason:
            'a row the current server identity can no longer read must not remain cached');
    final stamp = SyncJournal.stampOf(collection.name, 'secret');
    expect(stamp?.deleted, isTrue);
    expect(stamp?.updatedAt.millisecondsSinceEpoch, 0,
        reason:
            'permission tombstone is account-local and deliberately loses to a future restored server row');
  });

  test('visible but read-only row rolls forbidden local edit back to remote',
      () async {
    final box = Hive.box<String>(_PolicyCollection.testBox);
    await box.put('row', 'row:local-forbidden-edit');
    await Future<void>.delayed(Duration.zero);
    final localStamp = base.add(const Duration(minutes: 10));
    await SyncJournal.record(collection.name, 'row', SyncStamp(localStamp));

    final remoteStamp = base.add(const Duration(minutes: 2));
    final transport = FakeSyncTransport()
      ..seed(
        collection.name,
        'row',
        const {'value': 'row:server-authoritative'},
        remoteStamp,
      )
      ..forbiddenIds.add('row');

    final report = await SyncEngine.run(
      transport: transport,
      now: base.add(const Duration(minutes: 11)),
      only: {collection.name},
    );

    expect(report.ok, isTrue, reason: report.describe());
    expect(box.get('row'), 'row:server-authoritative');
    expect(
      SyncJournal.stampOf(collection.name, 'row')?.updatedAt,
      remoteStamp,
      reason:
          'read-only cache must converge to the exact server LWW coordinate',
    );
  });
}
