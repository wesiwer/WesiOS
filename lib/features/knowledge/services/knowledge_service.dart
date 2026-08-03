import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/localization/wesi_locale.dart';
import '../data/builtin_articles.dart';
import '../data/ota_error_codes_article.dart';
import '../models/article_model.dart';

/// Хранилище базы знаний.
class KnowledgeService {
  static const String _boxName = 'wesios_knowledge';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Box<ArticleModel>? _box;

  /// Уже сеяли в этом процессе — повторный seed на каждом _load не нужен.
  static bool _seeded = false;

  static Future<Box<ArticleModel>> get _articlesBox async {
    _box ??= await Hive.openBox<ArticleModel>(_boxName);
    return _box!;
  }

  /// Записывает встроенные статьи. Идемпотентно:
  /// - не трогает пользовательские;
  /// - у встроенных сохраняет pin и updatedAt;
  /// - revision++ только если реально что-то изменилось.
  static Future<void> seed({bool force = false}) async {
    if (_seeded && !force) return;
    final box = await _articlesBox;
    var changed = false;

    final builtins = [
      ...BuiltinArticles.all(WesiLocale.isRussian),
      builtinOtaErrorCodesArticle(WesiLocale.isRussian, DateTime.now()),
    ];

    for (final article in builtins) {
      final existing = box.get(article.id);
      if (existing == null) {
        await box.put(article.id, article);
        changed = true;
        continue;
      }
      if (!existing.builtIn) continue;

      // Обновляем текст из кода, pin пользователя сохраняем,
      // updatedAt НЕ трогаем — иначе сортировка «прыгает».
      final next = article.copyWith(
        pinned: existing.pinned,
        updatedAt: existing.updatedAt,
      );
      if (next.title != existing.title ||
          next.body != existing.body ||
          next.section != existing.section ||
          !_sameTags(next.tags, existing.tags) ||
          next.pinned != existing.pinned) {
        await box.put(article.id, next);
        changed = true;
      }
    }

    _seeded = true;
    if (changed) revision.value++;
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
        if (byDate != 0) return byDate;
        return a.id.compareTo(b.id);
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

  static Future<ArticleModel?> getById(String id) async {
    final box = await _articlesBox;
    return box.get(id);
  }

  static Future<void> save(ArticleModel article) async {
    final box = await _articlesBox;
    await box.put(article.id, article);
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

  static Future<void> togglePin(ArticleModel article) async {
    await save(article.copyWith(
      pinned: !article.pinned,
      updatedAt: article.updatedAt,
    ));
  }

  static Future<Map<ArticleSection, int>> counts() async {
    final all = await getAll();
    return {
      for (final s in ArticleSection.values)
        s: all.where((a) => a.section == s).length,
    };
  }

  static List<ArticleModel> getRoots() {
    final box = _box;
    if (box == null) return [];
    return box.values.where((a) => a.parentId == null).toList();
  }

  static List<ArticleModel> getChildren(String parentId) {
    final box = _box;
    if (box == null) return [];
    return box.values.where((a) => a.parentId == parentId).toList();
  }

  static bool hasChildren(String parentId) {
    final box = _box;
    if (box == null) return false;
    return box.values.any((a) => a.parentId == parentId);
  }

  static List<ArticleModel> getBreadcrumb(String articleId) {
    final box = _box;
    if (box == null) return [];
    final result = <ArticleModel>[];
    // Защита от петли в данных: если A лежит в B, а B — в A, этот цикл
    // крутился бы вечно и вешал экран намертво. Петлю на диске мог оставить
    // любой прежний билд, поэтому обход обязан быть устойчивым сам по себе,
    // а не только полагаться на проверку при выборе родителя.
    final seen = <String>{};
    var current = box.get(articleId);
    while (current != null && seen.add(current.id)) {
      result.insert(0, current);
      if (current.parentId == null) break;
      current = box.get(current.parentId);
    }
    return result;
  }

  /// Все потомки статьи, включая её саму — для проверки «не кладём папку
  /// внутрь самой себя».
  static Set<String> subtreeIds(String rootId) {
    final box = _box;
    if (box == null) return {rootId};
    final ids = <String>{rootId};
    var grew = true;
    // Обход волнами вместо рекурсии: на петле рекурсия переполнила бы стек,
    // а здесь множество просто перестаёт расти.
    while (grew) {
      grew = false;
      for (final a in box.values) {
        final p = a.parentId;
        if (p != null && ids.contains(p) && ids.add(a.id)) grew = true;
      }
    }
    return ids;
  }

  static List<ArticleModel> getSubtree(String rootId) {
    final box = _box;
    if (box == null) return [];
    final result = <ArticleModel>[];
    // seen — та же защита от петли: без него рекурсия переполняла бы стек.
    final seen = <String>{rootId};
    void collect(String pid) {
      final children = box.values.where((a) => a.parentId == pid).toList();
      for (final child in children) {
        if (!seen.add(child.id)) continue;
        result.add(child);
        collect(child.id);
      }
    }

    collect(rootId);
    return result;
  }
}
