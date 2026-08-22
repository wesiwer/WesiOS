import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_engine.dart';
import 'package:wesios/core/sync/sync_journal.dart';
import 'package:wesios/core/sync/sync_merge.dart';
import 'package:wesios/core/sync/sync_transport.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';

class _Transport implements SyncTransport {
  final Map<String, SyncRecord> rows;
  _Transport(this.rows);
  @override
  bool get isSignedIn => true;
  @override
  Future<SyncResult<String>> signIn(String login, String password) async =>
      const SyncResult.ok('ok');
  @override
  void signOut() {}
  @override
  Future<SyncResult<Map<String, SyncRecord>>> fetch(String collection) async =>
      SyncResult.ok(
        collection == 'organizations'
            ? Map<String, SyncRecord>.from(rows)
            : <String, SyncRecord>{},
      );
  @override
  Future<SyncPushResult> push(
    String collection,
    List<SyncRecord> records,
  ) async =>
      throw StateError('remote-authoritative download must never upload');
}

Map<String, dynamic> _payload(String id, String name, String? parentId) =>
    <String, dynamic>{
      'id': id,
      'name': name,
      'parentId': parentId,
      'isRoot': id == OrganizationModel.rootId,
      'baseCurrency': 'RUB',
      'status': 'active',
      'createdAt': '2026-08-17T13:19:24.672Z',
      'updatedAt': '2026-08-17T13:19:24.672Z',
      'createdBy': 'server',
      'code': null,
      'description': null,
      'colorValue': null,
      'sortOrder': 0,
    };

void main() {
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios_manual_org_');
    Hive.init(temp.path);
    if (!Hive.isAdapterRegistered(80))
      Hive.registerAdapter(OrganizationStatusAdapter());
    if (!Hive.isAdapterRegistered(81))
      Hive.registerAdapter(OrganizationModelAdapter());
  });
  setUp(() async {
    await SyncEngine.reset();
    final settings = Hive.isBoxOpen('wesios_settings')
        ? Hive.box<dynamic>('wesios_settings')
        : await Hive.openBox<dynamic>('wesios_settings');
    await settings.clear();
    final box = Hive.isBoxOpen(OrganizationService.boxName)
        ? Hive.box<OrganizationModel>(OrganizationService.boxName)
        : await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await box.clear();
  });
  tearDownAll(() async {
    await SyncEngine.reset();
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('manual remote-authoritative repair works with stale stamps', () async {
    final box = Hive.box<OrganizationModel>(OrganizationService.boxName);
    final old = DateTime.utc(2026, 8, 1);
    for (final row in <OrganizationModel>[
      OrganizationModel(
        id: OrganizationModel.rootId,
        name: 'bad root',
        parentId: 'legacy',
        isRoot: false,
        baseCurrency: 'RUB',
        createdAt: old,
        updatedAt: old,
        createdBy: 'legacy',
      ),
      OrganizationModel(
        id: OrganizationModel.wesiBeatsId,
        name: 'Wesi Beats',
        parentId: OrganizationModel.rootId,
        isRoot: false,
        baseCurrency: 'RUB',
        createdAt: old,
        updatedAt: old,
        createdBy: 'legacy',
      ),
      OrganizationModel(
        id: 'org_it',
        name: 'IT',
        parentId: OrganizationModel.rootId,
        isRoot: false,
        baseCurrency: 'RUB',
        createdAt: old,
        updatedAt: old,
        createdBy: 'legacy',
      ),
    ]) {
      await box.put(row.id, row);
    }
    expect(OrganizationsSync().local(), isEmpty);
    await SyncJournal.open();
    final stale = SyncStamp(DateTime.utc(2026, 8, 20, 12));
    for (final id in <String>[
      OrganizationModel.rootId,
      OrganizationModel.wesiBeatsId,
      'org_it',
    ]) {
      await SyncJournal.record('organizations', id, stale);
    }
    final at = DateTime.utc(2026, 8, 17, 13, 19, 24, 672);
    final transport = _Transport(<String, SyncRecord>{
      OrganizationModel.rootId: SyncRecord(
        id: OrganizationModel.rootId,
        updatedAt: at,
        fields: _payload(OrganizationModel.rootId, 'Wesi Inc', null),
      ),
      OrganizationModel.wesiBeatsId: SyncRecord(
        id: OrganizationModel.wesiBeatsId,
        updatedAt: at,
        fields: _payload(
          OrganizationModel.wesiBeatsId,
          'Wesi Beats',
          OrganizationModel.rootId,
        ),
      ),
      'org_it': SyncRecord(
        id: 'org_it',
        updatedAt: at,
        fields: _payload('org_it', 'IT', OrganizationModel.rootId),
      ),
    });
    final report = await SyncEngine.run(
      transport: transport,
      now: DateTime.utc(2026, 8, 22),
      only: const <String>{'organizations'},
      remoteAuthoritative: true,
    );
    expect(report.ok, isTrue, reason: report.describe());
    expect(report.uploaded, 0);
    expect(report.applied, 3);
    final root = box.get(OrganizationModel.rootId)!;
    expect(root.isRoot, isTrue);
    expect(root.parentId, isNull);
    expect(OrganizationsSync().local().length, 3);
  });
}
