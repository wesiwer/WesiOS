import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';

void main() {
  late Directory tempDir;
  late OrganizationsSync sync;

  Map<String, dynamic> payload({
    required String id,
    required String name,
    String? parentId,
    bool isRoot = false,
    bool archived = false,
  }) => <String, dynamic>{
    'id': id,
    'name': name,
    'parentId': parentId,
    'isRoot': isRoot,
    'baseCurrency': 'RUB',
    'status': archived ? 'archived' : 'active',
    'createdAt': '2026-08-17T13:19:24.672',
    'updatedAt': '2026-08-17T13:19:24.672',
    'createdBy': 'sync-test',
    'code': null,
    'description': null,
    'colorValue': null,
    'sortOrder': 0,
  };

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('wesios_org_sync_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(80)) {
      Hive.registerAdapter(OrganizationStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(81)) {
      Hive.registerAdapter(OrganizationModelAdapter());
    }
  });

  setUp(() async {
    sync = OrganizationsSync();
    final box = await sync.ensureBox();
    await box.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('orphan cache cannot block valid remote tree recovery', () async {
    final box = Hive.box<OrganizationModel>(OrganizationService.boxName);
    await box.put(
      'orphan',
      OrganizationModel(
        id: 'orphan',
        name: 'Orphan cache row',
        parentId: 'missing-parent',
        isRoot: false,
        baseCurrency: 'RUB',
        createdAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 1),
        createdBy: 'old-cache',
      ),
    );

    expect(
      await sync.applyFields(
        payload(id: OrganizationModel.rootId, name: 'Wesi Inc', isRoot: true),
      ),
      isTrue,
    );
    expect(
      await sync.applyFields(
        payload(
          id: OrganizationModel.wesiBeatsId,
          name: 'Wesi Beats',
          parentId: OrganizationModel.rootId,
        ),
      ),
      isTrue,
    );
    expect(
      await sync.applyFields(
        payload(
          id: 'org_it',
          name: "Wesi Inc IT Studio's",
          parentId: OrganizationModel.rootId,
        ),
      ),
      isTrue,
    );

    expect(
      sync.local().keys,
      containsAll(<String>[
        OrganizationModel.rootId,
        OrganizationModel.wesiBeatsId,
        'org_it',
      ]),
    );
    expect(sync.local().containsKey('orphan'), isFalse);
    expect(
      box.containsKey('orphan'),
      isTrue,
      reason: 'invalid local data is quarantined, not deleted',
    );
  });

  test('child is deferred until its parent chain exists', () async {
    expect(
      await sync.applyFields(
        payload(id: 'child', name: 'Child', parentId: OrganizationModel.rootId),
      ),
      isFalse,
    );
    expect(
      await sync.applyFields(
        payload(id: OrganizationModel.rootId, name: 'Wesi Inc', isRoot: true),
      ),
      isTrue,
    );
    expect(
      await sync.applyFields(
        payload(id: 'child', name: 'Child', parentId: OrganizationModel.rootId),
      ),
      isTrue,
    );
  });

  test('cycle remains rejected', () async {
    expect(
      await sync.applyFields(
        payload(id: OrganizationModel.rootId, name: 'Wesi Inc', isRoot: true),
      ),
      isTrue,
    );
    expect(
      await sync.applyFields(
        payload(id: 'a', name: 'A', parentId: OrganizationModel.rootId),
      ),
      isTrue,
    );
    expect(
      await sync.applyFields(payload(id: 'b', name: 'B', parentId: 'a')),
      isTrue,
    );
    expect(
      await sync.applyFields(payload(id: 'a', name: 'A', parentId: 'b')),
      isFalse,
    );
  });

  test('archived parent waits for active children', () async {
    expect(
      await sync.applyFields(
        payload(id: OrganizationModel.rootId, name: 'Wesi Inc', isRoot: true),
      ),
      isTrue,
    );
    expect(
      await sync.applyFields(
        payload(
          id: 'parent',
          name: 'Parent',
          parentId: OrganizationModel.rootId,
        ),
      ),
      isTrue,
    );
    expect(
      await sync.applyFields(
        payload(id: 'child', name: 'Child', parentId: 'parent'),
      ),
      isTrue,
    );

    expect(
      await sync.applyFields(
        payload(
          id: 'parent',
          name: 'Parent',
          parentId: OrganizationModel.rootId,
          archived: true,
        ),
      ),
      isFalse,
    );
    expect(
      await sync.applyFields(
        payload(id: 'child', name: 'Child', parentId: 'parent', archived: true),
      ),
      isTrue,
    );
    expect(
      await sync.applyFields(
        payload(
          id: 'parent',
          name: 'Parent',
          parentId: OrganizationModel.rootId,
          archived: true,
        ),
      ),
      isTrue,
    );
  });
}
