import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/localization/wesi_locale.dart';
import '../data/builtin_articles.dart';
import '../models/article_model.dart';

class KnowledgeService {
  static const String _boxName = 'wesios_knowledge';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Box<ArticleModel>? _box;
  static Future<Box<ArticleModel>>? _opening;
  static Future<void>? _seeding;
  static bool _seeded = false;

  /// Все параллельные вызовы используют одно открытие Hive-box.
  static Future<Box<ArticleModel>> get _articlesBox {
    final ready = _box;
    if (ready != null && ready.isOpen) return Future.value(ready);
    final running = _opening;
    if (running != null) return running;

    final future = Hive.openBox<ArticleModel>(_boxName).then((box) {
      _box = box;
      return box;
    });
    _opening = future;
    future.whenComplete(() {
      if (identical(_opening, future)) _opening = null;
    });
    return future;
  }

  /// Старт приложения и экран присоединяются к одному посеву статей.
  static Future<void> seed({bool force = false}) {
    if (_seeded && !force) return Future.value();
    final running = _seeding;
    if (running != null) return running;

    final future = _seed(force);
    _seeding = future;
    future.whenComplete(() {
      if (identical(_seeding, future)) _seeding = null;
    });
    return future;
  }

  static Future<void> _seed(bool force) async {
    if (_seeded && !force) return;
    final box = await _articlesBox;
    var changed = false;
    final builtins = BuiltinArticles.all(WesiLocale.isRussian);

    for (final article in builtins) {
      final existing = box.get(article.id);
      if (existing == null) {
        await box.put(article.id, article);
        changed = true;
        continue;
      }
      if (!existing.builtIn) continue;

      final next = article.copyWith(
        pinned: existing.pinned,
        updatedAt: existing.updatedAt,
      );
      if (next.title != existing.title ||
          next.body != existing.body ||
          next.section != existing.section ||
          next.orderRaw != existing.orderRaw ||
          next.parentId != existing.parentId ||
          !_sameTags(next.tags, existing.tags) ||
          next.pinned != existing.pinned) {
        await box.put(article.id, next);
        changed = true;
      }
    }

    if (await _pruneStale(box, {for (final a in builtins) a.id})) {
      changed = true;
    }
    _seeded = true;
    if (changed) revision.value++;
  }

  static Future<bool> _pruneStale(
    Box<ArticleModel> box,
    Set<String> keep,
  ) async {
    final stale = <String>{
      for (final a in box.values)
        if (a.builtIn && !keep.contains(a.id)) a.id,
    };
    if (stale.isEmpty) return false;

    for (final article in box.values.where(
      (a) => !a.builtIn && a.parentId != null && stale.contains(a.parentId),
    )) {
      await box.put(article.id, article.copyWith(parentId: null));
    }
    await box.deleteAll(stale);
    return true;
  }

  static bool _sameTags(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Future<List<ArticleModel>> getAll() async {
    final box = await _articlesBox;
    final list = box.values.toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        final byDate = b.updatedAt.compareTo(a.updatedAt);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    return list;
  }

  static Future<List<ArticleModel>> search({
    String query = '',
    ArticleSection? section,
  }) async {
    final all = await getAll();
    return all
        .where((a) => section == null || a.section == section)
        .where((a) => a.matches(query))
        .toList();
  }

  static Future<ArticleModel?> getById(String id) async =>
      (await _articlesBox).get(id);

  static Future<void> save(ArticleModel article) async {
    await (await _articlesBox).put(article.id, article);
    revision.value++;
  }

  static Future<ArticleModel> create({
    required String title,
    required String body,
    ArticleSection section = ArticleSection.playbook,
    List<String> tags = const [],
    String? parentId,
    bool isFolder = false,
  }) async {
    final now = DateTime.now();
    final article = ArticleModel(
      id: now.microsecondsSinceEpoch.toString(),
      title: title.trim(),
      body: body,
      section: section,
      tags: tags,
      createdAt: now,
      updatedAt: now,
      parentId: parentId,
      isFolder: isFolder,
    );
    await save(article);
    return article;
  }

  static Future<bool> delete(String id) async {
    final box = await _articlesBox;
    final article = box.get(id);
    if (article == null || article.builtIn) return false;
    await box.delete(id);
    revision.value++;
    return true;
  }

  static Future<void> togglePin(ArticleModel article) => save(
        article.copyWith(
          pinned: !article.pinned,
          updatedAt: article.updatedAt,
        ),
      );

  static Future<Map<ArticleSection, int>> counts() async {
    final all = await getAll();
    return {
      for (final s in ArticleSection.values)
        s: all.where((a) => a.section == s).length,
    };
  }

  static int compare(ArticleModel a, ArticleModel b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final byOrder = a.order.compareTo(b.order);
    if (byOrder != 0) return byOrder;
    if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
    return a.title.compareTo(b.title);
  }

  static List<ArticleModel> getRoots() {
    final box = _box;
    if (box == null || !box.isOpen) return [];
    return box.values.where((a) => a.parentId == null).toList()..sort(compare);
  }

  static List<ArticleModel> getChildren(String parentId) {
    final box = _box;
    if (box == null || !box.isOpen) return [];
    return box.values.where((a) => a.parentId == parentId).toList()
      ..sort(compare);
  }

  static bool hasChildren(String parentId) {
    final box = _box;
    return box != null &&
        box.isOpen &&
        box.values.any((a) => a.parentId == parentId);
  }

  static List<ArticleModel> getBreadcrumb(String articleId) {
    final box = _box;
    if (box == null || !box.isOpen) return [];
    final result = <ArticleModel>[];
    final seen = <String>{};
    var current = box.get(articleId);
    while (current != null && seen.add(current.id)) {
      result.insert(0, current);
      if (current.parentId == null) break;
      current = box.get(current.parentId);
    }
    return result;
  }

  static Set<String> subtreeIds(String rootId) {
    final box = _box;
    if (box == null || !box.isOpen) return {rootId};
    final ids = <String>{rootId};
    var grew = true;
    while (grew) {
      grew = false;
      for (final article in box.values) {
        final parent = article.parentId;
        if (parent != null && ids.contains(parent) && ids.add(article.id)) {
          grew = true;
        }
      }
    }
    return ids;
  }

  static List<ArticleModel> getSubtree(String rootId) {
    final box = _box;
    if (box == null || !box.isOpen) return [];
    final result = <ArticleModel>[];
    final seen = <String>{rootId};

    void collect(String parentId) {
      for (final child
          in box.values.where((a) => a.parentId == parentId).toList()) {
        if (!seen.add(child.id)) continue;
        result.add(child);
        collect(child.id);
      }
    }

    collect(rootId);
    return result;
  }
}
