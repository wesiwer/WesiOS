import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/core/sync/sync_engine.dart';
import 'package:wesios/core/sync/sync_journal.dart';
import 'package:wesios/features/roadmap/models/roadmap_models.dart';
import 'package:wesios/features/roadmap/services/roadmap_service.dart';

import 'fake_sync_transport.dart';

/// Проекты не синхронизировались вообще: их не было в списке коллекций, а
/// хранились они одной строкой JSON на весь список — журнал следит за
/// ключами бокса, и такой ключ был один. Совместная работа над дорожной
/// картой при этом невозможна в принципе: правка одной вехи считалась бы
/// изменением всего списка и затирала бы чужую.
void main() {
  late Directory dir;
  final base = DateTime.utc(2026, 8, 12, 10);

  RoadmapProject project(String id, String title) => RoadmapProject(
        id: id,
        title: title,
        description: '',
        owner: 'wesi',
        tags: const [],
        colorValue: 0xFF3B82F6,
        startDate: base,
        endDate: base.add(const Duration(days: 30)),
        createdAt: base,
        updatedAt: base,
      );

  RoadmapItem item(String id, String projectId, String title) => RoadmapItem(
        id: id,
        projectId: projectId,
        title: title,
        description: '',
        kind: RoadmapItemKind.phase,
        status: RoadmapItemStatus.planned,
        assignee: '',
        startDate: base,
        endDate: base.add(const Duration(days: 7)),
        progress: 0,
        order: 0,
        dependencyIds: const [],
        linkedTaskIds: const [],
        createdAt: base,
        updatedAt: base,
      );

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_roadmap_sync');
    Hive.init(dir.path);
    await Hive.openBox('wesios_settings');
    await Hive.openBox(SyncJournal.boxName);
    await Hive.openBox<String>(RoadmapService.projectsBoxName);
    await Hive.openBox<String>(RoadmapService.itemsBoxName);
  });

  tearDownAll(() async {
    await SyncEngine.reset();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    await SyncEngine.reset();
    await Hive.box('wesios_settings').clear();
    await Hive.box(SyncJournal.boxName).clear();
    await RoadmapService.clearForTest();
  });

  test('проекты вообще участвуют в обмене', () {
    final names = [for (final c in SyncCodec.collections) c.name];
    expect(names, contains('roadmap_projects'),
        reason: 'без этого дорожная карта живёт только на одном устройстве');
    expect(names, contains('roadmap_items'));
  });

  test('созданный проект уезжает на сервер', () async {
    await RoadmapService.saveProject(project('P1', 'Альбом'));
    await RoadmapService.saveItem(item('I1', 'P1', 'Сведение'));
    await Future<void>.delayed(Duration.zero);

    final t = FakeSyncTransport();
    final report = await SyncEngine.run(transport: t, now: base);

    expect(report.ok, isTrue, reason: report.describe());
    expect(t.store['roadmap_projects']?['P1'], isNotNull,
        reason: 'проект обязан оказаться на сервере');
    expect(t.store['roadmap_items']?['I1'], isNotNull);
    expect(t.store['roadmap_projects']!['P1']!.fields['title'], 'Альбом');
  });

  test('чужой проект приезжает и виден в списке', () async {
    final t = FakeSyncTransport();
    t.seed('roadmap_projects', 'P2', project('P2', 'Клип').toJson(), base);
    t.seed('roadmap_items', 'I2', item('I2', 'P2', 'Съёмка').toJson(), base);

    await SyncEngine.run(transport: t, now: base);

    final projects = await RoadmapService.projects();
    expect(projects.map((p) => p.id), contains('P2'));
    expect(projects.firstWhere((p) => p.id == 'P2').title, 'Клип');
    expect((await RoadmapService.items()).map((i) => i.id), contains('I2'));
  });

  test('правка одной вехи не стирает соседнюю, изменённую на другом '
      'устройстве', () async {
    // Ровно то, из-за чего хранение одной строкой было непригодно.
    await RoadmapService.saveItem(item('I1', 'P1', 'Сведение'));
    await RoadmapService.saveItem(item('I2', 'P1', 'Мастеринг'));
    await Future<void>.delayed(Duration.zero);

    final t = FakeSyncTransport();
    await SyncEngine.run(transport: t, now: base);

    // Сосед правит вторую веху и кладёт её на сервер.
    final later = base.add(const Duration(hours: 1));
    t.seed(
      'roadmap_items',
      'I2',
      item('I2', 'P1', 'Мастеринг у Ивана').copyWith(updatedAt: later).toJson(),
      later,
    );

    // Мы в это же время правим первую.
    await RoadmapService.saveItem(
        item('I1', 'P1', 'Сведение готово').copyWith(updatedAt: later));
    await Future<void>.delayed(Duration.zero);
    await SyncJournal.record('roadmap_items', 'I1', SyncStamp(later));

    await SyncEngine.run(
        transport: t, now: base.add(const Duration(hours: 2)));

    final items = await RoadmapService.items();
    final titles = {for (final i in items) i.id: i.title};
    expect(titles['I1'], 'Сведение готово', reason: 'наша правка потерялась');
    expect(titles['I2'], 'Мастеринг у Ивана',
        reason: 'чужая правка не доехала');
  });

  test('удалённый проект не воскресает с другого устройства', () async {
    await RoadmapService.saveProject(project('P3', 'Тур'));
    await Future<void>.delayed(Duration.zero);

    final t = FakeSyncTransport();
    await SyncEngine.run(transport: t, now: base);
    expect(t.store['roadmap_projects']?['P3'], isNotNull);

    await RoadmapService.deleteProject('P3');
    await Future<void>.delayed(Duration.zero);

    await SyncEngine.run(
        transport: t, now: base.add(const Duration(hours: 1)));

    expect(t.store['roadmap_projects']!['P3']!.deleted, isTrue,
        reason: 'сервер обязан узнать об удалении, иначе проект вернётся');

    await SyncEngine.run(
        transport: t, now: base.add(const Duration(hours: 2)));
    expect((await RoadmapService.projects()).map((p) => p.id),
        isNot(contains('P3')));
  });

  test('данные из старого формата переносятся, а не пропадают', () async {
    // Так выглядел бокс до этой версии: весь список одной строкой.
    final legacy = await Hive.openBox<dynamic>(RoadmapService.boxName);
    await legacy.clear();
    await legacy.put(
      'projects_v1',
      jsonEncode([project('OLD1', 'Старый проект').toJson()]),
    );
    await legacy.put(
      'items_v1',
      jsonEncode([item('OLDI1', 'OLD1', 'Старая веха').toJson()]),
    );

    // Обращение к сервису запускает перенос.
    final projects = await RoadmapService.projects();
    expect(projects.map((p) => p.id), contains('OLD1'),
        reason: 'проекты, заведённые до перехода, обязаны сохраниться');
    expect((await RoadmapService.items()).map((i) => i.id), contains('OLDI1'));

    // Повторное обращение не создаёт дублей и не откатывает правки.
    await RoadmapService.saveProject(
        project('OLD1', 'Переименован').copyWith(updatedAt: base));
    final again = await RoadmapService.projects();
    expect(again.where((p) => p.id == 'OLD1').length, 1);
    expect(again.firstWhere((p) => p.id == 'OLD1').title, 'Переименован');
  });
}
