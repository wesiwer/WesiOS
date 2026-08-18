import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_endpoint.dart';
import 'package:wesios/core/sync/sync_engine.dart';
import 'package:wesios/core/sync/sync_journal.dart';
import 'package:wesios/core/sync/sync_merge.dart';
import 'package:wesios/core/sync/sync_transport.dart';

class _AuthorityCollection extends SyncCollection<String> {
  final String suffix;
  _AuthorityCollection(this.suffix);

  @override
  String get name => 'authority_probe_$suffix';

  @override
  String get boxName => 'wesios_authority_probe_$suffix';

  @override
  String idOf(String value) => value.split(':').first;

  @override
  Map<String, dynamic> encode(String value) => {'value': value};

  @override
  String? decode(Map<String, dynamic> fields) => fields['value'] as String?;
}

class _AppliedFalseTransport implements SyncTransport {
  final String collection;
  final SyncRecord beforePush;
  final SyncRecord afterPush;
  final Future<void> Function()? onPush;
  int fetchCount = 0;

  _AppliedFalseTransport({
    required this.collection,
    required this.beforePush,
    required this.afterPush,
    this.onPush,
  });

  @override
  bool get isSignedIn => true;

  @override
  Future<SyncResult<Map<String, SyncRecord>>> fetch(String name) async {
    expect(name, collection);
    fetchCount++;
    final row = fetchCount == 1 ? beforePush : afterPush;
    return SyncResult.ok({row.id: row});
  }

  @override
  Future<SyncPushResult> push(
    String name,
    List<SyncRecord> records,
  ) async {
    expect(name, collection);
    expect(records.map((e) => e.id), contains(afterPush.id));
    if (onPush != null) await onPush!();
    return SyncPushResult(
      authoritativeIds: [afterPush.id],
      authoritativeStamps: {afterPush.id: afterPush.updatedAt},
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
  final base = DateTime.utc(2026, 8, 18, 12);

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_authority_reject_');
    Hive.init(dir.path);
    await Hive.openBox<dynamic>('wesios_settings');
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

  Future<(_AuthorityCollection, Box<String>)> prepare(String suffix) async {
    originalCollections = List<SyncCollection<dynamic>>.from(SyncCodec.collections);
    await SyncEngine.reset();
    await Hive.box<dynamic>('wesios_settings').clear();

    final collection = _AuthorityCollection(suffix);
    SyncCodec.collections
      ..clear()
      ..add(collection);

    final box = Hive.isBoxOpen(collection.boxName)
        ? Hive.box<String>(collection.boxName)
        : await Hive.openBox<String>(collection.boxName);
    await box.clear();
    await box.put('row', 'row:local-planned');

    await SyncJournal.open();
    await Hive.box<dynamic>(SyncJournal.boxName).clear();
    await SyncEndpoint.markRun(base.subtract(const Duration(days: 1)));
    await SyncEngine.prepare(now: base);
    await SyncJournal.record(
      collection.name,
      'row',
      SyncStamp(base.add(const Duration(minutes: 2))),
    );
    return (collection, box);
  }

  test('applied:false refetches and applies server payload immediately', () async {
    final (collection, box) = await prepare('apply');
    final remoteBefore = SyncRecord(
      id: 'row',
      fields: const {'value': 'row:server-old'},
      updatedAt: base.add(const Duration(minutes: 1)),
    );
    final remoteAfter = SyncRecord(
      id: 'row',
      fields: const {'value': 'row:server-authoritative'},
      updatedAt: base.add(const Duration(minutes: 3)),
    );
    final transport = _AppliedFalseTransport(
      collection: collection.name,
      beforePush: remoteBefore,
      afterPush: remoteAfter,
    );

    final report = await SyncEngine.run(
      transport: transport,
      now: base.add(const Duration(minutes: 4)),
      only: {collection.name},
    );

    expect(report.ok, isTrue, reason: report.describe());
    expect(report.uploaded, 0,
        reason: 'applied:false is not a delivered local upload');
    expect(report.applied, 1,
        reason: 'server authoritative row must be applied in the same run');
    expect(transport.fetchCount, 2,
        reason: 'post-rejection payload must come from permission-filtered GET');
    expect(box.get('row'), 'row:server-authoritative');
    expect(SyncJournal.stampOf(collection.name, 'row')?.updatedAt,
        remoteAfter.updatedAt);
  });

  test('post-push local edit is never overwritten by authoritative refetch',
      () async {
    final (collection, box) = await prepare('concurrent');
    final remoteBefore = SyncRecord(
      id: 'row',
      fields: const {'value': 'row:server-old'},
      updatedAt: base.add(const Duration(minutes: 1)),
    );
    final remoteAfter = SyncRecord(
      id: 'row',
      fields: const {'value': 'row:server-authoritative'},
      updatedAt: base.add(const Duration(minutes: 3)),
    );
    final newestLocalStamp = base.add(const Duration(minutes: 4));
    final transport = _AppliedFalseTransport(
      collection: collection.name,
      beforePush: remoteBefore,
      afterPush: remoteAfter,
      onPush: () async {
        await box.put('row', 'row:edited-during-http');
        await SyncJournal.record(
          collection.name,
          'row',
          SyncStamp(newestLocalStamp),
        );
      },
    );

    final report = await SyncEngine.run(
      transport: transport,
      now: base.add(const Duration(minutes: 5)),
      only: {collection.name},
    );

    expect(report.ok, isFalse);
    expect(report.firstFailure?.code, 'LOCAL_CHANGED_DURING_SYNC');
    expect(box.get('row'), 'row:edited-during-http');
    expect(SyncJournal.stampOf(collection.name, 'row')?.updatedAt,
        newestLocalStamp);
  });
}
