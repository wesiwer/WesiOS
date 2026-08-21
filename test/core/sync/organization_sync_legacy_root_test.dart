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
  }) => <String, dynamic>{
    'id': id,
    'name': name,
    'parentId': parentId,
    'isRoot': isRoot,
    'baseCurrency': 'RUB',
    'status': 'active',
    'createdAt': '2026-08-17T13:19:24.672',
    'updatedAt': '2026-08-17T13:19:24.672',
    'createdBy': 'sync-test',
    'sortOrder': 0,
  };

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('wesios_org_legacy_sync_');
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

  test('legacy root metadata is canonicalized by immutable root id', () async {
    final legacyRoot =
        payload(
            id: OrganizationModel.rootId,
            name: 'Wesi Inc',
            parentId: 'legacy-parent-that-must-be-ignored',
            isRoot: false,
          )
          ..remove('createdAt')
          ..['created'] = '2026-08-17T13:19:24.672';

    expect(await sync.applyFields(legacyRoot), isTrue);

    final root = Hive.box<OrganizationModel>(OrganizationService.boxName)
        .get(OrganizationModel.rootId);
    expect(root, isNotNull);
    expect(root!.isRoot, isTrue);
    expect(root.parentId, isNull);

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
  });

  test('organization apply reopens a closed Hive box', () async {
    final box = Hive.box<OrganizationModel>(OrganizationService.boxName);
    await box.close();

    expect(
      await sync.applyFields(
        payload(id: OrganizationModel.rootId, name: 'Wesi Inc'),
      ),
      isTrue,
    );
    expect(Hive.isBoxOpen(OrganizationService.boxName), isTrue);
  });
}
