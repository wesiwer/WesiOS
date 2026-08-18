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

class _DelayedPrepareCollection extends SyncCollection<String> {
  static const String probeBoxName = 'wesios_sync_prepare_probe';

  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  int ensureCalls = 0;

  @override
  String get name => 'prepare_probe';

  @override
  String get boxName => probeBoxName;

  @override
  String idOf(String value) => value;

  @override
  Map<String, dynamic> encode(String value) => {'value': value};

  @override
  String? decode(Map<String, dynamic> fields) => fields['value'] as String?;

  @override
  Future<Box<String>> ensureBox() async {
    ensureCalls++;
    if (!started.isCompleted) started.complete();
    await release.future;
    return Hive.isBoxOpen(boxName)
        ? Hive.box<String>(boxName)
        : Hive.openBox<String>(boxName);
  }
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
    if (Hive.isBoxOpen(_DelayedPrepareCollection.probeBoxName)) {
      await Hive.box<String>(_DelayedPrepareCollection.probeBoxName).close();
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

  test('concurrent prepare calls share one box preparation pass', () async {
    await SyncEngine.reset();
    final probe = _DelayedPrepareCollection();
    SyncCodec.collections
      ..clear()
      ..add(probe);

    final first = SyncEngine.prepare(now: DateTime.utc(2026, 8, 18, 3));
    await probe.started.future;
    final second = SyncEngine.prepare(now: DateTime.utc(2026, 8, 18, 3));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(probe.ensureCalls, 1,
        reason: 'prepare must be single-flight for one sync lifecycle');

    probe.release.complete();
    await Future.wait<void>([first, second]);
    expect(probe.ensureCalls, 1);
  });

  test('reset waits an in-flight prepare and next lifecycle prepares again',
      () async {
    await SyncEngine.reset();
    final probe = _DelayedPrepareCollection();
    SyncCodec.collections
      ..clear()
      ..add(probe);

    final preparing = SyncEngine.prepare(now: DateTime.utc(2026, 8, 18, 4));
    await probe.started.future;

    var resetFinished = false;
    final resetting = SyncEngine.reset().then((_) => resetFinished = true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(resetFinished, isFalse,
        reason: 'reset must not detach while old prepare still owns the boxes');

    probe.release.complete();
    await preparing;
    await resetting;
    expect(resetFinished, isTrue);

    await SyncEngine.prepare(now: DateTime.utc(2026, 8, 18, 5));
    expect(probe.ensureCalls, 2,
        reason: 'a new lifecycle must not inherit old journal readiness');
  });

  test('new collection on an established account gets conservative epoch stamps',
      () async {
    await SyncEngine.reset();
    final settings = Hive.box<dynamic>('wesios_settings');
    await settings.put('sync_last_run', DateTime.utc(2026, 8, 1).toIso8601String());
    await settings.put('sync_seeded_at', DateTime.utc(2026, 8, 1).toIso8601String());

    final collection = _StringCollection();
    SyncCodec.collections
      ..clear()
      ..add(collection);
    final box = Hive.box<String>(collection.boxName);
    await box.clear();
    await box.put('legacy', 'legacy:local-only-before-sync-support');
    await SyncJournal.open();
    await Hive.box<dynamic>(SyncJournal.boxName).clear();

    await SyncEngine.prepare(now: DateTime.utc(2026, 8, 18, 6));

    final stamp = SyncJournal.stampOf(collection.name, 'legacy');
    expect(stamp, isNotNull);
    expect(stamp!.updatedAt.millisecondsSinceEpoch, 0,
        reason: 'unknown pre-sync freshness must never masquerade as now');
  });
}
