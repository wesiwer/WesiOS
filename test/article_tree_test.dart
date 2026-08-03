import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/knowledge/models/article_model.dart';

ArticleModel article({
  String id = 'a',
  String? parentId,
  bool isFolder = false,
}) =>
    ArticleModel(
      id: id,
      title: id,
      body: '',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      parentId: parentId,
      isFolder: isFolder,
    );

void main() {
  group('copyWith и родительская папка', () {
    test('перенос в другую папку работает', () {
      final a = article(parentId: 'folder-1');
      expect(a.copyWith(parentId: 'folder-2').parentId, 'folder-2');
    });

    test('перенос В КОРЕНЬ работает', () {
      // Главный случай. С `parentId ?? this.parentId` статью можно было
      // положить в папку, но нельзя вынуть: выбор «в корень» даёт null, и
      // copyWith молча возвращал прежнего родителя.
      final a = article(parentId: 'folder-1');
      expect(a.copyWith(parentId: null).parentId, isNull);
    });

    test('не передали parentId — родитель не меняется', () {
      final a = article(parentId: 'folder-1');
      expect(a.copyWith(title: 'Новое имя').parentId, 'folder-1');
    });

    test('статья из корня остаётся в корне, если поле не трогали', () {
      final a = article();
      expect(a.copyWith(body: 'текст').parentId, isNull);
    });

    test('остальные поля переносятся как прежде', () {
      final a = article(id: 'x', parentId: 'p', isFolder: true);
      final b = a.copyWith(title: 'Т', pinned: true);
      expect(b.id, 'x');
      expect(b.title, 'Т');
      expect(b.pinned, isTrue);
      expect(b.isFolder, isTrue);
      expect(b.parentId, 'p');
      expect(b.createdAt, a.createdAt);
    });
  });
}
