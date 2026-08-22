import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_merge.dart';
import 'package:wesios/core/sync/sync_recovery.dart';
import 'package:wesios/core/sync/sync_transport.dart';

class _JsonCollection extends SyncCollection<String> {
  @override
  final String name;
  @override
  final String boxName;

  _JsonCollection(this.name, this.boxName);

  Map<String, dynamic> _json(String raw) =>
      Map<String, dynamic>.from(jsonDecode(raw) as Map);

  @override
  String idOf(String value) => '${_json(value)['id']}';

  @override
  Map<String, dynamic> encode(String value) => _json(value);

  @override
  String? decode(Map<String, dynamic> fields) {
    final id = fields['id'];
    if (id is! String || id.isEmpty) return null;
    return jsonEncode(fields);
  }
}

class _MemoryTransport implements SyncTransport {
  final Map<String, Map<String, SyncRecord>> remote = {};
  bool failFetchAfterPush = false;
  bool pushed = false;
  Future<void> Function(String collection, List<SyncRecord> records)? onPush;

  @override
  bool get isSignedIn => true;

  @override
  Future<SyncResult<Map<String, SyncRecord>>> fetch(String collection) async {
    if (failFetchAfterPush && pushed) {
      return const SyncResult.fail(SyncFailure.offline);
    }
    return SyncResult.ok(
      Map<String, SyncRecord>.from(
        remote[collection] ?? const <String, SyncRecord>{},
      ),
    );
  }

  @override
  Future<SyncPushResult> push(
    String collection,
    List<SyncRecord> records,
  ) async {
    pushed = true;
    await onPush?.call(collection, records);
    final target = remote.putIfAbsent(collection, () => <String, SyncRecord>{});
    final delivered = <String>[];
    final authoritative = <String>[];
    final accepted = <String, DateTime>{};
    final authoritativeStamps = <String, DateTime>{};

    for (final incoming in records) {
      final existing = target[incoming.id];
      if (existing != null &&
          !incoming.updatedAt.toUtc().isAfter(existing.updatedAt.toUtc())) {
        authoritative.add(incoming.id);
        authoritativeStamps[incoming.id] = existing.updatedAt;
        continue;
      }
      target[incoming.id] = incoming;
      delivered.add(incoming.id);
      accepted[incoming.id] = incoming.updatedAt;
    }

    return SyncPushResult(
      deliveredIds: delivered,
      acceptedStamps: accepted,
      authoritativeIds: authoritative,
      authoritativeStamps: authoritativeStamps,
    );
  }

  @override
  Future<SyncResult<String>> signIn(String login, String password) async =>
      const SyncResult.ok('ok');

  @override
  void signOut() {}
}

