import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/home/services/global_search_service.dart';
import 'package:wesios/features/knowledge/models/article_model.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/treasury/models/account_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';

void main() {
  final now = DateTime(2026, 7, 1);

  TransactionModel tx(String title, {String? category, String? description}) =>
      TransactionModel(
        id: title,
        title: title,
        amount: 100,
        type: TransactionType.expense,
        date: now,
        category: category,
        description: description,
      );

  TaskModel task(String title, {List<String> tags = const []}) => TaskModel(
        id: title,
        title: title,
        createdAt: now,
        tags: tags,
      );

  ArticleModel article(String title, {String body = ''}) => ArticleModel(
        id: title,
        title: title,
        body: body,
        createdAt: now,
        updatedAt: now,
      );

  group('нормализация', () {
    test('регистр и «ё» не мешают попасть в цель', () {
      expect(GlobalSearchService.normalize('  УчЁт  '), 'учет');
    });

    test('запрос короче двух символов ничего не ищет — иначе на одну букву '
        'вываливалась бы вся база', () {
      final hits = GlobalSearchService.search(
        query: 'а',
        tasks: [task('аренда')],
      );
      expect(hits, isEmpty);
    });
  });

  group('ранжирование', () {
    test('точное совпадение выше вхождения в середину', () {
      final hits = GlobalSearchService.search(
        query: 'аренда',
        transactions: [
          tx('Доплата за аренду склада'),
          tx('Аренда'),
        ],
      );
      expect(hits.first.title, 'Аренда');
    });

    test('совпадение с начала названия выше совпадения в описании', () {
      final hits = GlobalSearchService.search(
        query: 'подписк',
        transactions: [
          tx('Хостинг', description: 'годовая подписка'),
          tx('Подписка Figma'),
        ],
      );
      expect(hits.first.title, 'Подписка Figma');
    });

    test('порядок при равном счёте устойчив, а не случаен', () {
      List<String> run() => GlobalSearchService.search(
            query: 'налог',
            transactions: [tx('Налог Б'), tx('Налог А')],
          ).map((h) => h.title).toList();

      expect(run(), ['Налог А', 'Налог Б']);
      expect(run(), run());
    });
  });

  group('источники', () {
    test('раздел находится по слову из его описания, а не только по имени', () {
      final hits = GlobalSearchService.search(query: 'песочниц');
      expect(hits.any((h) => h.route == '/treasury/sandbox'), isTrue);
    });

    test('Wesi Shield ищется и по-русски, и по-английски', () {
      for (final q in ['защит', 'shield']) {
        final hits = GlobalSearchService.search(query: q);
        expect(hits.any((h) => h.route == '/shield'), isTrue, reason: q);
      }
    });

    test('задача находится по тегу', () {
      final hits = GlobalSearchService.search(
        query: 'срочно',
        tasks: [task('Позвонить в банк', tags: ['срочно'])],
      );
      expect(hits.single.title, 'Позвонить в банк');
      expect(hits.single.kind, SearchKind.task);
    });

    test('статья находится по тексту, а не только по заголовку', () {
      final hits = GlobalSearchService.search(
        query: 'кассовый разрыв',
        articles: [article('Как читать прогноз', body: 'Кассовый разрыв — это')],
      );
      expect(hits.any((h) => h.kind == SearchKind.article), isTrue);
    });

    test('счёт находится по названию', () {
      final hits = GlobalSearchService.search(
        query: 'резерв',
        accounts: [
          AccountModel(id: 'r', name: 'Резерв', createdAt: now),
        ],
      );
      expect(hits.single.kind, SearchKind.account);
    });

    test('каждый результат ведёт на существующий маршрут', () {
      final hits = GlobalSearchService.search(
        query: 'а',
        tasks: [task('аренда')],
      );
      for (final h in hits) {
        expect(h.route.startsWith('/'), isTrue);
      }
    });
  });

  group('ограничение выдачи', () {
    test('лимит общий, а не по источникам: точная задача не вытесняется '
        'сотней подходящих операций', () {
      final hits = GlobalSearchService.search(
        query: 'оплата',
        transactions: [
          for (var i = 0; i < 100; i++) tx('Частичная оплата $i'),
        ],
        tasks: [task('Оплата')],
        limit: 5,
      );
      expect(hits.length, 5);
      expect(hits.first.title, 'Оплата');
    });
  });
}
