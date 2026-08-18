import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_endpoint.dart';
import 'package:wesios/core/sync/sync_engine.dart';
import 'package:wesios/core/sync/sync_journal.dart';
import 'package:wesios/core/sync/sync_merge.dart';
import 'package:wesios/core/sync/sync_transport.dart';

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

class _NoDomainDeletePolicyCollection extends _PolicyCollection {
  @override
  String get name => 'policy_cache_no_domain_delete_probe';

  @override
  Future<void> removeById(String id) async {
    // Mirrors codecs such as OrganizationsSync where a normal synced business
    // tombstone is intentionally not allowed to delete the local entity.
  }
}

class _PermissionRevokedBetweenFetchAndPush implements SyncTransport {
  final SyncRecord initiallyVisible;
  int fetchCount = 0;

  _PermissionRevokedBetweenFetchAndPush(this.initiallyVisible);

  @override
  bool get isSignedIn => true;

  @override
  Future<SyncResult<Map<String, SyncRecord>>> fetch(String collection) async {
    fetchCount++;
    if (fetchCount == 1) {
      return SyncResult.ok({'row': initiallyVisible});
    }
    return const SyncResult.ok(<String, SyncRecord>{});
  }

  @override
  Future<SyncPushResult> push(
    String collection,
    List<SyncRecord> records,
  ) async {
    return SyncPushResult(
      forbiddenIds: records.map((r) => r.id).toList(),
    );
  }

  @override
  Future<SyncResult<String>> signIn(String login, String password) async =>
      const SyncResult.ok('test');

  @override
  void signOut() {}
}

class _PermissionRefreshFails implements SyncTransport {
  final SyncRecord initiallyVisible;
  int fetchCount = 0;

  _PermissionRefreshFails(this.initiallyVisible);

  @override
  bool get isSignedIn => true;

  @override
  Future<SyncResult<Map<String, SyncRecord>>> fetch(String collection) async {
    fetchCount++;
    if (fetchCount == 1) {
      return SyncResult.ok({'row': initiallyVisible});
    }
    return const SyncResult.fail(
      SyncFailure('NETWORK', 'permission refresh unavailable'),
    );
  }

  @override
  Future<SyncPushResult> push(
    String collection,
    List<SyncRecord> records,
  ) async {
    return SyncPushResult(
      forbiddenIds: records.map((r) => r.id).toList(),
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

    // Policy eviction writes an epoch tombstone only as an in-pass ordering
    // coordinate. The normal 180-day tombstone pruning at the end of the run
    // removes it immediately because epoch is intentionally ancient. Either
    // representation is safe: the sensitive row is gone and a future restored
    // server row cannot lose to a fresh local permission tombstone.
    final stamp = SyncJournal.stampOf(collection.name, 'secret');
    if (stamp != null) {
      expect(stamp.deleted, isTrue);
      expect(stamp.updatedAt.millisecondsSinceEpoch, 0);
    }
  });

  test('policy eviction bypasses domain removeById no-op', () async {
    final noDelete = _NoDomainDeletePolicyCollection();
    await SyncEngine.reset();
    SyncCodec.collections
      ..clear()
      ..add(noDelete);
    await SyncEngine.prepare(now: base);

    final box = Hive.box<String>(_PolicyCollection.testBox);
    await box.put('org-like', 'org-like:cached-secret');
    await Future<void>.delayed(Duration.zero);

    final transport = FakeSyncTransport()..forbiddenIds.add('org-like');
    final report = await SyncEngine.run(
      transport: transport,
      now: base.add(const Duration(minutes: 1)),
      only: {noDelete.name},
    );

    expect(report.ok, isTrue, reason: report.describe());
    expect(box.containsKey('org-like'), isFalse,
        reason:
            'permission cache eviction must not reuse conservative business deletion semantics');
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

  test('permission revoked between fetch and forbidden push purges stale cache',
      () async {
    final box = Hive.box<String>(_PolicyCollection.testBox);
    await box.put('row', 'row:local-edit');
    await Future<void>.delayed(Duration.zero);
    final localStamp = base.add(const Duration(minutes: 10));
    await SyncJournal.record(collection.name, 'row', SyncStamp(localStamp));

    final staleVisibleRemote = SyncRecord(
      id: 'row',
      updatedAt: base.add(const Duration(minutes: 2)),
      fields: const {'value': 'row:old-visible-server'},
    );
    final transport =
        _PermissionRevokedBetweenFetchAndPush(staleVisibleRemote);

    final report = await SyncEngine.run(
      transport: transport,
      now: base.add(const Duration(minutes: 11)),
      only: {collection.name},
    );

    expect(report.ok, isTrue, reason: report.describe());
    expect(transport.fetchCount, 2,
        reason: '403 must force a fresh permission-filtered snapshot');
    expect(box.containsKey('row'), isFalse,
        reason:
            'the stale pre-push fetch must never preserve data after read access was revoked');
  });

  test('failed post-403 permission refresh fails closed and purges denied cache',
      () async {
    final box = Hive.box<String>(_PolicyCollection.testBox);
    await box.put('row', 'row:local-edit');
    await Future<void>.delayed(Duration.zero);
    await SyncJournal.record(
      collection.name,
      'row',
      SyncStamp(base.add(const Duration(minutes: 10))),
    );

    final transport = _PermissionRefreshFails(
      SyncRecord(
        id: 'row',
        updatedAt: base.add(const Duration(minutes: 2)),
        fields: const {'value': 'row:old-visible-server'},
      ),
    );

    final report = await SyncEngine.run(
      transport: transport,
      now: base.add(const Duration(minutes: 11)),
      only: {collection.name},
    );

    expect(report.ok, isFalse);
    expect(report.firstFailure?.code, 'POLICY_REFRESH_FAILED');
    expect(transport.fetchCount, 2);
    expect(box.containsKey('row'), isFalse,
        reason:
            'after an explicit server denial, an unverifiable sensitive cache must not remain local');
  });
}
