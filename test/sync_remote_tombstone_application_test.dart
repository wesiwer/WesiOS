import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_endpoint.dart';
import 'package:wesios/core/sync/sync_engine.dart';
import 'package:wesios/core/sync/sync_journal.dart';
import 'package:wesios/core/sync/sync_merge.dart';
import 'package:wesios/core/sync/sync_transport.dart';

class _TombstoneCollection extends SyncCollection<String> {
  final String suffix;
  final bool archiveInsteadOfDelete;

  _TombstoneCollection(this.suffix, {this.archiveInsteadOfDelete = false});

  @override
  String get name => 'tombstone_probe_$suffix';

  @override
  String get boxName => 'wesios_tombstone_probe_$suffix';

  @override
  String idOf(String value) => value.split(':').first;

  @override
  bool shouldSync(String value) => !value.endsWith(':archived');

  @override
  Map<String, dynamic> encode(String value) => {'value': value};

  @override
  String? decode(Map<String, dynamic> fields) => fields['value'] as String?;

  @override
  Future<void> removeById(String id) async {
    if (!archiveInsteadOfDelete) {
      // Mirrors durable codecs that intentionally refuse a domain delete.
      return;
    }
    await box()?.put(id, '$id:archived');
  }
}

class _RemoteTombstoneTransport implements SyncTransport {
  final String id;
  final DateTime stamp;

  _RemoteTombstoneTransport(this.id, this.stamp);

  @override
  bool get isSignedIn => true;

  @override
  Future<SyncResult<Map<String, SyncRecord>>> fetch(String collection) async =>
      SyncResult.ok({
        id: SyncRecord(id: id, updatedAt: stamp, deleted: true),
      });

  @override
  Future<SyncPushResult> push(
    String collection,
    List<SyncRecord> records,
  ) async =>
      const SyncPushResult();

  @override
  Future<SyncResult<String>> signIn(String login, String password) async =>
      const SyncResult.ok('test');

  @override
  void signOut() {}
}

void main() {
  late Directory dir;
  late List<SyncCollection<dynamic>> originalCollections;
  final base = DateTime.utc(2026, 8, 18, 11);

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_tombstone_apply_');
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

  Future<_TombstoneCollection> prepareCollection({
    required String suffix,
    required bool archiveInsteadOfDelete,
  }) async {
    originalCollections = List<SyncCollection<dynamic>>.from(SyncCodec.collections);
    await SyncEngine.reset();
    await Hive.box<dynamic>('wesios_settings').clear();

    final collection = _TombstoneCollection(
      suffix,
      archiveInsteadOfDelete: archiveInsteadOfDelete,
    );
    SyncCodec.collections
      ..clear()
      ..add(collection);

    final box = Hive.isBoxOpen(collection.boxName)
        ? Hive.box<String>(collection.boxName)
        : await Hive.openBox<String>(collection.boxName);
    await box.clear();
    await SyncJournal.open();
    await Hive.box<dynamic>(SyncJournal.boxName).clear();
    await SyncEndpoint.markRun(base.subtract(const Duration(days: 1)));
    await SyncEngine.prepare(now: base);
    return collection;
  }

  test('no-op domain delete is not reported as an applied remote tombstone',
      () async {
    final collection = await prepareCollection(
      suffix: 'durable',
      archiveInsteadOfDelete: false,
    );
    final box = Hive.box<String>(collection.boxName);
    await box.put('row', 'row:active');
    await Future<void>.delayed(Duration.zero);
    await SyncJournal.record(
      collection.name,
      'row',
      SyncStamp(base.add(const Duration(minutes: 1))),
    );

    final remoteStamp = base.add(const Duration(minutes: 2));
    final report = await SyncEngine.run(
      transport: _RemoteTombstoneTransport('row', remoteStamp),
      now: base.add(const Duration(minutes: 3)),
      only: {collection.name},
    );

    expect(report.ok, isFalse);
    expect(report.firstFailure?.code, 'REMOTE_APPLY_INCOMPLETE');
    expect(box.get('row'), 'row:active');

    final journal = SyncJournal.stampOf(collection.name, 'row');
    expect(journal, isNotNull);
    expect(journal!.deleted, isFalse,
        reason:
            'journal must never claim deletion when the row remains sync-visible');
    expect(journal.updatedAt.millisecondsSinceEpoch, 0,
        reason:
            'failed remote apply is demoted so the authoritative row is retried');
  });

  test('archiving that removes the row from sync projection counts as deletion',
      () async {
    final collection = await prepareCollection(
      suffix: 'archive',
      archiveInsteadOfDelete: true,
    );
    final box = Hive.box<String>(collection.boxName);
    await box.put('row', 'row:active');
    await Future<void>.delayed(Duration.zero);
    await SyncJournal.record(
      collection.name,
      'row',
      SyncStamp(base.add(const Duration(minutes: 1))),
    );

    final remoteStamp = base.add(const Duration(minutes: 2));
    final report = await SyncEngine.run(
      transport: _RemoteTombstoneTransport('row', remoteStamp),
      now: base.add(const Duration(minutes: 3)),
      only: {collection.name},
    );

    expect(report.ok, isTrue, reason: report.describe());
    expect(box.get('row'), 'row:archived',
        reason: 'local history may remain if shouldSync=false');
    expect(collection.local().containsKey('row'), isFalse,
        reason: 'archived representation must be gone from sync projection');

    final journal = SyncJournal.stampOf(collection.name, 'row');
    expect(journal?.deleted, isTrue);
    expect(journal?.updatedAt, remoteStamp);
  });
}
