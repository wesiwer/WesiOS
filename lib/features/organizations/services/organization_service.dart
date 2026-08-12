import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/organization_model.dart';

class OrganizationTreeException implements Exception {
  final String message;
  const OrganizationTreeException(this.message);
  @override
  String toString() => 'OrganizationTreeException: $message';
}

class OrganizationService {
  OrganizationService._();

  static const String boxName = 'wesios_organizations';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Box<OrganizationModel>? _box;

  static Future<Box<OrganizationModel>> _open() async {
    _box ??= await Hive.openBox<OrganizationModel>(boxName);
    return _box!;
  }

  static Future<void> ensureBaseline({String createdBy = 'migration'}) async {
    final box = await _open();
    final now = DateTime.now();

    final roots = box.values.where((o) => o.isRoot).toList();
    OrganizationModel root;
    if (roots.isEmpty) {
      root = OrganizationModel(
        id: OrganizationModel.rootId,
        name: 'Wesi Inc',
        parentId: null,
        isRoot: true,
        baseCurrency: 'RUB',
        createdAt: now,
        updatedAt: now,
        createdBy: createdBy,
        code: 'WESI',
        sortOrder: 0,
      );
      await box.put(root.id, root);
    } else {
      root = roots.first;
      // Multiple roots must never silently survive. Keep the oldest as root,
      // attach accidental extras below it so the tree remains traversable.
      if (roots.length > 1) {
        roots.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        root = roots.first;
        for (final extra in roots.skip(1)) {
          await box.put(
            extra.id,
            OrganizationModel(
              id: extra.id,
              name: extra.name,
              parentId: root.id,
              isRoot: false,
              baseCurrency: extra.baseCurrency,
              status: extra.status,
              createdAt: extra.createdAt,
              updatedAt: now,
              createdBy: extra.createdBy,
              code: extra.code,
              description: extra.description,
              colorValue: extra.colorValue,
              sortOrder: extra.sortOrder,
            ),
          );
        }
      }
    }

    if (box.get(OrganizationModel.wesiBeatsId) == null) {
      await box.put(
        OrganizationModel.wesiBeatsId,
        OrganizationModel(
          id: OrganizationModel.wesiBeatsId,
          name: 'Wesi Beats',
          parentId: root.id,
          isRoot: false,
          baseCurrency: root.baseCurrency,
          createdAt: now,
          updatedAt: now,
          createdBy: createdBy,
          code: 'BEATS',
          sortOrder: 10,
        ),
      );
    }
    revision.value++;
  }

