import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-org-tree-');
    Hive.init(temp.path);
    if (!Hive.isAdapterRegistered(80)) Hive.registerAdapter(OrganizationStatusAdapter());
    if (!Hive.isAdapterRegistered(81)) Hive.registerAdapter(OrganizationModelAdapter());
  });

  setUp(() async {
    final box = await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await box.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('baseline contains exactly one real root and Wesi Beats child', () async {
    await OrganizationService.ensureBaseline();
    final all = await OrganizationService.all(includeArchived: true);
    final roots = all.where((o) => o.isRoot).toList();
    expect(roots, hasLength(1));
    expect(roots.single.id, OrganizationModel.rootId);
    expect(roots.single.name, 'Wesi Inc');

    final beats = await OrganizationService.byId(OrganizationModel.wesiBeatsId);
    expect(beats, isNotNull);
    expect(beats!.parentId, OrganizationModel.rootId);
    expect(beats.isRoot, isFalse);
    expect(await OrganizationService.validateTree(), isEmpty);
  });

  test('supports arbitrary depth and subtree traversal', () async {
    await OrganizationService.ensureBaseline();
    final it = await OrganizationService.create(
      name: 'IT',
      parentId: OrganizationModel.rootId,
      createdBy: 'test',
    );
    final studioA = await OrganizationService.create(
      name: 'Studio A',
      parentId: it.id,
      createdBy: 'test',
    );
    final project = await OrganizationService.create(
      name: 'Project X',
      parentId: studioA.id,
      createdBy: 'test',
    );

    final ids = await OrganizationService.subtreeIds(it.id);
    expect(ids, containsAll([it.id, studioA.id, project.id]));
    expect(await OrganizationService.isDescendant(project.id, it.id), isTrue);
    expect(await OrganizationService.isDescendant(it.id, project.id), isFalse);
  });

  test('cycle creation is rejected and root cannot be archived', () async {
    await OrganizationService.ensureBaseline();
    final it = await OrganizationService.create(
      name: 'IT',
      parentId: OrganizationModel.rootId,
      createdBy: 'test',
    );
    final studio = await OrganizationService.create(
      name: 'Studio A',
      parentId: it.id,
      createdBy: 'test',
    );

    await expectLater(
      OrganizationService.update(it, parentId: studio.id),
      throwsA(isA<OrganizationTreeException>()),
    );
    expect(await OrganizationService.archive(OrganizationModel.rootId), isFalse);
    expect(await OrganizationService.validateTree(), isEmpty);
  });

  test('parent with active child cannot be archived', () async {
    await OrganizationService.ensureBaseline();
    final it = await OrganizationService.create(
      name: 'IT',
      parentId: OrganizationModel.rootId,
      createdBy: 'test',
    );
    await OrganizationService.create(
      name: 'Studio A',
      parentId: it.id,
      createdBy: 'test',
    );
    expect(await OrganizationService.archive(it.id), isFalse);
  });
}
