import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/knowledge/models/article_model.dart';

ArticleModel article(String body) => ArticleModel(
      id: 'a',
      title: 'Заголовок',
      body: body,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  group('plainText: тело редактора (Delta Quill)', () {
    test('достаёт текст из Delta, а не показывает JSON', () {
      final body = jsonEncode([
        {'insert': 'Привет, '},
        {
          'insert': 'мир',
          'attributes': {'bold': true}
        },
        {'insert': '\n'},
      ]);
      expect(article(body).plainText, 'Привет, мир');
    });

    test('кавычки внутри текста не ломают разбор', () {
      // Ровно тот случай, на котором падало прежнее регулярное выражение.
      final body = jsonEncode([
        {'insert': 'Он сказал "да" и ушёл\n'},
      ]);
      expect(article(body).plainText, 'Он сказал "да" и ушёл');
    });

    test('обратный слэш внутри текста не ломает разбор', () {
      final body = jsonEncode([
        {'insert': r'путь C:\Windows\System32' '\n'},
      ]);
      expect(article(body).plainText, r'путь C:\Windows\System32');
    });

    test('переводы строк остаются переводами строк', () {
      final body = jsonEncode([
        {'insert': 'Первая\nВторая\n'},
      ]);
      expect(article(body).plainText, 'Первая\nВторая');
    });

    test('вставки-объекты (картинки) в текст не попадают', () {
      final body = jsonEncode([
        {'insert': 'до '},
        {
          'insert': {'image': 'data:image/png;base64,AAAA'}
        },
        {'insert': ' после\n'},
      ]);
      expect(article(body).plainText, 'до  после');
    });

    test('обычный текст остаётся собой', () {
      expect(article('Просто текст').plainText, 'Просто текст');
    });

    test('текст, начинающийся со скобки, не считается Delta', () {
      const body = '[важно] прочитать до конца';
      expect(article(body).plainText, body);
    });

    test('битый JSON возвращает тело как есть, а не пустоту', () {
      const body = '[{"insert": ';
      expect(article(body).plainText, body);
    });
  });

  group('excerpt', () {
    test('не показывает служебные слова Delta', () {
      final body = jsonEncode([
        {'insert': 'Регламент выдачи доступов\n'},
      ]);
      final e = article(body).excerpt;
      expect(e, 'Регламент выдачи доступов');
      expect(e.contains('insert'), isFalse);
      expect(e.contains('{'), isFalse);
    });

    test('обрезает длинный текст многоточием', () {
      final body = jsonEncode([
        {'insert': 'я' * 300},
      ]);
      final e = article(body).excerpt;
      expect(e.length, 141); // 140 знаков + многоточие
      expect(e.endsWith('…'), isTrue);
    });

    test('схлопывает переводы строк в пробелы', () {
      final body = jsonEncode([
        {'insert': 'Первая\n\nВторая\n'},
      ]);
      expect(article(body).excerpt, 'Первая Вторая');
    });
  });

  group('matches: поиск', () {
    test('находит слово внутри Delta-тела', () {
      final body = jsonEncode([
        {'insert': 'Порядок согласования отпуска\n'},
      ]);
      expect(article(body).matches('отпуска'), isTrue);
    });

    test('не находит служебные слова разметки', () {
      // Поиск по сырому JSON находил бы «insert» в любой статье подряд.
      final body = jsonEncode([
        {'insert': 'Текст без этого слова\n'},
      ]);
      expect(article(body).matches('insert'), isFalse);
    });

    test('пустой запрос подходит всем', () {
      expect(article('что угодно').matches('   '), isTrue);
    });
  });
}