void main() {
  late Directory tempDir;
  late _JsonCollection collection;
  late Box<String> business;

  String row(String id, String value) =>
      jsonEncode(<String, dynamic>{'id': id, 'value': value});

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('wesios_sync_recovery_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    if (!Hive.isBoxOpen('wesios_settings')) {
      await Hive.openBox<dynamic>('wesios_settings');
    } else {
      await Hive.box<dynamic>('wesios_settings').clear();
    }
    collection = _JsonCollection('tasks', 'test_recovery_tasks');
    business = await collection.ensureBox();
    await business.clear();
    final backups = Hive.isBoxOpen(SyncRecovery.backupBoxName)
        ? Hive.box<dynamic>(SyncRecovery.backupBoxName)
        : await Hive.openBox<dynamic>(SyncRecovery.backupBoxName);
    await backups.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'organization verification accepts server canonical transport shape',
    () {
      final collection = OrganizationsSync();
      final local = <String, dynamic>{
        'id': 'org_1786636872294887',
        'name': 'Local organization',
        'parentId': 'org_wesi_inc',
        'isRoot': false,
        'baseCurrency': '',
        'status': 'active',
        'createdAt': '2026-08-17T13:19:24.672Z',
        'updatedAt': '2026-08-17T13:19:24.672Z',
        'createdBy': '',
        'code': null,
        'description': null,
        'colorValue': null,
        'sortOrder': 0,
      };
      final remote = <String, dynamic>{
        ...local,
        'baseCurrency': 'RUB',
        'createdBy': 'sync-server',
        'created': '2026-08-17T13:19:24.672Z',
        'updated': '2026-08-17T13:19:24.672Z',
        'archived': false,
      };
      expect(
        SyncRecovery.samePayloadForVerification(collection, remote, local),
        isTrue,
      );
      remote['name'] = 'Different business name';
      expect(
        SyncRecovery.samePayloadForVerification(collection, remote, local),
        isFalse,
      );
    },
  );

  test('empty server receives snapshot without changing local bytes', () async {
    await business.put('a', row('a', 'phone-a'));
    await business.put('b', row('b', 'phone-b'));
    final before = Map<dynamic, String>.from(business.toMap());
    final transport = _MemoryTransport();

    final report = await SyncRecovery.run(
      transport: transport,
      collections: <SyncCollection<dynamic>>[collection],
      requireOwner: false,
      manageSafety: false,
    );

    expect(report.ok, isTrue);
    expect(report.local, 2);
    expect(report.verified, 2);
    expect(Map<dynamic, String>.from(business.toMap()), before);
    expect(transport.remote['tasks']!['a']!.fields['value'], 'phone-a');
    expect(transport.remote['tasks']!['b']!.fields['value'], 'phone-b');
    final backups = Hive.box<dynamic>(SyncRecovery.backupBoxName);
    expect(
      backups.keys.where((key) => '$key'.startsWith('manifest::')).length,
      1,
    );
  });

  test('older conflicting server row is replaced by phone snapshot', () async {
    await business.put('a', row('a', 'phone-authoritative'));
    final before = Map<dynamic, String>.from(business.toMap());
    final transport = _MemoryTransport();
    transport.remote['tasks'] = <String, SyncRecord>{
      'a': SyncRecord(
        id: 'a',
        fields: const <String, dynamic>{'id': 'a', 'value': 'server-old'},
        updatedAt: DateTime.utc(2020, 1, 1),
      ),
    };

    final report = await SyncRecovery.run(
      transport: transport,
      collections: <SyncCollection<dynamic>>[collection],
      requireOwner: false,
      manageSafety: false,
    );

    expect(report.ok, isTrue);
    expect(
      transport.remote['tasks']!['a']!.fields['value'],
      'phone-authoritative',
    );
    expect(Map<dynamic, String>.from(business.toMap()), before);
  });

  test('network loss after upload never rolls local data back', () async {
    await business.put('a', row('a', 'must-survive'));
    final before = Map<dynamic, String>.from(business.toMap());
    final transport = _MemoryTransport()..failFetchAfterPush = true;

    final report = await SyncRecovery.run(
      transport: transport,
      collections: <SyncCollection<dynamic>>[collection],
      requireOwner: false,
      manageSafety: false,
    );

    expect(report.ok, isFalse);
    expect(report.firstFailure?.code, 'NETWORK');
    expect(Map<dynamic, String>.from(business.toMap()), before);
  });

  test(
    'edit made during recovery survives and forces a new recovery pass',
    () async {
      await business.put('a', row('a', 'snapshot-value'));
      final transport = _MemoryTransport();
      transport.onPush = (_, __) async {
        await business.put('a', row('a', 'newer-local-edit'));
      };

      final report = await SyncRecovery.run(
        transport: transport,
        collections: <SyncCollection<dynamic>>[collection],
        requireOwner: false,
        manageSafety: false,
      );

      expect(report.ok, isFalse);
      expect(report.firstFailure?.code, 'LOCAL_CHANGED_DURING_RECOVERY');
      expect(jsonDecode(business.get('a')!)['value'], 'newer-local-edit');
      expect(
        transport.remote['tasks']!['a']!.fields['value'],
        'snapshot-value',
      );
    },
  );
}
