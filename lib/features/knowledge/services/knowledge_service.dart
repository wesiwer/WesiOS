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

  static Future<Box<ArticleModel>> get _articlesBox async {
    _box ??= await Hive.openBox<ArticleModel>(_boxName);
    return _box!;
  }

  /// Записывает встроенные статьи поверх сохранённых.
  ///
  /// Именно перезаписывает: справка должна обновляться вместе с приложением,
  /// иначе описание останется от версии, которой уже нет. Пользовательские
  /// статьи (`builtIn == false`) не трогаются никогда.
  static Future<void> seed() async {
    final box = await _articlesBox;
    for (final article in BuiltinArticles.all(WesiLocale.isRussian)) {
      final existing = box.get(article.id);
      // Закрепление — единственное, что пользователь мог поменять у
      // встроенной статьи; его сохраняем.
      await box.put(
        article.id,
        existing == null
            ? article
            : article.copyWith(pinned: existing.pinned),
      );
    }
    revision.value++;
  }

  static Future<List<ArticleModel>> getAll() async {
    final box = await _articlesBox;
    final list = box.values.toList()
      // Закреплённые сверху, дальше — по дате изменения: свежее выше.
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
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
    await save(article.copyWith(pinned: !article.pinned));
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
