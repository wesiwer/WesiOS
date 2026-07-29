import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/data/wesi_quotes.dart';

void main() {
  group('WesiQuotes', () {
    test('every quote has both languages filled in', () {
      for (final q in WesiQuotes.all) {
        expect(q.ru.trim(), isNotEmpty, reason: 'empty ru: ${q.en}');
        expect(q.en.trim(), isNotEmpty, reason: 'empty en: ${q.ru}');
      }
    });

    test('there are no duplicate quotes', () {
      final ru = WesiQuotes.all.map((q) => q.ru).toSet();
      expect(ru.length, WesiQuotes.all.length);
    });

    test('no near-duplicates either — two phrases differing only by ё/е, '
        'case or punctuation read as the same quote to a human, and the '
        'exact-match check above would let them both through', () {
      final seen = <String>{};
      final dupes = <String>[];
      for (final q in WesiQuotes.all) {
        final key = q.ru
            .toLowerCase()
            .replaceAll('ё', 'е')
            .replaceAll(RegExp(r'[^\wа-я\s]'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (!seen.add(key)) dupes.add(q.ru);
      }
      expect(dupes, isEmpty, reason: 'near-duplicates: ${dupes.take(5)}');
    });

    test('the pool is large enough that a given quote is rare', () {
      // Смысл фичи — «чтобы не надоедали». Небольшой список сводит идею на нет.
      expect(WesiQuotes.all.length, greaterThanOrEqualTo(1000));
    });

    test('walks the entire pool before repeating — the stride must stay '
        'coprime with the list length, otherwise the rotation collapses '
        'onto a small subset no matter how many quotes exist', () {
      final seen = <String>{};
      var t = DateTime(2026, 1, 1);
      for (int i = 0; i < WesiQuotes.all.length; i++) {
        seen.add(WesiQuotes.current(now: t).ru);
        t = t.add(const Duration(hours: 6));
      }
      expect(seen.length, WesiQuotes.all.length);
    });

    test('stays stable within one slot — the screen must not reshuffle the '
        'quote on every rebuild', () {
      final a = WesiQuotes.current(now: DateTime(2026, 7, 28, 10, 0));
      final b = WesiQuotes.current(now: DateTime(2026, 7, 28, 10, 59));
      expect(a.ru, b.ru);
    });

    test('changes between slots within the same day', () {
      final morning = WesiQuotes.current(now: DateTime(2026, 7, 28, 2));
      final noon = WesiQuotes.current(now: DateTime(2026, 7, 28, 8));
      final evening = WesiQuotes.current(now: DateTime(2026, 7, 28, 14));
      final night = WesiQuotes.current(now: DateTime(2026, 7, 28, 20));

      expect({morning.ru, noon.ru, evening.ru, night.ru}.length, 4);
    });

    test('changes from one day to the next', () {
      final today = WesiQuotes.current(now: DateTime(2026, 7, 28, 10));
      final tomorrow = WesiQuotes.current(now: DateTime(2026, 7, 29, 10));
      expect(today.ru, isNot(tomorrow.ru));
    });

    test('does not repeat across a long run of consecutive slots — the '
        'stepping must not collapse into a short cycle', () {
      final seen = <String>[];
      var t = DateTime(2026, 1, 1, 0);
      // 40 подряд идущих слотов = 10 дней.
      for (int i = 0; i < 40; i++) {
        seen.add(WesiQuotes.current(now: t).ru);
        t = t.add(const Duration(hours: 6));
      }
      // Ждём именно уникальности: при вырожденном шаге здесь были бы повторы
      // задолго до исчерпания списка.
      expect(seen.toSet().length, seen.length);
    });

    test('every slot maps into the pool — no out-of-range index for a full '
        'year of slots', () {
      var t = DateTime(2026, 1, 1);
      for (int i = 0; i < 365 * WesiQuotes.slotsPerDay; i++) {
        expect(() => WesiQuotes.current(now: t), returnsNormally);
        t = t.add(const Duration(hours: 6));
      }
    });
  });
}
