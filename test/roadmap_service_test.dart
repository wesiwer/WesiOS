import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/roadmap/models/roadmap_models.dart';
import 'package:wesios/features/roadmap/services/roadmap_service.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_roadmap_test');
    Hive.init(dir.path);
    await Hive.openBox<dynamic>(RoadmapService.boxName);
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  setUp(RoadmapService.clearForTest);

  RoadmapProject project() {
    final now = DateTime(2026, 8, 6);
    return RoadmapProject(
      id: 'p1',
      title: 'WesiOS 1.0',
      startDate: now,
      endDate: now.add(const Duration(days: 90)),
      createdAt: now,
      updatedAt: now,
    );
  }

  RoadmapItem item(
    String id, {
    RoadmapItemStatus status = RoadmapItemStatus.planned,
    int progress = 0,
    List<String> dependencies = const [],
    RoadmapItemKind kind = RoadmapItemKind.phase,
  }) {
    final now = DateTime(2026, 8, 6);
    return RoadmapItem(
      id: id,
      projectId: 'p1',
      title: 'Этап $id',
      status: status,
      progress: progress,
      kind: kind,
      dependencyIds: dependencies,
      startDate: now,
      endDate: now.add(const Duration(days: 14)),
      createdAt: now,
      updatedAt: now,
    );
  }

  test('проект и элементы сохраняются и сортируются', () async {
    await RoadmapService.saveProject(project());
    await RoadmapService.saveItem(item('b').copyWith(order: 2));
    await RoadmapService.saveItem(item('a').copyWith(order: 1));

    expect((await RoadmapService.projects()).single.title, 'WesiOS 1.0');
    expect([for (final value in await RoadmapService.items()) value.id], ['a', 'b']);
  });

  test('100 процентов автоматически переводит этап в done', () async {
    await RoadmapService.saveProject(project());
    await RoadmapService.saveItem(item('a', progress: 20));

    await RoadmapService.updateProgress('a', 100);

    final saved = (await RoadmapService.items()).single;
    expect(saved.progress, 100);
    expect(saved.status, RoadmapItemStatus.done);
  });

  test('done всегда нормализуется до 100 процентов', () async {
    await RoadmapService.saveProject(project());
    await RoadmapService.saveItem(
      item('a', status: RoadmapItemStatus.done, progress: 45),
    );

    final saved = (await RoadmapService.items()).single;
    expect(saved.progress, 100);
    expect(saved.status, RoadmapItemStatus.done);
  });

  test('удаление этапа очищает зависимости у остальных', () async {
    await RoadmapService.saveProject(project());
    await RoadmapService.saveItem(item('first'));
    await RoadmapService.saveItem(item('second', dependencies: ['first']));

    await RoadmapService.deleteItem('first');

    final remaining = (await RoadmapService.items()).single;
    expect(remaining.id, 'second');
    expect(remaining.dependencyIds, isEmpty);
  });

  test('сводка считает блокировки, вехи и прогресс', () async {
    await RoadmapService.saveProject(project());
    await RoadmapService.saveItem(item('a', progress: 50));
    await RoadmapService.saveItem(item(
      'b',
      status: RoadmapItemStatus.blocked,
      progress: 0,
      kind: RoadmapItemKind.milestone,
    ));

    final summary = await RoadmapService.summary();
    expect(summary.activeProjects, 1);
    expect(summary.items, 2);
    expect(summary.milestones, 1);
    expect(summary.blocked, 1);
    expect(summary.averageProgress, closeTo(.25, .0001));
  });
}
