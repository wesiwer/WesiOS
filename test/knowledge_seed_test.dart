import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/knowledge/data/builtin_articles.dart';
import 'package:wesios/features/knowledge/models/article_model.dart';
import 'package:wesios/features/knowledge/services/knowledge_service.dart';

/// Посев встроенных статей.
///
/// Раньше он умел только добавлять. Это значит, что справку нельзя было
/// переписать: на устройстве, где приложение уже стояло, старые статьи
/// оставались рядом с новыми навсегда — удалить их руками нельзя, встроенные
/// не удаляются намеренно.
void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('wesios_knowledge');
    Hive.init(dir.path);
    Hive.registerAdapter(ArticleSectionAdapter());
    Hive.registerAdapter(ArticleModelAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    final box = await Hive.openBox<ArticleModel>('wesios_knowledge');
    await box.clear();
  });

  ArticleModel record(
    String id, {
    required bool builtIn,
    String? parentId,
    bool isFolder = false,
  }) =>
      ArticleModel(
        id: id,
        title: id,
        body: '',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        builtIn: builtIn,
        parentId: parentId,
        isFolder: isFolder,
      );

  test('встроенные статьи появляются', () async {
    await KnowledgeService.seed(force: true);
    final all = await KnowledgeService.getAll();
    final ids = {for (final a in all) a.id};
    for (final a in BuiltinArticles.all(true)) {
      expect(ids.contains(a.id), isTrue, reason: a.id);
    }
  });

  test('исчезнувшая встроенная статья убирается', () async {
    final box = Hive.box<ArticleModel>('wesios_knowledge');
    await box.put('wesios_treasury_article',
        record('wesios_treasury_article', builtIn: true));

    await KnowledgeService.seed(force: true);

    expect(box.get('wesios_treasury_article'), isNull,
        reason: 'иначе человек видит две справки сразу и не знает, какая '
            'настоящая');
  });

  test('пользовательская статья не трогается', () async {
    final box = Hive.box<ArticleModel>('wesios_knowledge');
    await box.put('mine', record('mine', builtIn: false));

    await KnowledgeService.seed(force: true);

    expect(box.get('mine'), isNotNull);
  });

  test('статья из удалённой папки поднимается в корень', () async {
    // Самый неприятный случай: запись цела, но пути к ней нет — папка,
    // в которой она лежала, исчезла вместе со старой справкой. В дереве её
    // не видно, и найти можно только поиском.
    final box = Hive.box<ArticleModel>('wesios_knowledge');
    await box.put(
        'wesios_money', record('wesios_money', builtIn: true, isFolder: true));
    await box.put('mine',
        record('mine', builtIn: false, parentId: 'wesios_money'));

    await KnowledgeService.seed(force: true);

    expect(box.get('wesios_money'), isNull);
    expect(box.get('mine')!.parentId, isNull);
    expect(KnowledgeService.getRoots().any((a) => a.id == 'mine'), isTrue);
  });

  test('соседи по папке идут в заданном порядке, а не по алфавиту', () async {
    await KnowledgeService.seed(force: true);

    final children = KnowledgeService.getChildren('kb_start');
    expect(children, isNotEmpty);
    expect([for (final a in children) a.id].first, 'kb_start_what',
        reason: 'по алфавиту первым был бы другой');

    final orders = [for (final a in children) a.order];
    final sorted = [...orders]..sort();
    expect(orders, sorted);
  });

  test('корни идут в заданном порядке и начинаются с «Начала»', () async {
    await KnowledgeService.seed(force: true);
    final roots = KnowledgeService.getRoots();
    expect(roots.first.id, 'kb_start');
    expect([for (final a in roots) a.id],
        ['kb_start', 'kb_modules', 'kb_money', 'kb_work', 'kb_life']);
  });
}
