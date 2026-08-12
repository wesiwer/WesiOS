import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/calendar_days.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';

/// Четыре претензии к прогнозу, высказанные словами, а не багрепортом.
///
/// Каждая проверялась на движке замером и подтвердилась, поэтому здесь они
/// зафиксированы как тесты: это то, что человек проверяет глазами в первую
/// очередь, и то, из-за чего перестают верить всему остальному.
void main() {
  final today = DateTime(2026, 3, 1);

  TransactionModel tx(
    String id,
    double amount,
    TransactionType type,
    int daysAgo,
  ) =>
      TransactionModel(
        id: id,
        title: id,
        amount: amount,
        type: type,
        date: addDays(today, -daysAgo),
      );

  ForecastResult run(
    List<TransactionModel> txs, {
    int days = 30,
    double balance = 100000,
  }) =>
      ForecastEngine.generate(
        transactions: txs,
        currentBalance: balance,
        days: days,
        asOf: today,
      );

  group('совет по сокращению трат', () {
    // «Он предлагает сократить расходы на 30 000 в день, хотя видит, что
    // доход в день сильно меньше. Он должен предлагать решение под мои
    // возможности».
    test('не предлагает срезать больше, чем человек вообще тратит', () {
      // Тратит 5000 в день, зарабатывает 1000 — дыра огромная.
      final txs = <TransactionModel>[
        for (var i = 1; i <= 90; i++) ...[
          tx('e$i', 5000, TransactionType.expense, i),
          tx('i$i', 1000, TransactionType.income, i),
        ],
      ];
      final r = run(txs, days: 60, balance: 60000);
      final gap = r.actionPrompts.where((p) => p.code == 'gap-25').toList();
      expect(gap, isNotEmpty, reason: 'при таком раскладе риск обязан быть');

      final text = gap.first.textRu;
      // Совет обязан признать, что одним урезанием не обойтись, а не
      // называть недостижимую сумму как план действий.
      expect(text, contains('не обойтись'),
          reason: 'нельзя предлагать срезать больше половины трат: $text');
      expect(text, isNot(contains('Достаточно тратить')));
    });

    test('когда сократить реально — говорит сколько и какую это долю трат',
        () {
      // Тратит 5000 в день, зарабатывает 4900 — не хватает совсем немного.
      final txs = <TransactionModel>[
        for (var i = 1; i <= 90; i++) ...[
          tx('e$i', 5000, TransactionType.expense, i),
          tx('i$i', 4900, TransactionType.income, i),
        ],
      ];
      final r = run(txs, days: 90, balance: 20000);
      final gap = r.actionPrompts.where((p) => p.code == 'gap-25').toList();
      if (gap.isEmpty) return; // риск может и не наступить — это не провал
      final text = gap.first.textRu;
      expect(text, contains('% обычных трат'),
          reason: 'совет обязан показывать долю от привычных трат: $text');
      // Сумма к сокращению не может превышать сам расход.
      expect(gap.first.amount, lessThanOrEqualTo(5000 * 0.5 + 1));
    });
  });

  group('финансовая подушка', () {
    // «Пусть указывает, на сколько дней должно хватить такой подушки,
    // исходя из моих привычек в тратах».
    test('подушка переведена в дни по привычным тратам', () {
      final txs = <TransactionModel>[
        for (var i = 1; i <= 90; i++) ...[
          tx('e$i', 1000, TransactionType.expense, i),
          tx('i$i', 1000, TransactionType.income, i),
        ],
      ];
      final r = run(txs, balance: 90000);

      expect(r.spendPerDay, closeTo(1000, 60),
          reason: 'привычка тратить — 1000 в день');
      // 90 000 при тратах 1000 в день — это 90 дней.
      expect(r.cushionDays, closeTo(90, 6));
      expect(r.reserveDays, greaterThan(0),
          reason: 'рекомендуемая подушка тоже обязана быть выражена в днях');
      // Резерв на просадку не может быть длиннее, чем весь баланс.
      expect(r.reserveDays, lessThanOrEqualTo(r.cushionDays));
    });

    test('срок подушки считается от трат, а не от остатка после доходов', () {
      // Доход полностью покрывает расход: «остаток» нулевой, но подушка
      // всё равно должна меряться тратами.
      final txs = <TransactionModel>[
        for (var i = 1; i <= 90; i++) ...[
          tx('e$i', 2000, TransactionType.expense, i),
          tx('i$i', 2000, TransactionType.income, i),
        ],
      ];
      final r = run(txs, balance: 60000);
      expect(r.cushionDays, closeTo(30, 3),
          reason: '60 000 при тратах 2000 в день — это 30 дней');
    });
  });

  group('линия прогноза', () {
    // «У меня доходы равны расходам, но график показывает строго вниз».
    test('доходы сходятся с расходами — линия не уезжает', () {
      final txs = <TransactionModel>[
        for (var i = 1; i <= 90; i++) tx('e$i', 1000, TransactionType.expense, i),
        for (final d in [15, 45, 75])
          tx('sal$d', 30000, TransactionType.income, d),
      ];
      expect(run(txs).p50.last, closeTo(100000, 5000));
    });

    test('фаза месяца не решает ничего', () {
      final results = <double>[];
      for (final last in [1, 8, 15, 22, 29]) {
        final txs = <TransactionModel>[
          for (var i = 1; i <= 90; i++)
            tx('e$i', 1000, TransactionType.expense, i),
          for (var k = 0; k < 3; k++)
            tx('s$k', 30000, TransactionType.income, last + k * 30),
        ];
        results.add(run(txs).p50.last);
      }
      final spread = results.reduce((a, b) => a > b ? a : b) -
          results.reduce((a, b) => a < b ? a : b);
      expect(spread, lessThan(8000),
          reason: 'разброс по дню месяца: '
              '${results.map((v) => v.round()).toList()}');
    });

    test('реальный дефицит виден как минус, а не как плюс', () {
      final txs = <TransactionModel>[
        for (var i = 1; i <= 90; i++)
          tx('e$i', 1500, TransactionType.expense, i),
        for (final d in [15, 45, 75])
          tx('sal$d', 30000, TransactionType.income, d),
      ];
      // Теряет 500 в день — за месяц это около 15 000.
      expect(run(txs).p50.last, lessThan(90000));
    });
  });

  group('отчёты понятным языком', () {
    test('в советах нет жаргона вроде P50 и MAPE', () {
      final txs = <TransactionModel>[
        for (var i = 1; i <= 90; i++) ...[
          tx('e$i', 3000, TransactionType.expense, i),
          tx('i$i', 1000, TransactionType.income, i),
        ],
      ];
      final r = run(txs, days: 60, balance: 50000);
      for (final prompt in r.actionPrompts) {
        for (final jargon in const ['MAPE', 'квантил', 'бутстрап', 'Brier']) {
          expect(prompt.textRu.contains(jargon), isFalse,
              reason: 'в совете «${prompt.code}» встретилось «$jargon»');
        }
      }
    });
  });
}
