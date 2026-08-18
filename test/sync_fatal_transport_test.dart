import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_engine.dart';
import 'package:wesios/core/sync/sync_merge.dart';
import 'package:wesios/core/sync/sync_transport.dart';

class _FatalProbeCollection extends SyncCollection<String> {
  final String suffix;

  _FatalProbeCollection(this.suffix);

  @override
  String get name => 'fatal_probe_$suffix';

  @override
  String get boxName => 'wesios_fatal_probe_$suffix';

  @override
  String idOf(String value) => value;

  @override
  Map<String, dynamic> encode(String value) => {'value': value};

  @override
  String? decode(Map<String, dynamic> fields) => fields['value'] as String?;
}

class _FailureByCollectionTransport implements SyncTransport {
  final Map<String, SyncFailure> failures;
  final List<String> fetches = <String>[];

  _FailureByCollectionTransport(this.failures);

  @override
  bool get isSignedIn => true;

  @override
  Future<SyncResult<Map<String, SyncRecord>>> fetch(String collection) async {
    fetches.add(collection);
    final failure = failures[collection];
    if (failure != null) return SyncResult.fail(failure);
    return const SyncResult.ok(<String, SyncRecord>{});
  }

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
  late _FatalProbeCollection first;
  late _FatalProbeCollection second;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_fatal_transport_');
    Hive.init(dir.path);
    await Hive.openBox<dynamic>('wesios_settings');
  });

  setUp(() async {
    originalCollections = List<SyncCollection<dynamic>>.from(SyncCodec.collections);
    await SyncEngine.reset();
    first = _FatalProbeCollection('first');
    second = _FatalProbeCollection('second');
    SyncCodec.collections
      ..clear()
      ..addAll(<SyncCollection<dynamic>>[first, second]);
    await Hive.openBox<String>(first.boxName);
    await Hive.openBox<String>(second.boxName);
    await Hive.box<String>(first.boxName).clear();
    await Hive.box<String>(second.boxName).clear();
  });

  tearDown(() async {
    await SyncEngine.reset();
    SyncCodec.collections
      ..clear()
      ..addAll(originalCollections);
    if (Hive.isBoxOpen(first.boxName)) await Hive.box<String>(first.boxName).close();
    if (Hive.isBoxOpen(second.boxName)) await Hive.box<String>(second.boxName).close();
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('network failure aborts the pass after the first failed fetch', () async {
    final transport = _FailureByCollectionTransport({
      first.name: const SyncFailure('NETWORK', 'offline'),
      second.name: const SyncFailure('NETWORK', 'offline'),
    });

    final report = await SyncEngine.run(
      transport: transport,
      now: DateTime.utc(2026, 8, 18, 9),
    );

    expect(report.ok, isFalse);
    expect(report.firstFailure?.code, 'NETWORK');
    expect(transport.fetches, <String>[first.name],
        reason: 'one offline fetch must not be multiplied by every collection');
  });

  test('collection-specific HTTP error does not block the next collection',
      () async {
    final transport = _FailureByCollectionTransport({
      first.name: const SyncFailure('HTTP_400', 'bad row contract'),
    });

    final report = await SyncEngine.run(
      transport: transport,
      now: DateTime.utc(2026, 8, 18, 10),
    );

    expect(report.ok, isFalse);
    expect(report.firstFailure?.code, 'HTTP_400');
    expect(transport.fetches, <String>[first.name, second.name],
        reason: 'a collection failure must not hide healthy collections behind it');
  });
}