  static Future<List<OrganizationModel>> all({
    bool includeArchived = false,
  }) async {
    await ensureBaseline();
    final box = await _open();
    final list = box.values
        .where((o) => includeArchived || !o.archived)
        .toList()
      ..sort((a, b) {
        if (a.isRoot != b.isRoot) return a.isRoot ? -1 : 1;
        final order = a.sortOrder.compareTo(b.sortOrder);
        if (order != 0) return order;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  static Future<OrganizationModel?> byId(String id) async {
    await ensureBaseline();
    return (await _open()).get(id);
  }

  static Future<OrganizationModel> root() async {
    await ensureBaseline();
    final roots = (await _open()).values.where((o) => o.isRoot).toList();
    if (roots.length != 1) {
      throw const OrganizationTreeException('tree must contain exactly one root');
    }
    return roots.single;
  }

  static Future<List<OrganizationModel>> childrenOf(
    String id, {
    bool includeArchived = false,
  }) async {
    final list = await all(includeArchived: includeArchived);
    return list.where((o) => o.parentId == id).toList();
  }

  static Future<Set<String>> subtreeIds(
    String rootId, {
    bool includeArchived = false,
  }) async {
    final nodes = await all(includeArchived: includeArchived);
    if (!nodes.any((o) => o.id == rootId)) return <String>{};
    final byParent = <String, List<String>>{};
    for (final node in nodes) {
      final parent = node.parentId;
      if (parent == null) continue;
      byParent.putIfAbsent(parent, () => <String>[]).add(node.id);
    }
    final result = <String>{rootId};
    final queue = <String>[rootId];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final child in byParent[current] ?? const <String>[]) {
        if (result.add(child)) queue.add(child);
      }
    }
    return result;
  }

  static Future<bool> isDescendant(String candidateId, String ancestorId) async {
    if (candidateId == ancestorId) return false;
    return (await subtreeIds(ancestorId, includeArchived: true))
        .contains(candidateId);
  }

  static Future<OrganizationModel> create({
    required String name,
    required String parentId,
    String baseCurrency = 'RUB',
    required String createdBy,
    String? code,
    String? description,
    int? colorValue,
    int sortOrder = 0,
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw const OrganizationTreeException('organization name is empty');
    }
    final parent = await byId(parentId);
    if (parent == null || parent.archived) {
      throw const OrganizationTreeException('parent does not exist or is archived');
    }
    final now = DateTime.now();
    final id = 'org_${now.microsecondsSinceEpoch}';
    final model = OrganizationModel(
      id: id,
      name: normalized,
      parentId: parentId,
      isRoot: false,
      baseCurrency: baseCurrency.trim().toUpperCase().isEmpty
          ? parent.baseCurrency
          : baseCurrency.trim().toUpperCase(),
      createdAt: now,
      updatedAt: now,
      createdBy: createdBy,
      code: code?.trim().isEmpty == true ? null : code?.trim(),
      description: description?.trim().isEmpty == true
          ? null
          : description?.trim(),
      colorValue: colorValue,
      sortOrder: sortOrder,
    );
    await (await _open()).put(id, model);
    revision.value++;
    return model;
  }

  static Future<OrganizationModel> update(
    OrganizationModel organization, {
    String? name,
    String? parentId,
    String? baseCurrency,
    OrganizationStatus? status,
    String? code,
    String? description,
    int? colorValue,
    int? sortOrder,
  }) async {
    final current = await byId(organization.id);
    if (current == null) {
      throw const OrganizationTreeException('organization does not exist');
    }
    if (current.isRoot && parentId != null) {
      throw const OrganizationTreeException('root cannot have a parent');
    }
    if (current.isRoot && status == OrganizationStatus.archived) {
      throw const OrganizationTreeException('root cannot be archived');
    }
    if (parentId != null && parentId != current.parentId) {
      if (parentId == current.id || await isDescendant(parentId, current.id)) {
        throw const OrganizationTreeException('cyclic organization tree');
      }
      final parent = await byId(parentId);
      if (parent == null || parent.archived) {
        throw const OrganizationTreeException('new parent is invalid');
      }
    }
    final next = current.copyWith(
      name: name?.trim().isEmpty == false ? name!.trim() : null,
      parentId: parentId,
      baseCurrency: baseCurrency?.trim().toUpperCase(),
      status: status,
      code: code,
      description: description,
      colorValue: colorValue,
      sortOrder: sortOrder,
      updatedAt: DateTime.now(),
    );
    await (await _open()).put(next.id, next);
    revision.value++;
    return next;
  }

  static Future<bool> archive(String id) async {
    final org = await byId(id);
    if (org == null || org.isRoot) return false;
    final activeChildren = await childrenOf(id);
    if (activeChildren.isNotEmpty) return false;
    await (await _open()).put(
      id,
      org.copyWith(status: OrganizationStatus.archived, updatedAt: DateTime.now()),
    );
    revision.value++;
    return true;
  }

  static Future<bool> restore(String id) async {
    final org = await byId(id);
    if (org == null || !org.archived) return false;
    if (org.parentId != null) {
      final parent = await byId(org.parentId!);
      if (parent == null || parent.archived) return false;
    }
    await (await _open()).put(
      id,
      org.copyWith(status: OrganizationStatus.active, updatedAt: DateTime.now()),
    );
    revision.value++;
    return true;
  }

  static Future<List<String>> validateTree() async {
    final nodes = await all(includeArchived: true);
    final errors = <String>[];
    final roots = nodes.where((o) => o.isRoot).toList();
    if (roots.length != 1) errors.add('expected exactly one root');
    final ids = nodes.map((e) => e.id).toSet();
    for (final node in nodes) {
      if (node.isRoot && node.parentId != null) {
        errors.add('${node.id}: root has parent');
      }
      if (!node.isRoot && (node.parentId == null || !ids.contains(node.parentId))) {
        errors.add('${node.id}: missing parent');
      }
      final seen = <String>{node.id};
      var cursor = node.parentId;
      while (cursor != null) {
        if (!seen.add(cursor)) {
          errors.add('${node.id}: cycle detected');
          break;
        }
        final parent = nodes.where((e) => e.id == cursor).firstOrNull;
        cursor = parent?.parentId;
      }
    }
    return errors;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
