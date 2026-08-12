import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/calendar_days.dart';
import 'package:wesios/features/treasury/services/financial_advice.dart';
import 'package:wesios/features/treasury/services/financial_health.dart';

/// Подушка и советы. Проверяется главное: числа считаются от того, о чём
/// говорит подпись, и приложение не предлагает невыполнимого.
void main() {
  final now = DateTime(2026, 3, 1);

  TransactionModel tx(String id, double amount, TransactionType type, int daysAgo,
          {String? category}) =>
      TransactionModel(
        id: id,
        title: id,
        amount: amount,
        type: type,
        date: addDays(now, -daysAgo),
        category: category,
      );

  /// 30 дней: доход [income] и расход [expense] каждый день.
  List<TransactionModel> daily(double income, double expense,
      {String category = 'Еда'}) {
    final out = <TransactionModel>[];
    for (var i = 0; i < 30; i++) {
      if (income > 0) {
        out.add(tx('i$i', income, TransactionType.income, i));
      }
      if (expense > 0) {
        out.add(tx('e$i', expense, TransactionType.expense, i,
            category: category));
      }
    }
    return out;
  }

  group('подушка', () {
    test('дни считаются от привычных трат, а не от остатка', () {
      // Тратим 1000 в день, зарабатываем 900. Отложено 30 000.
      final h = FinancialHealth.compute(
        transactions: daily(900, 1000),
        balance: 30000,
        now: now,
      );
      // Без дохода 30 000 при тратах 1000/день — это ровно 30 дней.
      expect(h.cushionDays, 30);
      expect(h.spendPerDay, 1000);
      // А «запас хода» при нынешнем раскладе — другое число: теряем по 100
      // в день, значит хватит на 300 дней.
      expect(h.runwayDays, 300);
    });

    test('число дней и подпись под ним сходятся между собой', () {
      final h = FinancialHealth.compute(
        transactions: daily(0, 500),
        balance: 25000,
        now: now,
      );
      expect(h.cushionDays! * h.spendPerDay, closeTo(h.cushion, 500));
    });

    test('норма — три месяца трат', () {
      final h = FinancialHealth.compute(
        transactions: daily(0, 1000),
        balance: 0,
        now: now,
      );
      expect(h.targetDays, 90);
      expect(h.targetAmount, 90000);
      expect(h.gap, 90000);
    });

    test('норма набрана — недостачи нет', () {
      final h = FinancialHealth.compute(
        transactions: daily(2000, 1000),
        balance: 200000,
        now: now,
      );
      expect(h.targetReached, isTrue);
      expect(h.gap, 0);
    });
  });

  group('советы по силам', () {
    final ru = const FinancialAdviceBuilder(ru: true);

    test('не предлагает урезать больше половины трат', () {
      // Зарабатываем 1000 в день, тратим 30 000 — разрыв больше самих трат
      // урезать невозможно.
      final h = FinancialHealth.compute(
        transactions: daily(1000, 30000),
        balance: 100000,
        now: now,
      );
      expect(h.feasibility, CutFeasibility.impossible);

      final advice = ru.nextStep(h);
      expect(advice.headline, contains('не обойтись'));
      expect(advice.action, contains('доход'),
          reason: 'если урезанием не выйти, совет обязан говорить про доход');
    });

    test('небольшой разрыв подаётся как выполнимый', () {
      // Тратим 1000, зарабатываем 900: урезать нужно 10% трат.
      final h = FinancialHealth.compute(
        transactions: daily(900, 1000),
        balance: 50000,
        now: now,
      );
      expect(h.feasibility, CutFeasibility.realistic);
      expect(h.cutPerDayNeeded, closeTo(100, 0.01));

      final advice = ru.nextStep(h);
      expect(advice.headline, contains('меньше'));
      expect(advice.alarming, isFalse);
    });

    test('когда деньги остаются, речи об урезании нет', () {
      final h = FinancialHealth.compute(
        transactions: daily(2000, 1000),
        balance: 10000,
        now: now,
      );
      expect(h.feasibility, CutFeasibility.notNeeded);
      final advice = ru.nextStep(h);
      expect(advice.alarming, isFalse);
      expect(advice.headline, isNot(contains('меньше')));
    });

    test('называет самую крупную статью расходов', () {
      final txs = [
        ...daily(500, 200, category: 'Еда'),
        for (var i = 0; i < 30; i++)
          tx('r$i', 800, TransactionType.expense, i, category: 'Аренда'),
      ];
      final h = FinancialHealth.compute(
        transactions: txs,
        balance: 20000,
        now: now,
      );
      expect(h.biggest!.category, 'Аренда');
      expect(ru.nextStep(h).action, contains('Аренда'));
    });

    test('в совете нет статистического жаргона', () {
      final h = FinancialHealth.compute(
        transactions: daily(900, 1000),
        balance: 50000,
        now: now,
      );
      final text = [
        ru.cushion(h).headline,
        ru.cushion(h).detail,
        ru.nextStep(h).headline,
        ru.nextStep(h).detail,
      ].join(' ').toLowerCase();
      for (final word in [
        'перцентил',
        'квантил',
        'волатильн',
        'monte',
        'p10',
        'p50',
        'горизонт',
        'дисконт',
      ]) {
        expect(text.contains(word), isFalse, reason: 'слово «$word» в совете');
      }
    });
  });
}
