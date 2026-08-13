import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/roadmap_models.dart';

/// Проекты и дорожная карта.
///
/// Каждый проект и каждая веха лежат **отдельной записью**, ключ — их
/// идентификатор. Раньше весь список был одной строкой JSON под ключом
/// `projects_v1`, и это делало совместную работу невозможной: журнал
/// синхронизации следит за ключами бокса, а ключ был один на всё. Правка
/// одной вехи на телефоне уезжала бы как «изменился весь список» и стирала
/// бы чужую правку соседней вехи, сделанную в это же время на компьютере.
///
/// Старый формат читается при первом открытии и разбирается по записям —
/// данные, заведённые до этой версии, не теряются.
class RoadmapService {
  /// Старый бокс. Остаётся только как источник для переноса.
  static const String boxName = 'wesios_roadmap';
  static const String projectsBoxName = 'wesios_roadmap_projects';
  static const String itemsBoxName = 'wesios_roadmap_items';
  static const String _projectsKey = 'projects_v1';
  static const String _itemsKey = 'items_v1';
  static const String _migratedKey = 'migrated_to_records_v1';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Box<String>? _projectsBox;
  static Box<String>? _itemsBox;

  static Future<Box<String>> _openProjects() async {
    _projectsBox ??= Hive.isBoxOpen(projectsBoxName)
        ? Hive.box<String>(projectsBoxName)
        : await Hive.openBox<String>(projectsBoxName);
    await _migrateIfNeeded();
    return _projectsBox!;
  }

  static Future<Box<String>> _openItems() async {
    _itemsBox ??= Hive.isBoxOpen(itemsBoxName)
        ? Hive.box<String>(itemsBoxName)
        : await Hive.openBox<String>(itemsBoxName);
    await _migrateIfNeeded();
    return _itemsBox!;
  }

  static bool _migrating = false;

  /// Перенос со старого формата «весь список одной строкой».
  ///
  /// Выполняется один раз и помечается в старом же боксе: пока отметки нет,
  /// перенос повторяется, поэтому оборванный на середине переезд не теряет
  /// данные, а просто случается заново.
  static Future<void> _migrateIfNeeded() async {
    if (_migrating) return;
    if (!Hive.isBoxOpen(boxName)) {
      // Старого бокса нет вовсе — свежая установка, переносить нечего.
      final exists = await Hive.boxExists(boxName);
      if (!exists) return;
    }
    _migrating = true;
    try {
      final legacy = Hive.isBoxOpen(boxName)
          ? Hive.box<dynamic>(boxName)
          : await Hive.openBox<dynamic>(boxName);
      if (legacy.get(_migratedKey) == true) return;

      final projectsBox = _projectsBox ??= Hive.isBoxOpen(projectsBoxName)
          ? Hive.box<String>(projectsBoxName)
          : await Hive.openBox<String>(projectsBoxName);
      final itemsBox = _itemsBox ??= Hive.isBoxOpen(itemsBoxName)
          ? Hive.box<String>(itemsBoxName)
          : await Hive.openBox<String>(itemsBoxName);

      for (final project
          in _decodeList(legacy.get(_projectsKey), RoadmapProject.tryParse)) {
        // Уже перенесённое не трогаем: у него мог появиться более свежий
        // вариант с другого устройства.
        if (projectsBox.containsKey(project.id)) continue;
        await projectsBox.put(project.id, jsonEncode(project.toJson()));
      }
      for (final item
          in _decodeList(legacy.get(_itemsKey), RoadmapItem.tryParse)) {
        if (itemsBox.containsKey(item.id)) continue;
        await itemsBox.put(item.id, jsonEncode(item.toJson()));
      }
      await legacy.put(_migratedKey, true);
    } catch (_) {
      // Сломанный старый бокс не должен мешать работать дальше: проекты
      // будут пустыми, но приложение запустится.
    } finally {
      _migrating = false;
    }
  }

  static String newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  static Future<List<RoadmapProject>> projects({bool includeArchived = true}) async {
    final box = await _openProjects();
    final list = _decodeRecords(box, RoadmapProject.tryParse);
    list.sort((a, b) {
      final byArchive = (a.archived ? 1 : 0).compareTo(b.archived ? 1 : 0);
      if (byArchive != 0) return byArchive;
      return a.startDate.compareTo(b.startDate);
    });
    return includeArchived
        ? list
        : list.where((value) => !value.archived).toList();
  }

  static Future<List<RoadmapItem>> items() async {
    final box = await _openItems();
    final list = _decodeRecords(box, RoadmapItem.tryParse);
    list.sort((a, b) {
      final byProject = a.projectId.compareTo(b.projectId);
      if (byProject != 0) return byProject;
      final byOrder = a.order.compareTo(b.order);
      if (byOrder != 0) return byOrder;
      return a.startDate.compareTo(b.startDate);
    });
    return list;
  }

  /// Разбор бокса, где каждая запись — своя строка JSON.
  static List<T> _decodeRecords<T>(
    Box<String> box,
    T? Function(Map<String, dynamic>) parse,
  ) {
    final out = <T>[];
    for (final raw in box.values) {
      if (raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final value = parse(Map<String, dynamic>.from(decoded));
        if (value != null) out.add(value);
      } catch (_) {
        // Одна испорченная запись не должна прятать остальные.
      }
    }
    return out;
  }

