import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/forecast_backtest.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';

final DateTime today = DateTime(2026, 8, 3);

TransactionModel tx(
  DateTime date,
  double amount, {
  TransactionType type = TransactionType.income,
  String? id,
}) =>
    TransactionModel(
      id: id ?? '${date.toIso8601String()}_${amount}_${type.name}',
      title: 't',
      amount: amount,
      type: type,
      date: date,
    );

/// Ровный ряд: каждый день +1000 дохода и −600 расхода, итого +400/день.
List<TransactionModel> steadyHistory({required int days}) {
  final list = <TransactionModel>[];
  for (var i = days; i >= 0; i--) {
    final d = today.subtract(Duration(days: i));
    list.add(tx(d, 1000, id: 'inc_$i'));
    list.add(tx(d, 600, type: TransactionType.expense, id: 'exp_$i'));
  }
  return list;
}

void main() {
  group('balanceOn — восстановление баланса назад', () {
    test('на сегодня равен текущему балансу', () {
      final history = steadyHistory(days: 10);
      expect(
        ForecastBacktest.balanceOn(today, history, 100000),
        closeTo(100000, 0.001),
      );
    });

    test('вчера меньше на дневное нетто', () {
      final history = steadyHistory(days: 10);
      final yesterday = today.subtract(const Duration(days: 1));
      // За сегодня было +1000 −600 = +400, значит вчера баланс был на 400 ниже.
      expect(
        ForecastBacktest.balanceOn(yesterday, history, 100000),
        closeTo(100000 - 400, 0.001),
      );
    });

    test('до начала истории — баланс за вычетом всего оборота', () {
      final history = steadyHistory(days: 10); // 11 дней по +400
      final before = today.subtract(const Duration(days: 30));
      expect(
        ForecastBacktest.balanceOn(before, history, 100000),
        closeTo(100000 - 400 * 11, 0.001),
      );
    });

    test('операции ровно в этот день уже учтены', () {
      final d = today.subtract(const Duration(days: 5));
      final history = [
        tx(today.subtract(const Duration(days: 6)), 100),
        tx(d, 500),
        tx(today.subtract(const Duration(days: 4)), 700),
      ];
      // Позже дня d была только одна операция на 700.
      expect(
        ForecastBacktest.balanceOn(d, history, 10000),
        closeTo(10000 - 700, 0.001),
      );
    });
  });

  group('отказ считать, когда считать нечем', () {
    test('пустая история', () {
      final r = ForecastBacktest.run(
          transactions: const [], currentBalance: 0, now: today);
      expect(r.insufficientData, isTrue);
      expect(r.points, isEmpty);
    });

    test('меньше трёх операций', () {
      final r = ForecastBacktest.run(
        transactions: [tx(today.subtract(const Duration(days: 40)), 100)],
        currentBalance: 1000,
        now: today,
      );
      expect(r.insufficientData, isTrue);
    });

    test('вся история ПОСЛЕ точки отсчёта — проверять нечего', () {
      // Горизонт 30 дней, а данные только за последнюю неделю: на дату
      // отсчёта прогнозу было не на чем строиться.
      final r = ForecastBacktest.run(
        transactions: steadyHistory(days: 6),
        currentBalance: 10000,
        horizonDays: 30,
        now: today,
      );
      expect(r.insufficientData, isTrue);
    });

    test('истории до точки отсчёта меньше трёх недель', () {
      // 30 дней всего, горизонт 30 → до asOf не остаётся ничего.
      final r = ForecastBacktest.run(
        transactions: steadyHistory(days: 32),
        currentBalance: 10000,
        horizonDays: 30,
        now: today,
      );
      expect(r.insufficientData, isTrue);
    });

    test('нулевой горизонт', () {
      final r = ForecastBacktest.run(
        transactions: steadyHistory(days: 120),
        currentBalance: 10000,
        horizonDays: 0,
        now: today,
      );
      expect(r.insufficientData, isTrue);
    });
  });

  group('ровный ряд — прогноз обязан попасть', () {
    late BacktestResult result;

    setUp(() {
      result = ForecastBacktest.run(
        transactions: steadyHistory(days: 120),
        currentBalance: 200000,
        horizonDays: 30,
        now: today,
      );
    });

    test('проверка состоялась', () {
      expect(result.insufficientData, isFalse);
      expect(result.points.length, 30);
    });

    test('точка отсчёта — ровно горизонт назад', () {
      expect(result.asOf, today.subtract(const Duration(days: 30)));
    });

    test('дни идут подряд, начиная со следующего за точкой отсчёта', () {
      expect(result.points.first.date,
          result.asOf.add(const Duration(days: 1)));
      for (var i = 1; i < result.points.length; i++) {
        expect(
          result.points[i].date.difference(result.points[i - 1].date).inDays,
          1,
        );
      }
    });

    test('на ровных данных коридор накрывает почти всё', () {
      // Нетто каждый день одинаковое, разброса нет — прогноз обязан быть
      // точным. Если это не так, сломан сам движок, а не проверка.
      expect(result.coverage, greaterThan(0.8));
    });

    test('систематического перекоса нет', () {
      // bias измеряется в рублях; сравниваем с масштабом дневного нетто.
      expect(result.bias.abs(), lessThan(400 * 3));
    });

    test('ошибка в процентах посчитана и мала', () {
      expect(result.mape, isNotNull);
      expect(result.mape!, lessThan(10));
    });

    test('оценка — «хорошо»', () {
      expect(result.grade, BacktestGrade.good);
    });
  });

  group('арифметика показателей', () {
    test('error и inBand считаются от P50 и коридора', () {
      final p = BacktestPoint(
        date: _d,
        actual: 120,
        p10: 100,
        p50: 110,
        p90: 130,
      );
      expect(p.error, closeTo(10, 0.001));
      expect(p.inBand, isTrue);
    });

    test('факт вне коридора не засчитывается', () {
      final p = BacktestPoint(
          date: _d, actual: 90, p10: 100, p50: 110, p90: 130);
      expect(p.inBand, isFalse);
      expect(p.error, closeTo(-20, 0.001));
    });

    test('границы коридора считаются попаданием', () {
      final low =
          BacktestPoint(date: _d, actual: 100, p10: 100, p50: 110, p90: 130);
      final high =
          BacktestPoint(date: _d, actual: 130, p10: 100, p50: 110, p90: 130);
      expect(low.inBand, isTrue);
      expect(high.inBand, isTrue);
    });
  });

  group('оценка по коридору', () {
    BacktestResult withCoverage(double c) => BacktestResult(
          points: const [],
          asOf: _d,
          horizonDays: 30,
          mae: 0,
          mape: null,
          coverage: c,
          bias: 0,
        );

    test('обещанные 80% и выше — хорошо', () {
      expect(withCoverage(0.80).grade, BacktestGrade.good);
      expect(withCoverage(0.72).grade, BacktestGrade.good);
    });

    test('перебор не порок: накрыть всё — тоже хорошо', () {
      // На ровных данных коридор законно накрывает 100% дней. Считать это
      // недостатком было бы неправдой — прогноз просто не ошибся.
      expect(withCoverage(1.0).grade, BacktestGrade.good);
      expect(withCoverage(0.95).grade, BacktestGrade.good);
    });

    test('заметный недобор — средне', () {
      expect(withCoverage(0.60).grade, BacktestGrade.fair);
      expect(withCoverage(0.50).grade, BacktestGrade.fair);
    });

    test('коридор почти ничего не накрыл — плохо', () {
      // Прогноз самоуверен: обещал 80%, попал в 20%.
      expect(withCoverage(0.2).grade, BacktestGrade.poor);
      expect(withCoverage(0.0).grade, BacktestGrade.poor);
    });

    test('без данных оценки нет', () {
      expect(BacktestResult.empty(_d, 30).grade, BacktestGrade.unknown);
    });
  });

  group('движок умеет считать «на дату»', () {
    test('asOf сдвигает точку отсчёта прогноза', () {
      final history = steadyHistory(days: 120);
      final asOf = today.subtract(const Duration(days: 30));

      final past =
          history.where((t) => !t.date.isAfter(asOf)).toList();
      final a = ForecastEngine.generate(
        transactions: past,
        currentBalance: 100000,
        days: 10,
        asOf: asOf,
      );
      // Тот же вызов без asOf видит те же операции как «старые»: между
      // последней операцией и сегодня зияет месяц пустоты, и оценка тренда
      // получается другой. Достаточно того, что результаты различаются —
      // это и доказывает, что параметр действительно работает.
      final b = ForecastEngine.generate(
        transactions: past,
        currentBalance: 100000,
        days: 10,
      );
      expect(a.p50.isNotEmpty, isTrue);
      expect(a.historyDaysSpan, isNot(equals(b.historyDaysSpan)));
    });

    test('без asOf поведение прежнее', () {
      final history = steadyHistory(days: 60);
      final a = ForecastEngine.generate(
          transactions: history, currentBalance: 5000, days: 7);
      final b = ForecastEngine.generate(
        transactions: history,
        currentBalance: 5000,
        days: 7,
        asOf: DateTime.now(),
      );
      expect(a.p50.length, b.p50.length);
      expect(a.historyDaysSpan, b.historyDaysSpan);
    });
  });
}

final DateTime _d = DateTime(2026, 7, 4);
