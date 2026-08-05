import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/constants/app_version.dart';
import 'package:wesios/features/knowledge/data/builtin_articles.dart';
import 'package:wesios/features/knowledge/models/article_model.dart';

/// Встроенные статьи собираются конкатенацией строк в формат Delta.
/// Ошибка в этой сборке не ловится ни компилятором, ни анализатором —
/// она видна только в редакторе, и то как «текст выглядит неправильно».
void main() {
  for (final ru in [true, false]) {
    final label = ru ? 'русские' : 'английские';

    group('$label встроенные статьи', () {
      final articles = BuiltinArticles.all(ru);

      test('их вообще много и они не пустые', () {
        expect(articles.length, greaterThan(10));
      });

      test('тело каждой статьи — валидный JSON-массив операций', () {
        for (final a in articles) {
          if (a.isFolder && a.body.isEmpty) continue;
          Object? decoded;
          expect(
            () => decoded = jsonDecode(a.body),
            returnsNormally,
            reason: 'статья «${a.title}» (${a.id}) — тело не разбирается',
          );
          expect(decoded, isA<List>(), reason: a.id);
        }
      });

      test('в каждой операции есть insert', () {
        for (final a in articles) {
          if (a.isFolder && a.body.isEmpty) continue;
          for (final op in jsonDecode(a.body) as List) {
            expect(op, isA<Map>(), reason: a.id);
            expect((op as Map).containsKey('insert'), isTrue,
                reason: 'операция без insert в «${a.title}»');
          }
        }
      });

      test('атрибуты блока стоят на переводе строки, а не на тексте', () {
        // Это и есть та ошибка, из-за которой заголовки и списки в статьях
        // выглядели неправильно: header/list висели на самом тексте.
        for (final a in articles) {
          if (a.isFolder && a.body.isEmpty) continue;
          for (final op in jsonDecode(a.body) as List) {
            final attrs = (op as Map)['attributes'];
            if (attrs is! Map) continue;
            final isBlockAttr =
                attrs.containsKey('header') || attrs.containsKey('list');
            if (!isBlockAttr) continue;
            expect(op['insert'], '\n',
                reason: 'в «${a.title}» атрибут блока ${attrs.keys.toList()} '
                    'стоит на тексте «${op['insert']}», а не на переводе строки');
          }
        }
      });

      test('текст статьи читается, а не выглядит как JSON', () {
        for (final a in articles) {
          if (a.isFolder && a.body.isEmpty) continue;
          final text = a.plainText;
          expect(text.contains('"insert"'), isFalse,
              reason: 'в «${a.title}» разметка попала в текст');
          expect(text.trim(), isNotEmpty, reason: a.id);
        }
      });

      test('версия в статье «О программе» не захардкожена в прошлое', () {
        final about = articles.firstWhere((a) => a.id == 'wesios_about');
        // Совпадает с версией приложения — иначе справка врёт о самой себе.
        expect(about.plainText, contains(AppVersionProbe.display));
      });

      test('у каждой статьи есть заголовок', () {
        for (final a in articles) {
          expect(a.title.trim(), isNotEmpty, reason: a.id);
        }
      });

      test('parentId ссылается на существующую статью', () {
        final ids = {for (final a in articles) a.id};
        for (final a in articles) {
          final p = a.parentId;
          if (p == null) continue;
          expect(ids.contains(p), isTrue,
              reason: '«${a.title}» ссылается на несуществующего родителя $p');
        }
      });

      test('в дереве нет петель', () {
        final byId = {for (final a in articles) a.id: a};
        for (final a in articles) {
          final seen = <String>{};
          ArticleModel? cur = a;
          while (cur != null) {
            expect(seen.add(cur.id), isTrue,
                reason: 'петля в предках у «${a.title}»');
            final p = cur.parentId;
            cur = p == null ? null : byId[p];
          }
        }
      });
    });
  }
}

/// Версия берётся из самого приложения.
///
/// Здесь стояла копия строки — «чтобы тест не зависел от пути импорта».
/// Получилось ровно обратное тому, что тест проверяет: копию надо было
/// править при каждом поднятии версии, и до тех пор набор падал. Тест с
/// названием «версия не захардкожена в прошлое» сам держал версию
/// захардкоженной в прошлом.
///
/// Теперь источник один. Если справка начнёт врать о версии — упадёт;
/// если версию просто подняли — нет.
class AppVersionProbe {
  static const String display = AppVersion.display;
}