  static List<T> _decodeList<T>(
    Object? raw,
    T? Function(Map<String, dynamic>) parse,
  ) {
    if (raw is! String || raw.isEmpty) return <T>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <T>[];
      return [
        for (final value in decoded)
          if (value is Map)
            if (parse(Map<String, dynamic>.from(value)) case final item?) item,
      ];
    } catch (_) {
      return <T>[];
    }
  }

  static Future<void> _putProject(RoadmapProject value) async {
    final box = await _openProjects();
    await box.put(value.id, jsonEncode(value.toJson()));
    revision.value++;
  }

  static Future<void> _putItem(RoadmapItem value) async {
    final box = await _openItems();
    await box.put(value.id, jsonEncode(value.toJson()));
    revision.value++;
  }

  static Future<void> saveProject(RoadmapProject project) async {
    await _putProject(project.copyWith(updatedAt: DateTime.now()));
  }

  static Future<void> archiveProject(String id, {bool archived = true}) async {
    final all = await projects();
    final index = all.indexWhere((value) => value.id == id);
    if (index < 0) return;
    await _putProject(all[index].copyWith(
      archived: archived,
      updatedAt: DateTime.now(),
    ));
  }

  static Future<void> deleteProject(String id) async {
    final projectsBox = await _openProjects();
    final itemsBox = await _openItems();
    await projectsBox.delete(id);
    // Вехи удалённого проекта тоже уходят — поимённо, чтобы каждая оставила
    // в журнале своё надгробие и удаление доехало до других устройств.
    for (final item in await items()) {
      if (item.projectId == id) await itemsBox.delete(item.id);
    }
    revision.value++;
  }

  static Future<void> saveItem(RoadmapItem item) async {
    final sanitizedDependencies = item.dependencyIds
        .where((value) => value != item.id)
        .toSet()
        .toList();
    var normalized = item.copyWith(
      dependencyIds: sanitizedDependencies,
      updatedAt: DateTime.now(),
    );
    if (normalized.status == RoadmapItemStatus.done &&
        normalized.progress < 100) {
      normalized = normalized.copyWith(progress: 100);
    }
    if (normalized.progress >= 100 &&
        normalized.status != RoadmapItemStatus.done) {
      normalized = normalized.copyWith(status: RoadmapItemStatus.done);
    }
    await _putItem(normalized);
  }

  static Future<void> updateProgress(String id, int progress) async {
    final all = await items();
    final index = all.indexWhere((value) => value.id == id);
    if (index < 0) return;
    final value = progress.clamp(0, 100).toInt();
    var status = all[index].status;
    if (value >= 100) {
      status = RoadmapItemStatus.done;
    } else if (value > 0 && status == RoadmapItemStatus.planned) {
      status = RoadmapItemStatus.inProgress;
    } else if (value < 100 && status == RoadmapItemStatus.done) {
      status = RoadmapItemStatus.inProgress;
    }
    await saveItem(all[index].copyWith(progress: value, status: status));
  }

  static Future<void> deleteItem(String id) async {
    final box = await _openItems();
    await box.delete(id);
    // Ссылки на удалённую веху вычищаются только у тех, кто на неё ссылался:
    // переписывать записи, которых это не касается, значило бы объявить их
    // изменёнными и отправить на сервер целый список ни за чем.
    for (final value in await items()) {
      if (!value.dependencyIds.contains(id)) continue;
      await _putItem(value.copyWith(
        dependencyIds: value.dependencyIds
            .where((dependency) => dependency != id)
            .toList(),
        updatedAt: DateTime.now(),
      ));
    }
    revision.value++;
  }

  static Future<List<RoadmapItem>> itemsForProject(String projectId) async =>
      (await items())
          .where((value) => value.projectId == projectId)
          .toList();

  static Future<double> projectProgress(String projectId) async {
    final list = await itemsForProject(projectId);
    if (list.isEmpty) return 0;
    final phases = list.where((value) => value.kind == RoadmapItemKind.phase).toList();
    final source = phases.isEmpty ? list : phases;
    return source.fold<double>(0, (sum, value) => sum + value.progress) /
        source.length /
        100;
  }

  static Future<RoadmapSummary> summary() async {
    final allProjects = await projects();
    final allItems = await items();
    final visibleProjects = allProjects.where((value) => !value.archived).toList();
    return RoadmapSummary(
      projects: allProjects.length,
      activeProjects: visibleProjects.length,
      items: allItems.length,
      milestones:
          allItems.where((value) => value.kind == RoadmapItemKind.milestone).length,
      blocked:
          allItems.where((value) => value.status == RoadmapItemStatus.blocked).length,
      overdue: allItems.where((value) => value.isOverdue).length,
      completed: allItems.where((value) => value.isDone).length,
      averageProgress: allItems.isEmpty
          ? 0
          : allItems.fold<double>(0, (sum, value) => sum + value.progress) /
              allItems.length /
              100,
    );
  }

  static Future<void> clearForTest() async {
    await (await _openProjects()).clear();
    await (await _openItems()).clear();
    if (Hive.isBoxOpen(boxName)) await Hive.box<dynamic>(boxName).clear();
    revision.value++;
  }
}