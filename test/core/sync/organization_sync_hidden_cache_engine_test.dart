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

class _MemoryTransport implements SyncTransport {
  _MemoryTransport(this.organizations);

  final Map<String, SyncRecord> organizations;

  @override
  bool get isSignedIn => true;

  @override
  Future<SyncResult<String>> signIn(String login, String password) async =>
      const SyncResult.ok('test-token');

  @override
  void signOut() {}

  @override
  Future<SyncResult<Map<String, SyncRecord>>> fetch(String collection) async =>
      SyncResult.ok(
        collection == 'organizations'
            ? Map<String, SyncRecord>.from(organizations)
            : <String, SyncRecord>{},
      );

  @override
  Future<SyncPushResult> push(
    String collection,
    List<SyncRecord> records,
  ) async => const SyncPushResult();
}

Map<String, dynamic> _payload({
  required String id,
  required String name,
  String? parentId,
  bool isRoot = false,
}) => <String, dynamic>{
  'id': id,
  'name': name,
  'parentId': parentId,
  'isRoot': isRoot,
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
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('wesios_org_engine_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(80)) {
      Hive.registerAdapter(OrganizationStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(81)) {
      Hive.registerAdapter(OrganizationModelAdapter());
    }
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
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'full engine repairs hidden legacy tree without false concurrent edit',
    () async {
      final box = Hive.box<OrganizationModel>(OrganizationService.boxName);
      final oldAt = DateTime.utc(2026, 8, 1);

      await box.put(
        OrganizationModel.rootId,
        OrganizationModel(
          id: OrganizationModel.rootId,
          name: 'Wesi Inc old cache',
          parentId: 'legacy_parent',
          isRoot: false,
          baseCurrency: 'RUB',
          createdAt: oldAt,
          updatedAt: oldAt,
          createdBy: 'legacy-cache',
        ),
      );
      await box.put(
        OrganizationModel.wesiBeatsId,
        OrganizationModel(
          id: OrganizationModel.wesiBeatsId,
          name: 'Wesi Beats',
          parentId: OrganizationModel.rootId,
          isRoot: false,
          baseCurrency: 'RUB',
          createdAt: oldAt,
          updatedAt: oldAt,
          createdBy: 'legacy-cache',
        ),
      );
      await box.put(
        'org_it',
        OrganizationModel(
          id: 'org_it',
          name: "Wesi Inc IT Studio's",
          parentId: OrganizationModel.rootId,
          isRoot: false,
          baseCurrency: 'RUB',
          createdAt: oldAt,
          updatedAt: oldAt,
          createdBy: 'legacy-cache',
        ),
      );

      expect(OrganizationsSync().local(), isEmpty);

      await SyncJournal.open();
      final staleStamp = SyncStamp(DateTime.utc(2026, 8, 20, 12));
      for (final id in <String>[
        OrganizationModel.rootId,
        OrganizationModel.wesiBeatsId,
        'org_it',
      ]) {
        await SyncJournal.record('organizations', id, staleStamp);
      }

      final serverAt = DateTime.utc(2026, 8, 17, 13, 19, 24, 672);
      final transport = _MemoryTransport(<String, SyncRecord>{
        OrganizationModel.wesiBeatsId: SyncRecord(
          id: OrganizationModel.wesiBeatsId,
          updatedAt: serverAt,
          fields: _payload(
            id: OrganizationModel.wesiBeatsId,
            name: 'Wesi Beats',
            parentId: OrganizationModel.rootId,
          ),
        ),
        OrganizationModel.rootId: SyncRecord(
          id: OrganizationModel.rootId,
          updatedAt: serverAt,
          fields: _payload(
            id: OrganizationModel.rootId,
            name: 'Wesi Inc',
            parentId: 'legacy_parent',
            isRoot: false,
          ),
        ),
        'org_it': SyncRecord(
          id: 'org_it',
          updatedAt: serverAt,
          fields: _payload(
            id: 'org_it',
            name: "Wesi Inc IT Studio's",
            parentId: OrganizationModel.rootId,
          ),
        ),
      });

      final report = await SyncEngine.run(
        transport: transport,
        now: DateTime.utc(2026, 8, 21, 13),
        only: const <String>{'organizations'},
      );

      expect(report.ok, isTrue, reason: report.describe());
      expect(report.applied, 3);

      final root = box.get(OrganizationModel.rootId)!;
      expect(root.isRoot, isTrue);
      expect(root.parentId, isNull);
      expect(root.name, 'Wesi Inc');
      expect(
        OrganizationsSync().local().keys,
        containsAll(<String>[
          OrganizationModel.rootId,
          OrganizationModel.wesiBeatsId,
          'org_it',
        ]),
      );
    },
  );
}
