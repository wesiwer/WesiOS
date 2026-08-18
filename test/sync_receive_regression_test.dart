import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_engine.dart';

import 'fake_sync_transport.dart';

class _RejectingReceiveCollection extends SyncCollection<dynamic> {
  @override
  String get name => 'receive_probe';

  @override
  String get boxName => 'wesios_receive_probe';

  @override
  String idOf(dynamic value) => value is Map ? '${value['id'] ?? ''}' : '';

  @override
  Map<String, dynamic> encode(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  @override
  dynamic decode(Map<String, dynamic> fields) => fields;

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async => false;
}

class _DependencyReceiveCollection extends SyncCollection<dynamic> {
  final Set<String> accepted = <String>{};

  @override
  String get name => 'dependency_probe';

  @override
  String get boxName => 'wesios_dependency_probe';

  @override
  String idOf(dynamic value) => value is Map ? '${value['id'] ?? ''}' : '';

  @override
  Map<String, dynamic> encode(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  @override
  dynamic decode(Map<String, dynamic> fields) => fields;

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final id = '${fields['id'] ?? ''}';
    final parent = '${fields['parent'] ?? ''}';
    if (id.isEmpty) return false;
    if (parent.isNotEmpty && !accepted.contains(parent)) return false;
    accepted.add(id);
    return true;
  }
}

void main() {
  final base = DateTime.utc(2026, 8, 17, 12);
  late Directory dir;
  late _RejectingReceiveCollection probe;
  late _DependencyReceiveCollection dependencyProbe;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_receive_regression');
    Hive.init(dir.path);
    await Hive.openBox<dynamic>('wesios_settings');
    probe = _RejectingReceiveCollection();
    dependencyProbe = _DependencyReceiveCollection();
    SyncCodec.collections.add(probe);
    SyncCodec.collections.add(dependencyProbe);
    await SyncEngine.prepare(now: base);
  });

  tearDownAll(() async {
    SyncCodec.collections.remove(probe);
    SyncCodec.collections.remove(dependencyProbe);
    await SyncEngine.reset();
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('fetched but unapplied remote row makes the pass incomplete', () async {
    final transport = FakeSyncTransport()
      ..seed(
        probe.name,
        'remote-1',
        {'id': 'remote-1', 'value': 'from-server'},
        base.add(const Duration(minutes: 1)),
      );

    final report = await SyncEngine.run(
      transport: transport,
      now: base.add(const Duration(minutes: 2)),
      only: {probe.name},
    );

    expect(report.ok, isFalse);
    expect(report.firstFailure?.code, 'REMOTE_APPLY_INCOMPLETE');
    expect(report.firstFailure?.message, contains('receive_probe:remote-1'));
    expect(report.applied, 0);
  });

  test('dependency-blocked rows are retried within the same collection pass',
      () async {
    dependencyProbe.accepted.clear();
    final transport = FakeSyncTransport()
      ..seed(
        dependencyProbe.name,
        'child',
        {'id': 'child', 'parent': 'parent'},
        base.add(const Duration(minutes: 2)),
      )
      ..seed(
        dependencyProbe.name,
        'parent',
        {'id': 'parent'},
        base.add(const Duration(minutes: 1)),
      );

    final report = await SyncEngine.run(
      transport: transport,
      now: base.add(const Duration(minutes: 3)),
      only: {dependencyProbe.name},
    );

    expect(report.ok, isTrue, reason: report.describe());
    expect(dependencyProbe.accepted, containsAll(<String>{'parent', 'child'}));
    expect(report.applied, 2);
  });

  test('fresh interactive login serializes rebind, pull and receive polling', () {
    final source =
        File('lib/features/auth/login_screen.dart').readAsStringSync();
    expect(
      source,
      contains('await SyncFeatureExtensions.rebindCurrentAccountAndSync();'),
    );
    expect(source, isNot(contains('await SyncEngine.runOnLaunch();')));
    expect(source, isNot(contains('if (employee.isOwner) {')));
  });

  test('remote watermark is accepted only after the matching pull succeeds', () {
    final source = File('lib/core/sync/sync_auto.dart').readAsStringSync();
    expect(source, isNot(contains('SyncEngine.lastReport.value?.ok == true')));
    expect(source, contains('final observedRevision = result.value!;'));
    expect(
      source,
      contains('final report = await _runAuto(generation: generation);'),
    );
    expect(source, contains('_acceptObservedRevision(observedRevision);'));

    final observed = source.indexOf('final observedRevision = result.value!;');
    final run = source.indexOf(
      'final report = await _runAuto(generation: generation);',
      observed,
    );
    final accepted = source.indexOf(
      '_acceptObservedRevision(observedRevision);',
      run,
    );
    expect(observed, greaterThanOrEqualTo(0));
    expect(run, greaterThan(observed));
    expect(accepted, greaterThan(run));
  });

  test('remote Hive expectations use TTL instead of end-of-run clearing', () {
    final source = File('lib/core/sync/sync_journal.dart').readAsStringSync();
    expect(source, contains('_expectationLifetime = Duration(seconds: 5)'));
    expect(source, contains('age <= _expectationLifetime'));
    expect(source, contains('static void pruneExpectations()'));
  });
}
