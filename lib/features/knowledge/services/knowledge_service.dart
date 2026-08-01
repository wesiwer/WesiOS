import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/localization/wesi_locale.dart';
import '../data/builtin_articles.dart';
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
  ///
  /// Раньше seed() вызывался из _load() при каждом открытии списка и всегда
  /// делал revision++ → listener → _load → seed → бесконечный цикл, из-за
  /// которого карточки «дёргались» и менялись местами после выхода из
  /// закреплённой статьи.
  static Future<void> seed({bool force = false}) async {
    if (_seeded && !force) return;
    final box = await _articlesBox;
    var changed = false;

    for (final article in BuiltinArticles.all(WesiLocale.isRussian)) {
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
      // Закреплённые сверху, дальше — по дате изменения: свежее выше.
      // При равных updatedAt — стабильный порядок по id.
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
    );
    await save(article);
    return article;
  }

  /// Удаляет статью. Встроенную удалить нельзя: восстановить её было бы
  /// нечем, а исчезнувшая справка — худший вид пропажи.
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

  /// Сколько статей в каждом разделе — для подписей на фильтрах.
  static Future<Map<ArticleSection, int>> counts() async {
    final all = await getAll();
    return {
      for (final s in ArticleSection.values)
        s: all.where((a) => a.section == s).length,
    };
  }
}
