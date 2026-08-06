import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/roadmap_models.dart';

class RoadmapService {
  static const String boxName = 'wesios_roadmap';
  static const String _projectsKey = 'projects_v1';
  static const String _itemsKey = 'items_v1';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Box<dynamic>? _box;

  static Future<Box<dynamic>> _open() async {
    _box ??= await Hive.openBox<dynamic>(boxName);
    return _box!;
  }

  static String newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  static Future<List<RoadmapProject>> projects({bool includeArchived = true}) async {
    final box = await _open();
    final list = _decodeList(box.get(_projectsKey), RoadmapProject.tryParse);
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
    final box = await _open();
    final list = _decodeList(box.get(_itemsKey), RoadmapItem.tryParse);
    list.sort((a, b) {
      final byProject = a.projectId.compareTo(b.projectId);
      if (byProject != 0) return byProject;
      final byOrder = a.order.compareTo(b.order);
      if (byOrder != 0) return byOrder;
      return a.startDate.compareTo(b.startDate);
    });
    return list;
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

  static Future<void> _write<T>(
    String key,
    List<T> values,
    Map<String, dynamic> Function(T value) encode,
  ) async {
    final box = await _open();
    await box.put(key, jsonEncode([for (final value in values) encode(value)]));
    revision.value++;
  }

  static Future<void> saveProject(RoadmapProject project) async {
    final all = await projects();
    final normalized = project.copyWith(updatedAt: DateTime.now());
    final index = all.indexWhere((value) => value.id == project.id);
    if (index < 0) {
      all.add(normalized);
    } else {
      all[index] = normalized;
    }
    await _write(_projectsKey, all, (value) => value.toJson());
  }

  static Future<void> archiveProject(String id, {bool archived = true}) async {
    final all = await projects();
    final index = all.indexWhere((value) => value.id == id);
    if (index < 0) return;
    all[index] = all[index].copyWith(
      archived: archived,
      updatedAt: DateTime.now(),
    );
    await _write(_projectsKey, all, (value) => value.toJson());
  }

  static Future<void> deleteProject(String id) async {
    final allProjects = await projects();
    final allItems = await items();
    await _write(
      _projectsKey,
      allProjects.where((value) => value.id != id).toList(),
      (value) => value.toJson(),
    );
    await _write(
      _itemsKey,
      allItems.where((value) => value.projectId != id).toList(),
      (value) => value.toJson(),
    );
  }

  static Future<void> saveItem(RoadmapItem item) async {
    final all = await items();
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
    final index = all.indexWhere((value) => value.id == item.id);
    if (index < 0) {
      all.add(normalized);
    } else {
      all[index] = normalized;
    }
    await _write(_itemsKey, all, (value) => value.toJson());
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
    final all = await items();
    final cleaned = [
      for (final value in all)
        if (value.id != id)
          value.dependencyIds.contains(id)
              ? value.copyWith(
                  dependencyIds: value.dependencyIds
                      .where((dependency) => dependency != id)
                      .toList(),
                )
              : value,
    ];
    await _write(_itemsKey, cleaned, (value) => value.toJson());
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
    final box = await _open();
    await box.clear();
    revision.value++;
  }
}